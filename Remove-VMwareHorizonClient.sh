#!/usr/bin/env bash
# ============================================================
# VMware Horizon Client - Complete Removal Script (macOS)
# ============================================================
#
# Removes VMware Horizon Client and all of its associated
# components from a Mac: the main app, USB redirection, RTAV
# (real-time audio/video), client drive redirection, virtual
# printing/scanner redirection helpers, launch agents/daemons,
# and leftover user/system files.
#
# Usage:
#   chmod +x Remove-VMwareHorizonClient.sh
#   ./Remove-VMwareHorizonClient.sh
#
# Needs admin rights for system-level components and will
# prompt for your password via sudo.
# ============================================================

set -u

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

write_step() { printf "\n${CYAN}>> %s${NC}\n" "$1"; }
write_ok()   { printf "   ${GREEN}[OK]${NC} %s\n" "$1"; }
write_warn() { printf "   ${YELLOW}[WARN]${NC} %s\n" "$1"; }
write_err()  { printf "   ${RED}[ERROR]${NC} %s\n" "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    write_err "This script is for macOS only."
    exit 1
fi

APP_PATH="/Applications/VMware Horizon Client.app"

# -----------------------------------------------------------------
# 1. Quit Horizon Client if it's running
# -----------------------------------------------------------------
write_step "Quitting VMware Horizon Client if it's running..."
if pgrep -f "VMware Horizon Client" >/dev/null 2>&1; then
    osascript -e 'tell application "VMware Horizon Client" to quit' >/dev/null 2>&1
    sleep 2
    pkill -f "VMware Horizon Client" >/dev/null 2>&1
    write_ok "VMware Horizon Client closed"
else
    write_ok "VMware Horizon Client was not running"
fi

# -----------------------------------------------------------------
# 2. Uninstall via Homebrew cask, if installed that way
# -----------------------------------------------------------------
write_step "Checking for a Homebrew installation..."
if command -v brew >/dev/null 2>&1 && brew list --cask vmware-horizon-client >/dev/null 2>&1; then
    brew uninstall --cask --zap vmware-horizon-client
    write_ok "Removed Homebrew cask 'vmware-horizon-client' (including its --zap files)"
else
    write_ok "Not installed via Homebrew (skip)"
fi

# -----------------------------------------------------------------
# 3. Unload and remove LaunchAgents / LaunchDaemons
# -----------------------------------------------------------------
write_step "Removing launch agents and daemons..."

LAUNCH_DIRS=(
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
    "$HOME/Library/LaunchAgents"
)

for dir in "${LAUNCH_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r plist; do
        [[ -z "$plist" ]] && continue
        label=$(basename "$plist" .plist)
        if [[ "$dir" == "/Library/LaunchDaemons" ]]; then
            sudo launchctl bootout system "$plist" 2>/dev/null
            sudo rm -f "$plist" && write_ok "Removed daemon: $plist"
        else
            launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null
            rm -f "$plist" 2>/dev/null || sudo rm -f "$plist"
            write_ok "Removed agent: $plist"
        fi
    done < <(grep -ril -e "vmware.*horizon" -e "vmware\.florida" -e "vmware\.viewusbd" -e "vmware\.viewcdr" -e "vmware\.rtav" -e "vmware\.hzn" -e "vmware\.tsdr" "$dir" 2>/dev/null; find "$dir" -iname "*horizon*" -o -iname "com.vmware.florida*" -o -iname "com.vmware.viewusbd*" -o -iname "com.vmware.viewcdr*" -o -iname "com.vmware.rtav*" -o -iname "com.vmware.hzn*" -o -iname "com.vmware.tsdr*" 2>/dev/null)
done
write_ok "Done scanning launch agents/daemons"

# -----------------------------------------------------------------
# 4. Remove the application bundle
# -----------------------------------------------------------------
write_step "Removing VMware Horizon Client.app..."
if [[ -d "$APP_PATH" ]]; then
    if sudo rm -rf "$APP_PATH"; then
        write_ok "Deleted: $APP_PATH"
    else
        write_err "Could not delete $APP_PATH"
    fi
else
    write_ok "Not found (skip): $APP_PATH"
fi

# -----------------------------------------------------------------
# 5. Remove system extensions (USB/driver helpers)
# -----------------------------------------------------------------
write_step "Checking for VMware Horizon system extensions..."
EXT_MATCHES=$(systemextensionsctl list 2>/dev/null | grep -i -e vmware -e horizon || true)
if [[ -n "$EXT_MATCHES" ]]; then
    write_warn "Found system extension(s) still registered:"
    echo "$EXT_MATCHES" | sed 's/^/      /'
    write_warn "macOS requires removing these from System Settings > Privacy & Security > Login Items & Extensions (they can't be force-removed by a script)."
else
    write_ok "No VMware Horizon system extensions found"
fi

# -----------------------------------------------------------------
# 6. Remove leftover user files
# -----------------------------------------------------------------
write_step "Cleaning up user data folders and files..."

USER_PATHS=(
    "$HOME/Library/Application Support/VMware Horizon Client"
    "$HOME/Library/Application Support/VMware"
    "$HOME/Library/Preferences/com.vmware.horizon.plist"
    "$HOME/Library/Preferences/com.vmware.viewclient.plist"
    "$HOME/Library/Caches/com.vmware.horizon"
    "$HOME/Library/Caches/com.vmware.viewclient"
    "$HOME/Library/Logs/VMware Horizon Client"
    "$HOME/Library/Saved Application State/com.vmware.horizon.savedState"
    "$HOME/Library/Saved Application State/com.vmware.viewclient.savedState"
)

for path in "${USER_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        if rm -rf "$path"; then
            write_ok "Deleted: $path"
        else
            write_warn "Could not delete: $path"
        fi
    else
        write_ok "Not found (skip): $path"
    fi
done

# -----------------------------------------------------------------
# 7. Remove leftover system-wide files
# -----------------------------------------------------------------
write_step "Cleaning up system-wide support files..."

SYSTEM_PATHS=(
    "/Library/Application Support/VMware Horizon Client"
    "/Library/Preferences/com.vmware.horizon.plist"
)

for path in "${SYSTEM_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        if sudo rm -rf "$path"; then
            write_ok "Deleted: $path"
        else
            write_warn "Could not delete: $path"
        fi
    else
        write_ok "Not found (skip): $path"
    fi
done

# -----------------------------------------------------------------
# 8. Remove package receipts (only present for .pkg installs)
# -----------------------------------------------------------------
write_step "Removing package receipts..."
RECEIPTS=$(pkgutil --pkgs 2>/dev/null | grep -i -e vmware -e horizon || true)
if [[ -n "$RECEIPTS" ]]; then
    while IFS= read -r pkg_id; do
        sudo pkgutil --forget "$pkg_id" && write_ok "Forgot receipt: $pkg_id"
    done <<< "$RECEIPTS"
else
    write_ok "No package receipts found (skip)"
fi

# -----------------------------------------------------------------
# 9. Done
# -----------------------------------------------------------------
printf "\n${CYAN}============================================================${NC}\n"
printf "${CYAN} Done! VMware Horizon Client has been removed.${NC}\n"
printf " If any system extensions were listed above, finish removing\n"
printf " them in System Settings > Privacy & Security > Login Items\n"
printf " & Extensions, then restart your Mac.\n"
printf "${CYAN}============================================================${NC}\n\n"
