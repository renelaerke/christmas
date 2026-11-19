#!/usr/bin/env bash
# Installs JuleHygge for the current user, without root:
#   ~/.local/share/JuleHygge/JuleHygge      the app (a folder you can write to, so it can update itself)
#   ~/.local/bin/julehygge                  a link to it, to start it from a terminal
#   ~/.local/share/applications/julehygge.desktop and the snowflake icon: "JuleHygge" in the app menu
#
#   ./install.sh               install (or update) from the folder this script is in, and start it
#   ./install.sh --autostart   also start it when you log in (or tick "Start ved login" in its menu later)
#   ./install.sh --no-start    install, but do not start it now
#   ./install.sh --uninstall   remove all of the above (your settings in ~/.config/JuleHygge are kept)
#
# Run it from the unpacked JuleHygge-linux-x86_64.tar.gz.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
app_dir=$data/JuleHygge
exe=$app_dir/JuleHygge
link=$HOME/.local/bin/julehygge
menu_entry=$data/applications/julehygge.desktop
icon=$data/icons/hicolor/256x256/apps/julehygge.png
autostart_entry=$config/autostart/julehygge.desktop

autostart=0
start=1
for arg in "$@"; do
    case "$arg" in
        --autostart) autostart=1 ;;
        --no-start) start=0 ;;
        --uninstall)
            pkill -x JuleHygge 2>/dev/null || true
            rm -f "$link" "$menu_entry" "$icon" "$autostart_entry"
            rm -rf "$app_dir"
            echo "JuleHygge er fjernet. Indstillingerne i $config/JuleHygge er beholdt."
            exit 0
            ;;
        *) echo "usage: $0 [--autostart] [--no-start] | --uninstall" >&2; exit 2 ;;
    esac
done

if [ ! -x "$src/JuleHygge" ]; then
    echo "JuleHygge not found next to $0: run it from the unpacked JuleHygge-linux-x86_64.tar.gz" >&2
    exit 1
fi

# stop a running copy (it is started again below), then put the new one in place (a rename, so a running file is
# never overwritten)
if [ "$start" = 1 ]; then pkill -x JuleHygge 2>/dev/null && sleep 1 || true; fi
mkdir -p "$app_dir" "$(dirname "$link")" "$(dirname "$menu_entry")"
cp "$src/JuleHygge" "$exe.tmp"
chmod 755 "$exe.tmp"
mv -f "$exe.tmp" "$exe"
ln -sf "$exe" "$link"
"$exe" --write-icon="$icon"

entry() {
    cat <<DESKTOP
[Desktop Entry]
Type=Application
Name=JuleHygge
Comment=Sne, nisser og julekalender på skrivebordet
Exec="$exe"
Icon=julehygge
Terminal=false
Categories=Utility;
DESKTOP
}
entry > "$menu_entry"
if [ "$autostart" = 1 ]; then
    mkdir -p "$(dirname "$autostart_entry")"
    { entry; echo "X-GNOME-Autostart-enabled=true"; } > "$autostart_entry"
fi
command -v update-desktop-database >/dev/null && update-desktop-database -q "$(dirname "$menu_entry")" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true

echo "JuleHygge $("$exe" --version | cut -d' ' -f2) er installeret i $app_dir."
[ "$autostart" = 1 ] && echo "Den starter, når du logger ind." || echo "Vil du have den til at starte ved login, så sæt hak i \"Start ved login\" i dens menu."
if [ "$start" = 1 ]; then
    setsid -f "$exe" >/dev/null 2>&1 < /dev/null
    echo "Den kører nu: se efter snefnugget i panelet."
fi
