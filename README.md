# Claude Desktop - Clean Reinstall Script

**A PowerShell script to completely remove and reinstall Claude Desktop on Windows, fixing Cowork virtualization issues.**

## 🎯 What It Does

This script performs a complete clean reinstall of Claude Desktop with special attention to the **Cowork** feature's virtualization requirements.

### Features

- ✅ **Enables virtualization** - Virtual Machine Platform (required by Cowork), optionally Hyper-V
- ✅ **Checks the hypervisor** - Warns if VT-x/AMD-V is off in firmware, fixes `hypervisorlaunchtype Off`
- ✅ **Downloads before it deletes** - Gets and verifies the new installer *before* removing anything, so a failed download never leaves you without Claude
- ✅ **Backs up your settings** - Copies `claude_desktop_config.json` (MCP servers) and extension settings to your Desktop first
- ✅ **Full uninstallation** - Removes MSIX packages (including duplicates and provisioned copies) and classic installs
- ✅ **Stops/removes CoworkVMService** - Cleans up the Cowork service
- ✅ **Deletes leftover data** - Cleans up Claude's data folders, including `%LOCALAPPDATA%\Claude-Data` used by current versions
- ✅ **Downloads the official installer** - Correct build for x64 or ARM64
- ✅ **Verifies the installer** - Refuses to run it unless it has a valid Anthropic signature
- ✅ **Safe to run via `irm | iex`** - Never closes your PowerShell window

## 🚀 Quick Start

### Prerequisites

- Windows 10 version 2004+ or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- **Administrator privileges**
- Internet connection

### One-Line Run

From a PowerShell window opened with **Run as administrator**:

```powershell
irm https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1 | iex
```

To pass options with the one-liner:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1))) -Force
```

Or download and run it (opens an elevated window for you):

```powershell
# 1. Download the script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1" -OutFile "$env:TEMP\Reset-ClaudeDesktop.ps1"

# 2. Run as Administrator
Start-Process powershell.exe -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$env:TEMP\Reset-ClaudeDesktop.ps1`"" -Verb RunAs
```

### Step-by-Step

1. **Right-click PowerShell** → **Run as administrator**
2. **Go to** the script folder:
   ```powershell
   cd C:\Path\To\Script
   ```
3. **Run the script**:
   ```powershell
   .\Reset-ClaudeDesktop.ps1
   ```
   If you get an execution-policy error, run `powershell -ExecutionPolicy Bypass -File .\Reset-ClaudeDesktop.ps1` instead.

> ⚠️ Run it from a **separate** PowerShell window, not from a terminal inside Claude Desktop - closing Claude would kill the script halfway. The script refuses to run inside Claude.

> ⚠️ Use your **own** Windows account elevated as admin. If you elevate with a *different* admin account, the per-user cleanup applies to that account instead - the script warns you if it detects this.

### Options

