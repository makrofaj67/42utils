#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="$HOME/homemover_script.log"
MIN_SIZE_MB=${1:-50}

USER_ID=$(whoami)
TOTAL_MOVED_MB=0

# Initialize log file (Append mode)
echo "----------------------------------------------------------------" >> "$LOG_FILE"
date '+%Y-%m-%d %H:%M:%S - Homemover Script Started' >> "$LOG_FILE"

log_msg() {
    echo -e "$1"
}

log_cmd() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - CMD: $*" >> "$LOG_FILE"
}

log_res() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - RESULT: $*" >> "$LOG_FILE"
}

log_hdr() {
    echo -e "\n[ FOR DIRECTORY: $1 ]" >> "$LOG_FILE"
}

format_size() {
    local mb=$1
    if [ "$mb" -ge 1024 ]; then
        echo "$((mb / 1024)) GB"
    else
        echo "$mb MB"
    fi
}

if [ -d "/sgoinfre" ]; then
    TARGET_DISK="sgoinfre"
    TARGET_BASE="/sgoinfre/$USER_ID/home"
elif [ -d "/goinfre" ]; then
    TARGET_DISK="goinfre"
    TARGET_BASE="/goinfre/$USER_ID/home"
else
    log_msg "${RED}[FATAL] No sgoinfre or goinfre drive found! Aborting operation.${NC}"
    exit 1
fi


clear
log_msg "${RED}${BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
log_msg "                      DATA LOSS WARNING"
log_msg "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
log_msg "${YELLOW}sgoinfre/goinfre drives can be wiped by the system at any time."
log_msg "This script frees up your quota by moving large directories."
log_msg "Minimum size threshold: ${BLUE}$MIN_SIZE_MB MB${NC}"
log_msg "${RED}${BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}\n"

log_msg "--- Homemover Script Started (Min Size: $MIN_SIZE_MB MB) ---"

get_size_mb() {
    local size_kb=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
    echo $((${size_kb:-0} / 1024))
}

move_and_link() {
    local src="$1"
    local rel="${src#$HOME/}"
    local dest="$TARGET_BASE/$rel"
    
    log_hdr "$src"
    
    if [ -d "$dest" ]; then
        log_msg "    ${RED}[ERROR]${NC} Directory already exists at destination (Operation aborted): $dest"
        return 1
    fi
    
    mkdir -p "$(dirname "$dest")"
    echo -e "    ${BLUE}Moving to target disk...${NC}"
    
    log_cmd "rsync/cp -ahXA --info=progress2 --no-inc-recursive \"$src\" \"$(dirname "$dest")/\""
    if command -v rsync >/dev/null 2>&1; then
        rsync -ahXA --info=progress2 --no-inc-recursive "$src" "$(dirname "$dest")/"
    else
        log_msg "    ${YELLOW}[INFO]${NC} rsync not found, using cp -a..."
        cp -a "$src" "$(dirname "$dest")/"
    fi
    status=$?
    echo ""
    
    if [ $status -eq 0 ]; then
        log_res "SUCCESS"
        local size_mb=$(get_size_mb "$dest")
        TOTAL_MOVED_MB=$((TOTAL_MOVED_MB + size_mb))
        
        log_cmd "rm -rf \"$src\""
        rm -rf "$src"
        
        log_cmd "ln -s \"$dest\" \"$src\""
        ln -s "$dest" "$src"
        
        log_msg "    ${GREEN}[OK]${NC} ~/$rel successfully moved and linked."
    else
        log_res "FAILED (Exit Code: $status)"
        log_msg "    ${RED}[ERROR]${NC} An error occurred while moving ~/$rel!"
        log_msg "    ${YELLOW}Cleaning up partial copy...${NC}"
        log_cmd "rm -rf \"$dest\" (cleanup after failed rsync)"
        rm -rf "$dest"
    fi
}


log_msg "${BLUE}Target drive to use: /$TARGET_DISK${NC}"
log_msg "${BLUE}Scanning home directory...${NC}\n"

while IFS= read -r item; do
    [ -d "$item" ] || continue
    [ -L "$item" ] && continue
    
    rel="${item#$HOME/}"
    dest="$TARGET_BASE/$rel"

    if [ -e "$dest" ]; then
        continue
    fi

    if [ "$rel" = "bin" ]; then
        continue
    fi

    if [ "$rel" = ".local" ]; then
        target_sub="$HOME/.local/share"
        dest_sub="$TARGET_BASE/.local/share"
        
        if [ -d "$target_sub" ] && [ ! -L "$target_sub" ]; then
            if [ -e "$dest_sub" ]; then
                continue
            fi
            size=$(get_size_mb "$target_sub")
            if [ "$size" -ge "$MIN_SIZE_MB" ]; then
                log_msg "${YELLOW}[EXCEPTION]${NC} ~/.local/share directory is large ($size MB)."
                read -p "  Do you want to move this folder? [y/N]: " res
                if [ "$res" = "y" ] || [ "$res" = "Y" ]; then
                    move_and_link "$target_sub"
                else
                    log_msg "  -> Skipped."
                fi
            fi
        fi
        continue
    fi

    size=$(get_size_mb "$item")
    
    if [ "$size" -ge "$MIN_SIZE_MB" ]; then
        log_msg "${YELLOW}[CANDIDATE]${NC} ~/$rel ($size MB)"
        read -p "  Do you want to move this folder? [y/N]: " res
        if [ "$res" = "y" ] || [ "$res" = "Y" ]; then
            move_and_link "$item"
        else
            log_msg "  -> Skipped."
        fi
    fi
done < <(find "$HOME" -maxdepth 1 -mindepth 1 | sort)

# Final Summary
HOME_STATS=$(df -m "$HOME" | tail -n 1)
HOME_TOTAL=$(echo "$HOME_STATS" | awk '{print $2}')
HOME_FREE=$(echo "$HOME_STATS" | awk '{print $4}')

log_msg "\n${GREEN}${BOLD}Operation completed.${NC}"
log_msg "${BLUE}Total Moved in this session:${NC} $(format_size $TOTAL_MOVED_MB)"
log_msg "${BLUE}Home Partition Free Space:${NC} $(format_size $HOME_FREE) / $(format_size $HOME_TOTAL)"
log_msg "Log file: $LOG_FILE\n"