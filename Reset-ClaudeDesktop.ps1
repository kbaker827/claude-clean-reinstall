# ============================================================
# Claude Desktop - Clean Reinstall Script
# Run as Administrator in PowerShell
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n>> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "   [WARN] $Message" -ForegroundColor Yellow
}

# -----------------------------------------------------------------
# 1. Check and enable virtualization (required for Cowork)
# -----------------------------------------------------------------
Write-Step "Checking virtualization support..."

$rebootNeeded = $false

$features = @(
    @{ Name = "Microsoft-Hyper-V-All"; Label = "Hyper-V" },
    @{ Name = "VirtualMachinePlatform"; Label = "Virtual Machine Platform" },
    @{ Name = "HypervisorPlatform"; Label = "Windows Hypervisor Platform" }
)

foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue).State
    if ($state -eq "Enabled") {
        Write-OK "$($feature.Label): Already enabled"
    }
    else {
        Write-Warn "$($feature.Label): NOT enabled - attempting to enable..."
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -All -NoRestart -ErrorAction Stop
            Write-OK "$($feature.Label): Enabled successfully"
            if ($result.RestartNeeded) { $rebootNeeded = $true }
        }
        catch {
            Write-Warn "$($feature.Label): Could not enable - $_"
            Write-Host "   This may be blocked by Group Policy (Intune/GPO). Contact your IT admin." -ForegroundColor Yellow
        }
    }
}

if ($rebootNeeded) {
    Write-Host "`n   *** A REBOOT IS REQUIRED to finish enabling virtualization. ***" -ForegroundColor Red
    Write-Host "   After rebooting, re-run this script to complete the Claude reinstall." -ForegroundColor Yellow
    $reboot = Read-Host "`n   Reboot now? (y/n)"
    if ($reboot -eq "y") { Restart-Computer -Force }
    else { Write-Host "   Exiting. Please reboot manually then re-run the script."; exit }
}

# -----------------------------------------------------------------
# 2. Stop CoworkVMService if running
# -----------------------------------------------------------------
Write-Step "Stopping CoworkVMService..."
$svc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
if ($svc) {
    try {
        Stop-Service -Name "CoworkVMService" -Force
        sc.exe delete "CoworkVMService" | Out-Null
        Write-OK "CoworkVMService stopped and removed"
    }
    catch {
        Write-Warn "Could not remove CoworkVMService: $_"
    }
}
else {
    Write-OK "CoworkVMService not found (already clean)"
}

# -----------------------------------------------------------------
# 3. Uninstall Claude Desktop
# -----------------------------------------------------------------
Write-Step "Uninstalling Claude Desktop..."

$msixApp = Get-AppxPackage -Name "*Claude*" -ErrorAction SilentlyContinue
if ($msixApp) {
    Remove-AppxPackage -Package $msixApp.PackageFullName
    Write-OK "Removed MSIX package: $($msixApp.Name)"
}
else {
    Write-OK "No MSIX package found"
}

$uninstallers = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
"HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
Get-ItemProperty |
Where-Object { $_.DisplayName -like "*Claude*" }

foreach ($u in $uninstallers) {
    if ($u.UninstallString) {
        Write-OK "Running uninstaller for: $($u.DisplayName)"
        Start-Process "cmd.exe" -ArgumentList "/c $($u.UninstallString) /S" -Wait -ErrorAction SilentlyContinue
    }
}

# -----------------------------------------------------------------
# 4. Delete leftover data folders
# -----------------------------------------------------------------
Write-Step "Cleaning up AppData folders..."

$foldersToDelete = @(
    "$env:APPDATA\Claude",
    "$env:LOCALAPPDATA\Claude",
    "$env:LOCALAPPDATA\Packages\Claude_pzs8sxjxfjjc"
)

foreach ($folder in $foldersToDelete) {
    if (Test-Path $folder) {
        try {
            Remove-Item -Recurse -Force $folder
            Write-OK "Deleted: $folder"
        }
        catch {
            Write-Warn "Could not delete $folder - $_"
        }
    }
    else {
        Write-OK "Not found (skip): $folder"
    }
}

# -----------------------------------------------------------------
# 5. Download fresh installer
# -----------------------------------------------------------------
Write-Step "Downloading latest Claude Desktop installer..."

$installerPath = "$env:TEMP\ClaudeSetup.exe"

try {
    Invoke-WebRequest -Uri "https://storage.googleapis.com/osprey-downloads-c02d6b0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe" `
        -OutFile $installerPath -UseBasicParsing
    Write-OK "Downloaded to: $installerPath"
}
catch {
    Write-Warn "Auto-download failed. Please download manually from: https://claude.com/download"
    Write-Host "   Then run the installer as Administrator." -ForegroundColor Yellow
    exit
}

# -----------------------------------------------------------------
# 6. Run installer
# -----------------------------------------------------------------
Write-Step "Running installer..."
Write-Host "   The installer window will open. Follow the prompts." -ForegroundColor White

Start-Process -FilePath $installerPath -Verb RunAs -Wait
Write-OK "Installer completed"

# -----------------------------------------------------------------
# 7. Done
# -----------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Done! Launch Claude Desktop and check the Cowork tab." -ForegroundColor Cyan
Write-Host " If Cowork still fails, check Event Viewer:" -ForegroundColor Cyan
Write-Host "   Event Viewer > Windows Logs > Application" -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan
