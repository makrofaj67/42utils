# xwpbg

## INSTALLATION

Download and compile from source:

```bash
mkdir -p "$HOME"/.local/bin/ && gcc x11_wp_layer.c -o "$HOME"/.local/bin/xwpbg -lX11 -lXext -ljpeg -lpng -Wall -Wextra
```

Add the following to your shell configuration file:

```bash
export PATH="$PATH:$HOME/.local/bin/"
wpbg(){
    xwpbg "$HOME"/Pictures/Wallpapers/image.png "$@"
}
```

## USAGE

```bash
wpbg
```

```bash
xwpbg "$HOME"/Pictures/Wallpapers/image.jpg
```

```bash
xwpbg "$HOME"/Pictures/Wallpapers/image.png --foreground
```
