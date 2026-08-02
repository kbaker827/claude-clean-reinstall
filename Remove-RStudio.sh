#!/usr/bin/env bash
# ============================================================
# RStudio Desktop - Complete Removal Script (macOS)
# ============================================================
#
# Removes RStudio Desktop and all of its associated files from
# a Mac. Does NOT remove R itself, only RStudio.
#
# Usage:
#   chmod +x Remove-RStudio.sh
#   ./Remove-RStudio.sh
#
# Some steps (deleting the .app bundle, package receipts) need
# admin rights and will prompt for your password via sudo.
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

APP_PATH="/Applications/RStudio.app"

# -----------------------------------------------------------------
# 1. Quit RStudio if it's running
# -----------------------------------------------------------------
write_step "Quitting RStudio if it's running..."
if pgrep -x "RStudio" >/dev/null 2>&1; then
    osascript -e 'tell application "RStudio" to quit' >/dev/null 2>&1
    sleep 2
    pkill -x "RStudio" >/dev/null 2>&1
    write_ok "RStudio closed"
else
    write_ok "RStudio was not running"
fi

# -----------------------------------------------------------------
# 2. Uninstall via Homebrew cask, if installed that way
# -----------------------------------------------------------------
write_step "Checking for a Homebrew installation..."
if command -v brew >/dev/null 2>&1 && brew list --cask rstudio >/dev/null 2>&1; then
    brew uninstall --cask --zap rstudio
    write_ok "Removed Homebrew cask 'rstudio' (including its --zap files)"
else
    write_ok "Not installed via Homebrew (skip)"
fi

# -----------------------------------------------------------------
# 3. Remove the application bundle
# -----------------------------------------------------------------
write_step "Removing RStudio.app..."
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
# 4. Remove user data, preferences, caches, and state
# -----------------------------------------------------------------
write_step "Cleaning up user data folders and files..."

PATHS_TO_DELETE=(
    "$HOME/Library/Application Support/RStudio"
    "$HOME/Library/Application Support/RStudio-Desktop"
    "$HOME/Library/Application Support/Rstudio"
    "$HOME/.local/share/rstudio"
    "$HOME/.rstudio-desktop"
    "$HOME/.rstudio"
    "$HOME/Library/Caches/RStudio"
    "$HOME/Library/Caches/org.rstudio.RStudio"
    "$HOME/Library/Caches/com.rstudio.desktop"
    "$HOME/Library/Preferences/com.rstudio.desktop.plist"
    "$HOME/Library/Preferences/org.rstudio.RStudio.plist"
    "$HOME/Library/Saved Application State/com.rstudio.desktop.savedState"
    "$HOME/Library/Saved Application State/org.rstudio.RStudio.savedState"
    "$HOME/Library/HTTPStorages/com.rstudio.desktop"
    "$HOME/Library/WebKit/com.rstudio.desktop"
    "$HOME/Library/Logs/RStudio"
)

for path in "${PATHS_TO_DELETE[@]}"; do
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
# 5. Remove package receipts (only present for .pkg installs)
# -----------------------------------------------------------------
write_step "Removing package receipts..."
RECEIPTS=$(pkgutil --pkgs 2>/dev/null | grep -i rstudio || true)
if [[ -n "$RECEIPTS" ]]; then
    while IFS= read -r pkg_id; do
        sudo pkgutil --forget "$pkg_id" && write_ok "Forgot receipt: $pkg_id"
    done <<< "$RECEIPTS"
else
    write_ok "No package receipts found (skip)"
fi

# -----------------------------------------------------------------
# 6. Done
# -----------------------------------------------------------------
printf "\n${CYAN}============================================================${NC}\n"
printf "${CYAN} Done! RStudio Desktop has been removed.${NC}\n"
printf " Note: R itself was not removed. To remove R, uninstall the\n"
printf " R.framework separately (e.g. via 'brew uninstall --cask r' or\n"
printf " by deleting /Library/Frameworks/R.framework).\n"
printf "${CYAN}============================================================${NC}\n\n"
