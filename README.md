# Claude Desktop - Clean Reinstall Script

**A PowerShell script to completely remove and reinstall Claude Desktop, fixing Cowork virtualization issues.**

> Also included: `Remove-RStudio.sh`, a bash script to completely remove RStudio Desktop from macOS. See [RStudio Removal (macOS)](#-rstudio-removal-macos) below.

## 🎯 What It Does

This script performs a complete clean reinstall of Claude Desktop with special attention to fixing the **Cowork** feature's virtualization requirements.

### Features

- ✅ **Enables virtualization** - Hyper-V, Virtual Machine Platform, Windows Hypervisor Platform
- ✅ **Stops/removes CoworkVMService** - Cleans up the Cowork service
- ✅ **Full uninstallation** - Removes MSIX packages and registry entries
- ✅ **Deletes AppData** - Cleans up all user data folders
- ✅ **Auto-downloads installer** - Gets the latest Claude Desktop version
- ✅ **Runs installer** - Launches the installer as Administrator
- ✅ **Color-coded output** - Easy-to-read progress indicators

## 🚀 Quick Start

### Prerequisites

- Windows 10/11
- PowerShell 5.1 or higher
- **Administrator privileges** (script will fail without them)

### One-Line Run

```powershell
# Download and run directly
irm https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1 | iex
```

Or download and run manually:

```powershell
# 1. Download the script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1" -OutFile "$env:TEMP\Reset-ClaudeDesktop.ps1"

# 2. Run as Administrator
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File $env:TEMP\Reset-ClaudeDesktop.ps1" -Verb RunAs
```

### Step-by-Step

1. **Right-click PowerShell** → **Run as Administrator**
2. **Navigate** to the script folder:
   ```powershell
   cd C:\Path\To\Script
   ```
3. **Run the script**:
   ```powershell
   .\Reset-ClaudeDesktop.ps1
   ```

## 📋 What the Script Does

### Step 1: Check Virtualization Support

Checks and enables required Windows features for Cowork:
- Microsoft-Hyper-V-All
- VirtualMachinePlatform  
- HypervisorPlatform

> ⚠️ **May require reboot** if features were just enabled.

### Step 2: Stop CoworkVMService

Stops and removes the CoworkVMService to prevent conflicts during reinstall.

### Step 3: Uninstall Claude Desktop

Removes:
- MSIX packaged app
- Registry uninstaller entries
- Traditional installer remnants

### Step 4: Clean AppData

Deletes these folders:
```
%APPDATA%\Claude
%LOCALAPPDATA%\Claude
%LOCALAPPDATA%\Packages\Claude_pzs8sxjxfjjc
```

### Step 5: Download Installer

Downloads the latest Claude Desktop installer from the official source:
```
https://storage.googleapis.com/osprey-downloads/.../Claude-Setup-x64.exe
```

### Step 6: Run Installer

Launches the installer with Administrator privileges and waits for completion.

## 🖥️ Output Example

```
>> Checking virtualization support...
   [OK] Hyper-V: Already enabled
   [OK] Virtual Machine Platform: Already enabled
   [OK] Windows Hypervisor Platform: Already enabled

>> Stopping CoworkVMService...
   [OK] CoworkVMService not found (already clean)

>> Uninstalling Claude Desktop...
   [OK] No MSIX package found

>> Cleaning up AppData folders...
   [OK] Not found (skip): C:\Users\...\AppData\Roaming\Claude
   [OK] Deleted: C:\Users\...\AppData\Local\Claude
   [OK] Not found (skip): C:\Users\...\AppData\Local\Packages\Claude_pzs8sxjxfjjc

>> Downloading latest Claude Desktop installer...
   [OK] Downloaded to: C:\Users\...\AppData\Local\Temp\ClaudeSetup.exe

>> Running installer...
   The installer window will open. Follow the prompts.
   [OK] Installer completed

============================================================
 Done! Launch Claude Desktop and check the Cowork tab.
 If Cowork still fails, check Event Viewer:
   Event Viewer > Windows Logs > Application
============================================================
```

## ⚠️ Troubleshooting

### "This script requires administrator privileges"

You must run PowerShell as Administrator. Right-click PowerShell → "Run as Administrator"

### "Could not enable [feature] - blocked by Group Policy"

Your IT department may have disabled virtualization features. Contact your IT admin to enable:
- Hyper-V
- Virtual Machine Platform
- Windows Hypervisor Platform

### Download fails

If the auto-download fails, the script will provide a manual download link:
- Go to https://claude.com/download
- Download and run the installer manually

### Cowork still doesn't work after reinstall

1. Check Event Viewer:
   ```
   Event Viewer > Windows Logs > Application
   ```
2. Look for errors related to "CoworkVMService" or "Claude"
3. Check Windows Features are enabled:
   ```powershell
   Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -like "*Hyper*" -or $_.FeatureName -like "*Virtual*" }
   ```

### Reboot loop

If the script keeps asking to reboot:
1. Reboot your computer
2. Run the script again
3. The second run should complete without requiring another reboot

## 🔧 Manual Steps (If Script Fails)

### Enable Virtualization Manually

```powershell
# Run as Administrator
dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism /online /enable-feature /featurename:HypervisorPlatform /all /norestart
```

Then **reboot** and re-run the script.

### Uninstall Claude Manually

1. Windows Settings → Apps → Installed Apps
2. Find "Claude" → Uninstall
3. Delete folders:
   ```
   %APPDATA%\Claude
   %LOCALAPPDATA%\Claude
   %LOCALAPPDATA%\Packages\Claude_pzs8sxjxfjjc
   ```

## 📝 Requirements

- Windows 10 version 2004+ or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges
- Internet connection (for downloading installer)

## 🔒 Safety

- ✅ **Backs up nothing** - but you can manually backup `%APPDATA%\Claude` before running
- ✅ **Non-destructive** - Only removes Claude-related files
- ✅ **Reversible** - You can always reinstall Claude normally

## 🍏 RStudio Removal (macOS)

**`Remove-RStudio.sh`** completely uninstalls RStudio Desktop from a Mac.

### What It Does

- ✅ Quits RStudio if it's currently running
- ✅ Uninstalls via Homebrew (`brew uninstall --cask --zap rstudio`) if that's how it was installed
- ✅ Deletes `/Applications/RStudio.app`
- ✅ Removes user data, preferences, caches, saved state, and logs
- ✅ Forgets any `pkgutil` package receipts left by a `.pkg` installer
- ✅ Does **not** remove R itself — only RStudio

### Usage

```bash
chmod +x Remove-RStudio.sh
./Remove-RStudio.sh
```

The script will prompt for your password via `sudo` when it needs to delete the application bundle or package receipts.

### Removing R Too

RStudio is just the IDE — the R language runtime is separate. If you also want to remove R:

```bash
# If installed via Homebrew
brew uninstall --cask r

# Manual install
sudo rm -rf /Library/Frameworks/R.framework
sudo rm -rf /Applications/R.app
sudo pkgutil --forget org.r-project.R.*
```

## 🍏 VMware Horizon Client Removal (macOS)

**`Remove-VMwareHorizonClient.sh`** completely uninstalls VMware Horizon Client from a Mac.

### What It Does

- ✅ Quits Horizon Client if it's currently running
- ✅ Uninstalls via Homebrew (`brew uninstall --cask --zap vmware-horizon-client`) if that's how it was installed
- ✅ Unloads and deletes related LaunchAgents/LaunchDaemons (USB redirection, RTAV, drive redirection, etc.)
- ✅ Deletes `/Applications/VMware Horizon Client.app`
- ✅ Flags any lingering system extensions (must be finished off in System Settings)
- ✅ Removes user and system-wide data, preferences, caches, and logs
- ✅ Forgets any `pkgutil` package receipts left by a `.pkg` installer

### Usage

```bash
chmod +x Remove-VMwareHorizonClient.sh
./Remove-VMwareHorizonClient.sh
```

The script will prompt for your password via `sudo` when it needs to remove system daemons, the application bundle, or package receipts.

## 📄 Files

| File | Description |
|------|-------------|
| `Reset-ClaudeDesktop.ps1` | PowerShell script to reinstall Claude Desktop (Windows) |
| `Remove-RStudio.sh` | Bash script to remove RStudio Desktop (macOS) |
| `Remove-VMwareHorizonClient.sh` | Bash script to remove VMware Horizon Client (macOS) |
| `README.md` | This documentation |

## 🤝 Contributing

Found an issue or have an improvement? Open an issue or PR!

## 📄 License

MIT License - Free to use and distribute.

## 🔗 Links

- **Repository:** https://github.com/kbaker827/claude-clean-reinstall
- **Claude Desktop:** https://claude.com/download
- **Anthropic Support:** https://support.anthropic.com

---

**Fix Claude Desktop and Cowork issues with one script! 🚀**
