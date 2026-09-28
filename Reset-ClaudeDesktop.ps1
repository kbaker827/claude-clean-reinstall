<#
.SYNOPSIS
    Completely removes Claude Desktop and reinstalls the latest version, fixing
    common Cowork (virtualization) problems along the way.

.DESCRIPTION
    1. Checks that the Windows features Cowork needs are enabled (enables them if not).
    2. Backs up your Claude Desktop settings (claude_desktop_config.json etc.).
    3. Closes Claude, stops CoworkVMService and uninstalls Claude Desktop
       (MSIX package, provisioned package and any classic installer).
    4. Deletes leftover Claude data folders.
    5. Downloads the latest official installer, verifies its signature and runs it.

    Must be run from an elevated (Administrator) PowerShell session.

.PARAMETER Force
    Skip the confirmation prompts. Never reboots automatically.

.PARAMETER EnableHyperV
    Also enable the full Hyper-V role and Windows Hypervisor Platform. Cowork only
    needs Virtual Machine Platform, so this is off by default.

.PARAMETER SkipBackup
    Do not back up Claude Desktop settings before deleting them.

.PARAMETER SkipInstall
    Only uninstall and clean up; do not download or run the installer.

.EXAMPLE
    .\Reset-ClaudeDesktop.ps1

.EXAMPLE
    .\Reset-ClaudeDesktop.ps1 -Force -SkipBackup

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kbaker827/claude-clean-reinstall/main/Reset-ClaudeDesktop.ps1))) -Force
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$EnableHyperV,
    [switch]$SkipBackup,
    [switch]$SkipInstall
)

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------

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

function Write-Fail {
    param([string]$Message)
    Write-Host "   [FAIL] $Message" -ForegroundColor Red
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
    param([string]$Prompt, [switch]$AssumeYes)
    if ($AssumeYes) { return $true }
    $answer = Read-Host "`n   $Prompt (y/n)"
    return ($answer -match '^\s*(y|yes)\s*$')
}

function Split-UninstallCommand {
    # Turns a registry UninstallString into an executable path + arguments,
    # adding a silent switch when the entry doesn't provide a quiet variant.
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [switch]$IsQuiet
    )

    if ($CommandLine -match '(?i)msiexec' -and $CommandLine -match '\{[0-9A-Fa-f-]{36}\}') {
        # MSI entries usually say "/I{GUID}" (repair/modify); force a silent removal instead.
        return [pscustomobject]@{
            FilePath  = "$env:SystemRoot\System32\msiexec.exe"
            Arguments = "/x $($Matches[0]) /qn /norestart"
        }
    }

    if ($CommandLine -match '^\s*"([^"]+)"\s*(.*)$') {
        $file = $Matches[1]; $arguments = $Matches[2].Trim()
    }
    elseif ($CommandLine -match '^\s*(.+?\.exe)(?:\s+(.*))?$') {
        $file = $Matches[1]; $arguments = "$($Matches[2])".Trim()
    }
    else {
        return $null
    }

    if (-not $IsQuiet) {
        if ($arguments -match '--uninstall') {
            # Squirrel (Update.exe --uninstall) uses -s for silent.
            if ($arguments -notmatch '(^|\s)(-s|--silent)(\s|$)') { $arguments = "$arguments -s".Trim() }
        }
        elseif ($arguments -notmatch '(^|\s)/S(\s|$)') {
            $arguments = "$arguments /S".Trim()
        }
    }

    return [pscustomobject]@{ FilePath = $file; Arguments = $arguments }
}

function Get-NativeArchitecture {
    # PROCESSOR_ARCHITECTURE in the registry reflects the OS, even when this
    # PowerShell process is running under x64 emulation on ARM64.
    $arch = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction SilentlyContinue).PROCESSOR_ARCHITECTURE
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

# -----------------------------------------------------------------
# Main
# -----------------------------------------------------------------

