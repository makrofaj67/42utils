#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="$HOME/homemover_script.log"
TOTAL_RESTORED_MB=0
MIN_SIZE_MB=${1:-0}

log_msg() {
    echo -e "$1"
}

log_cmd() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [BRINGBACK] CMD: $*" >> "$LOG_FILE"
}

log_res() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [BRINGBACK] RESULT: $*" >> "$LOG_FILE"
}

log_hdr() {
    echo -e "\n[ BRINGING BACK DIRECTORY: $1 ]" >> "$LOG_FILE"
}

format_size() {
    local mb=$1
    if [ "$mb" -ge 1024 ]; then
        echo "$((mb / 1024)) GB"
    else
        echo "$mb MB"
    fi
}

get_size_mb() {
    local size_kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    echo $((${size_kb:-0} / 1024))
}

bring_back() {
    local symlink_path="$1"
    local target_path="$2"
    local rel="${symlink_path#$HOME/}"
    
    log_hdr "$symlink_path"
    
    # Quota check
    local size_mb=$(get_size_mb "$target_path")
    local home_free=$(df -m "$HOME" | tail -n 1 | awk '{print $4}')
    
    if [ "$size_mb" -gt "$home_free" ]; then
        log_msg "    ${RED}[ERROR]${NC} Not enough space in Home to bring back ~/$rel!"
        log_msg "    Size: $size_mb MB | Free: $home_free MB"
        log_res "FAILED (Insufficient space)"
        return 1
    fi

    log_msg "    ${BLUE}Restoring to home directory...${NC}"
    
    # Use a temp dir so a crash doesn't leave us with data in neither place
    local tmp_dest="$(dirname "$symlink_path")/.bring_back_tmp_${rel##*/}"
    
    log_cmd "rsync/cp -ahXA --info=progress2 --no-inc-recursive \"$target_path/\" \"$tmp_dest\""
    if command -v rsync >/dev/null 2>&1; then
        rsync -ahXA --info=progress2 --no-inc-recursive "$target_path/" "$tmp_dest"
    else
        log_msg "    ${YELLOW}[INFO]${NC} rsync not found, using cp -a..."
        cp -a "$target_path/" "$tmp_dest"
    fi
    status=$?
    echo ""
    
    if [ $status -eq 0 ]; then
        log_res "SUCCESS"
        TOTAL_RESTORED_MB=$((TOTAL_RESTORED_MB + size_mb))
        
        # Only now it's safe to remove the symlink and rename tmp
        log_cmd "rm \"$symlink_path\""
        rm "$symlink_path"
        
        log_cmd "mv \"$tmp_dest\" \"$symlink_path\""
        mv "$tmp_dest" "$symlink_path"
        
        log_cmd "rm -rf \"$target_path\""
        rm -rf "$target_path"
        
        log_msg "    ${GREEN}[OK]${NC} ~/$rel restored successfully."
    else
        log_res "FAILED (Exit Code: $status)"
        log_msg "    ${RED}[ERROR]${NC} Failed to restore ~/$rel! (symlink untouched)"
        # Clean up tmp if it was partially created
        rm -rf "$tmp_dest"
    fi
}

clear
log_msg "${RED}${BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
log_msg "                      HOMEBRINGER (UNDO)"
log_msg "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
log_msg "This script moves directories back from sgoinfre/goinfre to Home."
log_msg "Make sure you have enough disk quota in your home directory."
log_msg "${RED}${BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}\n"

# Initialize log file (Append mode)
echo "----------------------------------------------------------------" >> "$LOG_FILE"
date '+%Y-%m-%d %H:%M:%S - Homebringer Script Started' >> "$LOG_FILE"

# Start scanning
log_msg "${BLUE}Scanning home directory for symlinks to sgoinfre/goinfre...${NC}\n"

FOUND=0
while IFS= read -r item; do
    rel="${item#$HOME/}"

    # Special handling for .local/share
    if [ "$rel" = ".local" ]; then
        sub="$HOME/.local/share"
        if [ -L "$sub" ]; then
            target=$(readlink "$sub")
            if [[ "$target" == /sgoinfre/* ]] || [[ "$target" == /goinfre/* ]]; then
                FOUND=1
                size=$(get_size_mb "$target")
                log_msg "${YELLOW}[EXCEPTION]${NC} ~/.local/share points to external drive ($size MB)"
                read -p "  Do you want to bring this folder back to Home? [y/N]: " res
                if [ "$res" = "y" ] || [ "$res" = "Y" ]; then
                    bring_back "$sub" "$target"
                else
                    log_msg "  -> Skipped."
                fi
            fi
        fi
        continue
    fi

    # Only check symlinks for other items
    [ -L "$item" ] || continue
    
    # Read symlink destination
    target=$(readlink "$item")
    
    # Check if it points to sgoinfre or goinfre
    if [[ "$target" == /sgoinfre/* ]] || [[ "$target" == /goinfre/* ]]; then
        FOUND=1
        size=$(get_size_mb "$target")
        
        log_msg "${YELLOW}[LINKED]${NC} ~/$rel points to external drive ($size MB)"
        read -p "  Do you want to bring this folder back to Home? [y/N]: " res
        if [ "$res" = "y" ] || [ "$res" = "Y" ]; then
            bring_back "$item" "$target"
        else
            log_msg "  -> Skipped."
        fi
    fi
done < <(find "$HOME" -maxdepth 1 -mindepth 1 | sort)

if [ $FOUND -eq 0 ]; then
    log_msg "${YELLOW}No linked directories found to bring back.${NC}"
fi

# Final Summary
HOME_STATS=$(df -m "$HOME" | tail -n 1)
HOME_TOTAL=$(echo "$HOME_STATS" | awk '{print $2}')
HOME_FREE=$(echo "$HOME_STATS" | awk '{print $4}')

log_msg "\n${GREEN}${BOLD}Operation completed.${NC}"
log_msg "${BLUE}Total Restored in this session:${NC} $(format_size $TOTAL_RESTORED_MB)"
log_msg "${BLUE}Home Partition Free Space:${NC} $(format_size $HOME_FREE) / $(format_size $HOME_TOTAL)"
log_msg "Log file: $LOG_FILE\n"