| Parameter | What it does |
|-----------|--------------|
| `-Force` | Skip the confirmation prompts (never reboots on its own) |
| `-EnableHyperV` | Also enable full Hyper-V and Windows Hypervisor Platform (not needed by Cowork; not available on Windows Home) |
| `-SkipBackup` | Don't back up Claude Desktop settings |
| `-SkipInstall` | Only uninstall and clean up; don't reinstall |
| `-InstallerPath <file>` | Use an installer you downloaded yourself from [claude.com/download](https://claude.com/download) (still signature-checked) |

## 📋 What the Script Does

### Step 1: Check Virtualization Support

- Enables **Virtual Machine Platform** (the only feature Cowork requires)
- With `-EnableHyperV`, also enables `Microsoft-Hyper-V-All` and `HypervisorPlatform`
- Warns if CPU virtualization is disabled in BIOS/UEFI
- Sets `hypervisorlaunchtype` back to `Auto` if VMware/VirtualBox turned it off

> ⚠️ **Requires a reboot** if anything was just enabled. The script stops there - reboot, then run it again.

### Step 2: Get the Installer

Downloads the latest installer from the same link as [claude.com/download](https://claude.com/download):
```
https://claude.ai/api/desktop/win32/<x64|arm64>/setup/latest/redirect
```
(or uses the file given with `-InstallerPath`), then checks its Authenticode signature is valid and issued to **Anthropic, PBC**. If either step fails the script stops here, and **nothing has been removed**.

### Step 3: Confirm

Asks before deleting anything (skip with `-Force`).

> ⚠️ Local data includes **Cowork tasks and their files** stored on this PC. Chats sync from your account; local Cowork work does not come back.

### Step 4: Back Up Settings

Copies `claude_desktop_config.json` and the `Claude Extensions Settings` folder from every Claude data folder (`%LOCALAPPDATA%\Claude-Data\*`, `%APPDATA%\Claude` and the MSIX equivalent) to `Desktop\Claude-Backup-<date>`. Sign-in tokens and other app state are deliberately not copied.

> 🔑 `claude_desktop_config.json` can contain API keys for your MCP servers - delete the backup once you've restored what you need.

### Step 5: Close Claude and Stop CoworkVMService

Closes running Claude Desktop processes (including the Claude Code build that Claude Desktop bundles; a standalone Claude Code CLI is left alone) and stops the Cowork service.

### Step 6: Uninstall Claude Desktop

Removes:
- Every `Claude` MSIX registration for your user
- Any machine-wide provisioned `Claude` package
- Classic installs listed under *Apps & features* (matched by exact name, so other apps are untouched)
- `CoworkVMService`, if it was left behind

### Step 7: Clean Leftover Folders

```
%APPDATA%\Claude
%LOCALAPPDATA%\Claude
%LOCALAPPDATA%\Claude-Data
%LOCALAPPDATA%\AnthropicClaude
%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc
```

### Step 8: Run Installer

Runs the installer and waits for it to finish. Afterwards, launch Claude from the **Start menu** (so it doesn't run as Administrator).

## 🖥️ Output Example

```
>> Checking virtualization support...
   [OK] Windows hypervisor is running
   [OK] Virtual Machine Platform: already enabled

>> Getting the latest Claude Desktop installer...
   [OK] Downloaded x64 installer (7.1 MB) to: C:\Users\me\AppData\Local\Temp\Claude-Setup-x64.exe
   [OK] Signature verified: Anthropic, PBC

   This will uninstall Claude Desktop and DELETE its local data for 'PC\me',
   including Cowork tasks and their files stored on this PC.
   (Chats sync from your account; MCP/extension settings are backed up first.)

   Continue? (y/n): y

>> Backing up Claude Desktop settings...
   [OK] Backed up 1 settings item(s) to: C:\Users\me\Desktop\Claude-Backup-20260928-101500

>> Closing Claude Desktop...
   [OK] Closed 12 Claude process(es)
   [OK] CoworkVMService stopped

>> Uninstalling Claude Desktop...
   [OK] Removed MSIX package: Claude_1.0.0.0_x64__pzs8sxrjxfjjc

>> Cleaning up leftover folders...
   [OK] Deleted: C:\Users\me\AppData\Roaming\Claude
   [OK] Not found (skip): C:\Users\me\AppData\Local\Claude
   [OK] Deleted: C:\Users\me\AppData\Local\Claude-Data
   ...

>> Running installer...
   The installer window will open. Follow the prompts.
   [OK] Installer finished
   [OK] Claude Desktop 1.0.0.0 is installed
   [OK] CoworkVMService is registered
```

## 🔢 Exit Codes

When run as a `.ps1` file the script sets an exit code (useful for RMM/Intune):

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Failed or cancelled (not admin, run from inside Claude, download/signature failure, user said no) |
| `3010` | Reboot required - reboot and run again |
| other | The installer's own exit code |

## ⚠️ Troubleshooting

### "This script must be run as Administrator"

Right-click PowerShell → **Run as administrator**, then run the script again.

### "Could not enable [feature]" / blocked by Group Policy

Your IT department may manage Windows features. Ask them to enable **Virtual Machine Platform**.

### "CPU virtualization is disabled in BIOS/UEFI"

Reboot into your firmware settings and enable Intel VT-x / AMD-V (sometimes called "SVM" or "Virtualization Technology").

### Download or signature check fails

Nothing has been removed at this point. The download link can refuse scripted downloads (HTTP 403) because of bot protection or a corporate proxy. Download the installer in your browser from https://claude.com/download, then run:

```powershell
.\Reset-ClaudeDesktop.ps1 -InstallerPath "$env:USERPROFILE\Downloads\<installer file name>.exe"
```

### "This PowerShell session is running inside Claude Desktop"

Open a separate PowerShell window with **Run as administrator** and run the script from there.

### Cowork still doesn't work after reinstall

1. In Claude: **Help → Troubleshooting → Show Logs** and open `supported-features-info.json` to see which check fails
2. Check the virtualization services exist:
   ```powershell
   Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
   Get-Service vmcompute, hns
   ```
3. Check Event Viewer → Windows Logs → Application for `CoworkVMService` or `Claude` errors
4. Virtual machines / VDI without nested virtualization can't run Cowork

### Reboot loop

If the script keeps asking to reboot:
1. Use **Restart**, not Shut down + power on (Fast Startup can skip loading the hypervisor)
2. Run the script again

## 🔧 Manual Steps (If Script Fails)

### Enable Virtualization Manually

```powershell
# Run as Administrator
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
bcdedit /set hypervisorlaunchtype auto
```

Then **restart** and re-run the script.

### Uninstall Claude Manually

1. Windows Settings → Apps → Installed apps
2. Find "Claude" → Uninstall
3. Delete folders:
   ```
   %APPDATA%\Claude
   %LOCALAPPDATA%\Claude
   %LOCALAPPDATA%\Claude-Data
   %LOCALAPPDATA%\AnthropicClaude
   %LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc
   ```

## 🔒 Safety

- ⚠️ **Deletes local Claude Desktop data** - settings are backed up to your Desktop first (unless `-SkipBackup`)
- ✅ **Only touches Claude Desktop** - apps are matched by exact name; a standalone Claude Code CLI is left alone
- ✅ **Downloads before deleting** - a failed download or signature check stops the script before anything is removed
- ✅ **Verifies the download** - only runs an installer signed by Anthropic, PBC
- ✅ **Asks before destructive steps and before rebooting**

## 📄 Files

| File | Description |
|------|-------------|
| `Reset-ClaudeDesktop.ps1` | Main PowerShell script |
| `PSScriptAnalyzerSettings.psd1` | Lint settings used by CI |
| `tests/Reset-ClaudeDesktop.Tests.ps1` | Pester tests for the helper functions (`Invoke-Pester ./tests`) |
| `README.md` | This documentation |

## 🤝 Contributing

Found an issue or have an improvement? Open an issue or PR! CI runs PSScriptAnalyzer, a Windows PowerShell 5.1 parse check and the Pester tests on every push.

## 📄 License

[MIT License](LICENSE) - free to use and distribute.

## 🔗 Links

- **Repository:** https://github.com/kbaker827/claude-clean-reinstall
- **Claude Desktop:** https://claude.com/download
- **Deploying Claude Desktop for Windows:** https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows
- **Anthropic Support:** https://support.claude.com

---

**Fix Claude Desktop and Cowork issues with one script! 🚀**
