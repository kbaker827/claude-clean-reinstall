# Claude Desktop - Clean Reinstall Script

**A PowerShell script to completely remove and reinstall Claude Desktop on Windows, fixing Cowork virtualization issues.**

## 🎯 What It Does

This script performs a complete clean reinstall of Claude Desktop with special attention to the **Cowork** feature's virtualization requirements.

### Features

- ✅ **Enables virtualization** - Virtual Machine Platform (required by Cowork), optionally Hyper-V
- ✅ **Checks the hypervisor** - Warns if VT-x/AMD-V is off in firmware, fixes `hypervisorlaunchtype Off`
- ✅ **Backs up your settings** - Copies `claude_desktop_config.json` (MCP servers) and other settings to your Desktop first
- ✅ **Full uninstallation** - Removes MSIX packages (including duplicates and provisioned copies) and classic installs
- ✅ **Stops/removes CoworkVMService** - Cleans up the Cowork service
- ✅ **Deletes leftover data** - Cleans up Claude's AppData folders
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

From a PowerShell window opened with **Run as administrator** (replace `<owner>` with the GitHub account hosting this repo):

```powershell
irm https://raw.githubusercontent.com/<owner>/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1 | iex
```

To pass options with the one-liner:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/<owner>/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1))) -Force
```

Or download and run it (opens an elevated window for you):

```powershell
# 1. Download the script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/<owner>/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1" -OutFile "$env:TEMP\Reset-ClaudeDesktop.ps1"

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

> ⚠️ Use your **own** Windows account elevated as admin. If you elevate with a *different* admin account, the per-user cleanup applies to that account instead - the script warns you if it detects this.

### Options

| Parameter | What it does |
|-----------|--------------|
| `-Force` | Skip the confirmation prompts (never reboots on its own) |
| `-EnableHyperV` | Also enable full Hyper-V and Windows Hypervisor Platform (not needed by Cowork; not available on Windows Home) |
| `-SkipBackup` | Don't back up Claude Desktop settings |
| `-SkipInstall` | Only uninstall and clean up; don't reinstall |

## 📋 What the Script Does

### Step 1: Check Virtualization Support

- Enables **Virtual Machine Platform** (the only feature Cowork requires)
- With `-EnableHyperV`, also enables `Microsoft-Hyper-V-All` and `HypervisorPlatform`
- Warns if CPU virtualization is disabled in BIOS/UEFI
- Sets `hypervisorlaunchtype` back to `Auto` if VMware/VirtualBox turned it off

> ⚠️ **Requires a reboot** if anything was just enabled. The script stops there - reboot, then run it again.

### Step 2: Confirm

Asks before deleting anything (skip with `-Force`).

### Step 3: Back Up Settings

Copies the `*.json` settings files from `%APPDATA%\Claude` (and the MSIX equivalent) to `Desktop\Claude-Backup-<date>`.

> 🔑 `claude_desktop_config.json` can contain API keys for your MCP servers - delete the backup once you've restored what you need.

### Step 4: Close Claude and Stop CoworkVMService

Closes running Claude Desktop windows (leaves the Claude Code CLI alone) and stops the Cowork service.

### Step 5: Uninstall Claude Desktop

Removes:
- Every `Claude` MSIX registration for your user
- Any machine-wide provisioned `Claude` package
- Classic installs listed under *Apps & features* (matched by exact name, so other apps are untouched)
- `CoworkVMService`, if it was left behind

### Step 6: Clean Leftover Folders

```
%APPDATA%\Claude
%LOCALAPPDATA%\Claude
%LOCALAPPDATA%\AnthropicClaude
%LOCALAPPDATA%\Packages\Claude_pzs8sxjxfjjc
```

### Step 7: Download Installer

Downloads the latest installer from the same link as [claude.com/download](https://claude.com/download):
```
https://claude.ai/api/desktop/win32/<x64|arm64>/setup/latest/redirect
```
Then checks its Authenticode signature is valid and issued to Anthropic.

### Step 8: Run Installer

Runs the installer and waits for it to finish. Afterwards, launch Claude from the **Start menu** (so it doesn't run as Administrator).

## 🖥️ Output Example

```
>> Checking virtualization support...
   [OK] Windows hypervisor is running
   [OK] Virtual Machine Platform: already enabled

   This will uninstall Claude Desktop and DELETE its local data for 'PC\me'
   (chat history syncs from your account; local settings are backed up first).

   Continue? (y/n): y

>> Backing up Claude Desktop settings...
   [OK] Backed up 2 settings file(s) to: C:\Users\me\Desktop\Claude-Backup-20260928-101500

>> Closing Claude Desktop...
   [OK] Closed 4 Claude process(es)
   [OK] CoworkVMService stopped

>> Uninstalling Claude Desktop...
   [OK] Removed MSIX package: Claude_1.0.0.0_x64__pzs8sxjxfjjc

>> Cleaning up leftover folders...
   [OK] Deleted: C:\Users\me\AppData\Roaming\Claude
   [OK] Not found (skip): C:\Users\me\AppData\Local\Claude
   ...

>> Downloading latest Claude Desktop installer...
   [OK] Downloaded x64 installer (150.2 MB) to: C:\Users\me\AppData\Local\Temp\Claude-Setup-x64.exe
   [OK] Signature verified: Anthropic, PBC

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
| `1` | Failed or cancelled (not admin, download/signature failure, user said no) |
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

Download the installer manually from https://claude.com/download and run it.

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
   %LOCALAPPDATA%\AnthropicClaude
   %LOCALAPPDATA%\Packages\Claude_pzs8sxjxfjjc
   ```

## 🔒 Safety

- ⚠️ **Deletes local Claude Desktop data** - settings are backed up to your Desktop first (unless `-SkipBackup`)
- ✅ **Only touches Claude Desktop** - apps are matched by exact name; the Claude Code CLI is left alone
- ✅ **Verifies the download** - only runs an installer signed by Anthropic
- ✅ **Asks before destructive steps and before rebooting**

## 📄 Files

| File | Description |
|------|-------------|
| `Reset-ClaudeDesktop.ps1` | Main PowerShell script |
| `PSScriptAnalyzerSettings.psd1` | Lint settings used by CI |
| `README.md` | This documentation |

## 🤝 Contributing

Found an issue or have an improvement? Open an issue or PR! CI runs PSScriptAnalyzer on every push.

## 📄 License

[MIT License](LICENSE) - free to use and distribute.

## 🔗 Links

- **Claude Desktop:** https://claude.com/download
- **Deploying Claude Desktop for Windows:** https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows
- **Anthropic Support:** https://support.claude.com

---

**Fix Claude Desktop and Cowork issues with one script! 🚀**