function Invoke-ClaudeReset {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [switch]$Force,
        [switch]$EnableHyperV,
        [switch]$SkipBackup,
        [switch]$SkipInstall
    )

    # Scoped to this function so running via "irm | iex" doesn't change the caller's session.
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is extremely slow with the progress bar on PS 5.1

    $serviceName = 'CoworkVMService'
    $packageName = 'Claude'
    $defaultPackageFamily = 'Claude_pzs8sxjxfjjc'

    # -------------------------------------------------------------
    # 0. Pre-flight checks
    # -------------------------------------------------------------
    if ($env:OS -ne 'Windows_NT') {
        Write-Fail 'This script only runs on Windows.'
        return 1
    }

    if (-not (Test-IsAdministrator)) {
        Write-Fail 'This script must be run as Administrator.'
        Write-Host '   Right-click PowerShell > "Run as administrator", then run the script again.' -ForegroundColor Yellow
        return 1
    }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        # The Appx module isn't natively supported in every PowerShell 7 build.
        try { Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop }
        catch { Write-Verbose "Could not import Appx via Windows PowerShell compatibility: $_" }
    }

    # Elevating with a *different* admin account means $env:APPDATA / HKCU point at
    # that account's profile, not the user who actually uses Claude.
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $consoleUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if ($consoleUser -and $consoleUser -ne $currentUser) {
        Write-Warn "Running as '$currentUser' but the signed-in user is '$consoleUser'."
        Write-Warn "Per-user cleanup (AppData, MSIX package) will apply to '$currentUser' only."
        if (-not (Confirm-Action -Prompt 'Continue anyway?' -AssumeYes:$Force)) { return 1 }
    }

    # -------------------------------------------------------------
    # 1. Check and enable virtualization (required for Cowork)
    # -------------------------------------------------------------
    Write-Step 'Checking virtualization support...'

    $rebootNeeded = $false

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($computer -and $computer.HypervisorPresent) {
        Write-OK 'Windows hypervisor is running'
    }
    elseif ($cpu -and $cpu.VirtualizationFirmwareEnabled -eq $false) {
        Write-Warn 'CPU virtualization (Intel VT-x / AMD-V) is disabled in BIOS/UEFI firmware.'
        Write-Host '   Cowork will not work until it is enabled in your firmware settings.' -ForegroundColor Yellow
    }

    $features = @(
        @{ Name = 'VirtualMachinePlatform'; Label = 'Virtual Machine Platform' }
    )
    if ($EnableHyperV) {
        $features += @(
            @{ Name = 'Microsoft-Hyper-V-All'; Label = 'Hyper-V' },
            @{ Name = 'HypervisorPlatform'; Label = 'Windows Hypervisor Platform' }
        )
    }

    foreach ($feature in $features) {
        $info = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name -ErrorAction SilentlyContinue
        $state = if ($info) { [string]$info.State } else { $null }

        if (-not $info) {
            Write-Warn "$($feature.Label): not available on this edition of Windows (skipped)"
        }
        elseif ($state -eq 'Enabled') {
            Write-OK "$($feature.Label): already enabled"
        }
        elseif ($state -eq 'EnablePending') {
            Write-Warn "$($feature.Label): enabled, waiting for a reboot"
            $rebootNeeded = $true
        }
        else {
            Write-Warn "$($feature.Label): not enabled - enabling..."
            try {
                $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature.Name -All -NoRestart -ErrorAction Stop
                Write-OK "$($feature.Label): enabled"
                if ($result.RestartNeeded) { $rebootNeeded = $true }
            }
            catch {
                Write-Warn "$($feature.Label): could not enable - $($_.Exception.Message)"
                Write-Host '   This may be blocked by Group Policy (Intune/GPO). Contact your IT admin.' -ForegroundColor Yellow
            }
        }
    }

    # VMware/VirtualBox installs sometimes turn the Windows hypervisor off at boot.
    $bcd = & bcdedit.exe /enum '{current}' 2>$null
    if ($LASTEXITCODE -eq 0 -and ($bcd | Select-String -Pattern '^\s*hypervisorlaunchtype\s+Off\b' -Quiet)) {
        Write-Warn 'Windows hypervisor is set to not launch at boot (hypervisorlaunchtype = Off) - fixing...'
        & bcdedit.exe /set '{current}' hypervisorlaunchtype auto | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK 'hypervisorlaunchtype set to Auto'
            $rebootNeeded = $true
        }
        else {
            Write-Warn 'Could not change hypervisorlaunchtype. Run: bcdedit /set hypervisorlaunchtype auto'
        }
    }

    if ($rebootNeeded) {
        Write-Host "`n   *** A REBOOT IS REQUIRED to finish enabling virtualization. ***" -ForegroundColor Red
        Write-Host '   Use Restart (not Shut down) so Fast Startup does not skip loading the hypervisor.' -ForegroundColor Yellow
        Write-Host '   After rebooting, run this script again to finish the Claude reinstall.' -ForegroundColor Yellow
        if (-not $Force -and (Confirm-Action -Prompt 'Reboot now?')) {
            Restart-Computer -Force
        }
        else {
            Write-Host '   Exiting. Please restart manually, then run the script again.'
        }
        return 3010
    }

    # -------------------------------------------------------------
    # 2. Confirm before doing anything destructive
    # -------------------------------------------------------------
    Write-Host "`n   This will uninstall Claude Desktop and DELETE its local data for '$currentUser'" -ForegroundColor Yellow
    Write-Host '   (chat history syncs from your account; local settings are backed up first).' -ForegroundColor Yellow
    if (-not (Confirm-Action -Prompt 'Continue?' -AssumeYes:$Force)) {
        Write-Host '   Cancelled. Nothing was changed.'
        return 1
    }

    $packages = @(Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue)
    $packageFamilies = @(@($packages | ForEach-Object { $_.PackageFamilyName }) + $defaultPackageFamily |
        Sort-Object -Unique)

    # -------------------------------------------------------------
    # 3. Back up settings (must happen before the MSIX is removed,
    #    because removing it also deletes its virtualized AppData)
    # -------------------------------------------------------------
    if (-not $SkipBackup) {
        Write-Step 'Backing up Claude Desktop settings...'

        $sources = @(@{ Label = 'AppData'; Path = Join-Path $env:APPDATA 'Claude' })
        foreach ($family in $packageFamilies) {
            $sources += @{
                Label = "MSIX-$family"
                Path  = Join-Path $env:LOCALAPPDATA "Packages\$family\LocalCache\Roaming\Claude"
            }
        }

        $backupRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) ("Claude-Backup-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
        $backedUp = 0
        foreach ($source in $sources) {
            if (-not (Test-Path -LiteralPath $source.Path)) { continue }
            $files = @(Get-ChildItem -LiteralPath $source.Path -Filter '*.json' -File -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { continue }
            $destination = Join-Path $backupRoot $source.Label
            try {
                $null = New-Item -ItemType Directory -Path $destination -Force
                $files | Copy-Item -Destination $destination -Force
                $backedUp += $files.Count
            }
            catch {
                Write-Warn "Could not back up $($source.Path) - $($_.Exception.Message)"
            }
        }

        if ($backedUp -gt 0) {
            Write-OK "Backed up $backedUp settings file(s) to: $backupRoot"
            Write-Host '   Note: claude_desktop_config.json may contain API keys for your MCP servers.' -ForegroundColor Yellow
        }
        else {
            Write-OK 'No settings files found to back up'
        }
    }

    # -------------------------------------------------------------
    # 4. Close Claude and stop CoworkVMService
    # -------------------------------------------------------------
    Write-Step 'Closing Claude Desktop...'

    # Match on install location so the Claude Code CLI (also claude.exe) is left alone.
    $claudeProcesses = @(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -match '\\(WindowsApps\\Claude_|AnthropicClaude\\)' })
    if ($claudeProcesses.Count -gt 0) {
        $claudeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-OK "Closed $($claudeProcesses.Count) Claude process(es)"
    }
    else {
        Write-OK 'Claude is not running'
    }

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        try {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-OK "$serviceName stopped"
        }
        catch {
            Write-Warn "Could not stop $serviceName - $($_.Exception.Message)"
        }
    }
    elseif ($svc) {
        Write-OK "$serviceName is already stopped"
    }
    else {
        Write-OK "$serviceName not found (already clean)"
    }

    # -------------------------------------------------------------
    # 5. Uninstall Claude Desktop
    # -------------------------------------------------------------
    Write-Step 'Uninstalling Claude Desktop...'

    # There can be more than one registration (e.g. in-app updater + MDM), so remove all of them.
    if ($packages.Count -gt 0) {
        foreach ($package in $packages) {
            try {
                Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
                Write-OK "Removed MSIX package: $($package.PackageFullName)"
            }
            catch {
                Write-Warn "Could not remove $($package.PackageFullName) - $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-OK 'No MSIX package found for this user'
    }

    # A provisioned (machine-wide) copy would silently re-register the old version.
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $packageName })
    foreach ($package in $provisioned) {
        try {
            $null = Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop
            Write-OK "Removed provisioned package: $($package.PackageName)"
        }
        catch {
            Write-Warn "Could not remove provisioned package $($package.PackageName) - $($_.Exception.Message)"
        }
    }

    # Classic (non-MSIX) installs. Match the name exactly so other apps with
    # "Claude" in their name are not uninstalled.
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $uninstallers = @(
        foreach ($root in $uninstallRoots) {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue }
        }
    ) | Where-Object { $_.DisplayName -match '^Claude( Desktop)?$' }

    foreach ($entry in @($uninstallers)) {
        $isQuiet = [bool]$entry.QuietUninstallString
        $commandLine = if ($isQuiet) { $entry.QuietUninstallString } else { $entry.UninstallString }
        if (-not $commandLine) { continue }

        $command = Split-UninstallCommand -CommandLine $commandLine -IsQuiet:$isQuiet
        if (-not $command -or -not (Test-Path -LiteralPath $command.FilePath)) {
            Write-Warn "Uninstaller for '$($entry.DisplayName)' not found: $commandLine"
            continue
        }

        Write-Host "   Running uninstaller for: $($entry.DisplayName)" -ForegroundColor White
        try {
            $startArgs = @{ FilePath = $command.FilePath; PassThru = $true; Wait = $true }
            if ($command.Arguments) { $startArgs.ArgumentList = $command.Arguments }
            $proc = Start-Process @startArgs
            if ($proc.ExitCode -in 0, 1605, 3010) {
                Write-OK "Uninstalled: $($entry.DisplayName)"
            }
            else {
                Write-Warn "Uninstaller for '$($entry.DisplayName)' exited with code $($proc.ExitCode)"
            }
        }
        catch {
            Write-Warn "Could not run uninstaller for '$($entry.DisplayName)' - $($_.Exception.Message)"
        }
    }

    # Normally removed along with the package; delete it if it was left behind.
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        & sc.exe delete $serviceName | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Removed leftover $serviceName"
        }
        else {
            Write-Warn "Could not remove $serviceName (sc.exe exit code $LASTEXITCODE)"
        }
    }

    # -------------------------------------------------------------
    # 6. Delete leftover data folders
    # -------------------------------------------------------------
    Write-Step 'Cleaning up leftover folders...'

    $foldersToDelete = @(
        (Join-Path $env:APPDATA 'Claude'),
        (Join-Path $env:LOCALAPPDATA 'Claude'),
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude')   # older (Squirrel) installs
    )
    foreach ($family in $packageFamilies) {
        $foldersToDelete += Join-Path $env:LOCALAPPDATA "Packages\$family"
    }

    foreach ($folder in $foldersToDelete) {
        if (Test-Path -LiteralPath $folder) {
            try {
                Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
                Write-OK "Deleted: $folder"
            }
            catch {
                Write-Warn "Could not fully delete $folder - $($_.Exception.Message)"
            }
        }
        else {
            Write-OK "Not found (skip): $folder"
        }
    }

    if ($SkipInstall) {
        Write-Host "`n   Claude Desktop has been removed (-SkipInstall: not reinstalling)." -ForegroundColor Cyan
        return 0
    }

    # -------------------------------------------------------------
    # 7. Download fresh installer
    # -------------------------------------------------------------
    Write-Step 'Downloading latest Claude Desktop installer...'

    $arch = Get-NativeArchitecture
    $downloadUrl = "https://claude.ai/api/desktop/win32/$arch/setup/latest/redirect"
    $installerPath = Join-Path $env:TEMP "Claude-Setup-$arch.exe"

    # Windows PowerShell 5.1 may default to TLS 1.0, which the download server rejects.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    try {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        $sizeMb = [math]::Round((Get-Item -LiteralPath $installerPath).Length / 1MB, 1)
        Write-OK "Downloaded $arch installer ($sizeMb MB) to: $installerPath"
    }
    catch {
        Write-Fail "Download failed - $($_.Exception.Message)"
        Write-Host '   Download the installer manually from https://claude.com/download and run it.' -ForegroundColor Yellow
        return 1
    }

    # Refuse to run anything that isn't a validly signed Anthropic binary.
    $signature = Get-AuthenticodeSignature -FilePath $installerPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Anthropic') {
        Write-Fail "Installer signature check failed (status: $($signature.Status), signer: $($signature.SignerCertificate.Subject))."
        Write-Host '   The file was deleted. Download the installer manually from https://claude.com/download.' -ForegroundColor Yellow
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        return 1
    }
    Write-OK "Signature verified: $($signature.SignerCertificate.GetNameInfo('SimpleName', $false))"

    # -------------------------------------------------------------
    # 8. Run installer
    # -------------------------------------------------------------
    Write-Step 'Running installer...'
    Write-Host '   The installer window will open. Follow the prompts.' -ForegroundColor White

    # WaitForExit() waits for the installer only; Start-Process -Wait would also wait
    # for Claude itself if the installer launches it when finished.
    $installer = Start-Process -FilePath $installerPath -PassThru
    $null = $installer.Handle   # keeps ExitCode readable after exit on Windows PowerShell 5.1
    $installer.WaitForExit()

    if ($installer.ExitCode -ne 0) {
        Write-Fail "Installer exited with code $($installer.ExitCode)"
        Write-Host "   The installer was kept at $installerPath so you can retry it." -ForegroundColor Yellow
        return $installer.ExitCode
    }
    Write-OK 'Installer finished'
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue

    $installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installed) {
        Write-OK "Claude Desktop $($installed.Version) is installed"
    }
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-OK "$serviceName is registered"
    }
    else {
        Write-Warn "$serviceName is not registered yet - it may appear after Claude's first launch."
    }

    # -------------------------------------------------------------
    # 9. Done
    # -------------------------------------------------------------
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host ' Done! Launch Claude Desktop from the Start menu and check Cowork.' -ForegroundColor Cyan
    Write-Host ' If Claude opened by itself, close it and relaunch it from the' -ForegroundColor Cyan
    Write-Host ' Start menu so it does not run as Administrator.' -ForegroundColor Cyan
    if (-not $SkipBackup -and $backedUp -gt 0) {
        Write-Host " Your old settings are in: $backupRoot" -ForegroundColor Cyan
    }
    Write-Host ' If Cowork still fails:' -ForegroundColor Cyan
    Write-Host '   Claude > Help > Troubleshooting > Show Logs > supported-features-info.json' -ForegroundColor White
    Write-Host '   Event Viewer > Windows Logs > Application' -ForegroundColor White
    Write-Host "============================================================`n" -ForegroundColor Cyan
    return 0
}

$exitCode = Invoke-ClaudeReset -Force:$Force -EnableHyperV:$EnableHyperV -SkipBackup:$SkipBackup -SkipInstall:$SkipInstall

# Only set a process exit code when run as a .ps1 file; under "irm | iex" an
# exit would close the user's PowerShell window.
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') {
    exit ([int]($exitCode | Select-Object -Last 1))
}
