#!/usr/bin/env bash
# ============================================================
# Microsoft Teams - Complete Removal Script (macOS)
# Removes both "classic" Microsoft Teams and the new
# "Microsoft Teams (work or school)" client, plus all
# associated user data, caches, preferences, and background
# helper processes.
#
# Usage:
#   chmod +x Remove-MicrosoftTeams.sh
#   ./Remove-MicrosoftTeams.sh
#
# Run with sudo as well if you want system-wide (/Library)
# leftovers removed too:
#   sudo ./Remove-MicrosoftTeams.sh
# ============================================================

set -uo pipefail

# -----------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

step()  { printf "\n${CYAN}>> %s${NC}\n" "$1"; }
ok()    { printf "   ${GREEN}[OK]${NC} %s\n" "$1"; }
warn()  { printf "   ${YELLOW}[WARN]${NC} %s\n" "$1"; }

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script only runs on macOS." >&2
    exit 1
fi

IS_ROOT=false
if [[ $EUID -eq 0 ]]; then
    IS_ROOT=true
fi

remove_path() {
    local target="$1"
    local err
    if [[ -e "$target" || -L "$target" ]]; then
        if err=$(rm -rf "$target" 2>&1); then
            ok "Deleted: $target"
        else
            warn "Could not delete: $target ($err)"
        fi
    fi
}

# -----------------------------------------------------------------
# 1. Quit Microsoft Teams and related helpers
# -----------------------------------------------------------------
step "Quitting Microsoft Teams and helper processes..."

TEAMS_PROCESS_NAMES=(
    "Microsoft Teams"
    "Microsoft Teams Helper"
    "Teams"
    "MSTeams"
    "com.microsoft.teams2.launcher"
    "TeamsUpdaterDaemon"
)

for name in "${TEAMS_PROCESS_NAMES[@]}"; do
    osascript -e "tell application \"$name\" to quit" >/dev/null 2>&1
done

for name in "${TEAMS_PROCESS_NAMES[@]}"; do
    if pgrep -f "$name" >/dev/null 2>&1; then
        pkill -f "$name" >/dev/null 2>&1
    fi
done
sleep 1
ok "Teams processes stopped"

# -----------------------------------------------------------------
# 2. Unload and remove LaunchAgents / LaunchDaemons
# -----------------------------------------------------------------
step "Removing Teams launch agents/daemons..."

LAUNCH_ITEMS=(
    "$HOME/Library/LaunchAgents/com.microsoft.teams.TeamsUpdaterDaemon.plist"
    "$HOME/Library/LaunchAgents/com.microsoft.teams2.TeamsUpdaterDaemon.plist"
    "/Library/LaunchAgents/com.microsoft.teams.TeamsUpdaterDaemon.plist"
    "/Library/LaunchDaemons/com.microsoft.teams.TeamsUpdaterDaemon.plist"
)

for plist in "${LAUNCH_ITEMS[@]}"; do
    if [[ -f "$plist" ]]; then
        launchctl unload "$plist" >/dev/null 2>&1
        remove_path "$plist"
    fi
done
ok "Launch agents/daemons cleaned"

# -----------------------------------------------------------------
# 3. Remove login items
# -----------------------------------------------------------------
step "Removing Teams from Login Items..."

osascript <<'EOF' >/dev/null 2>&1
tell application "System Events"
    set loginItems to name of every login item
    repeat with itemName in loginItems
        if itemName contains "Teams" then
            delete login item itemName
        end if
    end repeat
end tell
EOF
ok "Login items cleaned (if any existed)"

# -----------------------------------------------------------------
# 4. Remove application bundles
# -----------------------------------------------------------------
step "Removing Microsoft Teams application(s)..."

APP_PATHS=(
    "/Applications/Microsoft Teams.app"
    "/Applications/Microsoft Teams (work or school).app"
    "/Applications/Microsoft Teams classic.app"
    "$HOME/Applications/Microsoft Teams.app"
    "$HOME/Applications/Microsoft Teams (work or school).app"
)

for app in "${APP_PATHS[@]}"; do
    remove_path "$app"
done

# -----------------------------------------------------------------
# 5. Remove user-level data, caches, preferences, logs
# -----------------------------------------------------------------
step "Cleaning up user data (Application Support, Caches, Preferences, Logs)..."

USER_PATHS=(
    "$HOME/Library/Application Support/Microsoft/Teams"
    "$HOME/Library/Application Support/Microsoft/TeamsMeetingAddin"
    "$HOME/Library/Application Support/Microsoft/Teams (work or school)"
    "$HOME/Library/Caches/com.microsoft.teams"
    "$HOME/Library/Caches/com.microsoft.teams2"
    "$HOME/Library/Caches/com.microsoft.teams.helper"
    "$HOME/Library/HTTPStorages/com.microsoft.teams"
    "$HOME/Library/HTTPStorages/com.microsoft.teams2"
    "$HOME/Library/WebKit/com.microsoft.teams"
    "$HOME/Library/WebKit/com.microsoft.teams2"
    "$HOME/Library/Logs/Microsoft Teams"
    "$HOME/Library/Logs/Teams"
    "$HOME/Library/Preferences/com.microsoft.teams.plist"
    "$HOME/Library/Preferences/com.microsoft.teams2.plist"
    "$HOME/Library/Preferences/com.microsoft.teams.helper.plist"
    "$HOME/Library/Saved Application State/com.microsoft.teams.savedState"
    "$HOME/Library/Saved Application State/com.microsoft.teams2.savedState"
    "$HOME/Library/Cookies/com.microsoft.teams.binarycookies"
)

for path in "${USER_PATHS[@]}"; do
    remove_path "$path"
done

# Container/group-container sandboxed data (used by the new Teams client)
for dir in "$HOME/Library/Containers" "$HOME/Library/Group Containers"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' match; do
        remove_path "$match"
    done < <(find "$dir" -maxdepth 1 -iname "*microsoft.teams*" -print0 2>/dev/null)
done

ok "User data cleaned"

# -----------------------------------------------------------------
# 6. Remove system-wide leftovers (requires sudo)
# -----------------------------------------------------------------
step "Checking for system-wide leftovers..."

if [[ "$IS_ROOT" == true ]]; then
    SYSTEM_PATHS=(
        "/Library/Application Support/Microsoft/Teams"
        "/Library/Preferences/com.microsoft.teams.plist"
        "/Library/Logs/Microsoft Teams"
    )
    for path in "${SYSTEM_PATHS[@]}"; do
        remove_path "$path"
    done
    ok "System-wide leftovers cleaned"
else
    warn "Skipped /Library items - re-run with 'sudo' to remove system-wide leftovers"
fi

# -----------------------------------------------------------------
# 7. Reset Dock (removes any stale/broken Teams icon)
# -----------------------------------------------------------------
step "Refreshing the Dock..."
killall Dock >/dev/null 2>&1 || true
ok "Dock refreshed"

# -----------------------------------------------------------------
# Done
# -----------------------------------------------------------------
printf "\n${CYAN}============================================================${NC}\n"
printf "${CYAN} Done! Microsoft Teams and its data have been removed.${NC}\n"
printf " If you ran this without sudo, re-run as:\n"
printf "   sudo ./Remove-MicrosoftTeams.sh\n"
printf " to also clear any system-wide (/Library) leftovers.\n"
printf "${CYAN}============================================================${NC}\n\n"
