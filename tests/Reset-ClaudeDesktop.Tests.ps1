#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Loads the helper functions from the script without running it (running it
# would uninstall Claude Desktop).
BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\Reset-ClaudeDesktop.ps1'
    $script:scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:scriptText, [ref]$null, [ref]$null)
    $helpers = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ne 'Invoke-ClaudeReset'
        }, $false)
    foreach ($helper in $helpers) {
        . ([scriptblock]::Create($helper.Extent.Text))
    }
}

Describe 'Package family name' {
    It 'uses the real Claude Desktop package family' {
        # Regression: an earlier version had a typo (pzs8sxjxfjjc), so the MSIX data
        # folder was never backed up or cleaned when the package was not registered.
        $script:scriptText | Should -Match "'Claude_pzs8sxrjxfjjc'"
    }
}

Describe 'Split-UninstallCommand' {
    It 'turns an MSI modify entry into a silent removal' {
        $result = Split-UninstallCommand -CommandLine 'MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}'
        $result.FilePath | Should -BeLike '*\System32\msiexec.exe'
        $result.Arguments | Should -Be '/x {12345678-1234-1234-1234-123456789ABC} /qn /norestart'
    }

    It 'adds -s to a Squirrel uninstaller' {
        $result = Split-UninstallCommand -CommandLine '"C:\Users\me\AppData\Local\AnthropicClaude\Update.exe" --uninstall'
        $result.FilePath | Should -Be 'C:\Users\me\AppData\Local\AnthropicClaude\Update.exe'
        $result.Arguments | Should -Be '--uninstall -s'
    }

    It 'does not add -s twice' {
        $result = Split-UninstallCommand -CommandLine '"C:\x\Update.exe" --uninstall -s'
        $result.Arguments | Should -Be '--uninstall -s'
    }

    It 'adds /S to an unquoted path with spaces' {
        $result = Split-UninstallCommand -CommandLine 'C:\Program Files\Claude\Uninstall Claude.exe'
        $result.FilePath | Should -Be 'C:\Program Files\Claude\Uninstall Claude.exe'
        $result.Arguments | Should -Be '/S'
    }

    It 'leaves a quiet uninstall string unchanged' {
        $result = Split-UninstallCommand -CommandLine '"C:\x\uninstall.exe" /quiet' -IsQuiet
        $result.Arguments | Should -Be '/quiet'
    }

    It 'returns nothing for an unrecognised command line' {
        Split-UninstallCommand -CommandLine 'rundll32 something' | Should -BeNullOrEmpty
    }
}

Describe 'Test-IsClaudeDesktopPath' {
    It 'matches <Path>' -ForEach @(
        @{ Path = 'C:\Program Files\WindowsApps\Claude_4.1.0.0_x64__pzs8sxrjxfjjc\app\claude.exe' }
        @{ Path = 'C:\Users\me\AppData\Local\AnthropicClaude\app-0.9.0\claude.exe' }
        @{ Path = 'C:\Users\me\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\claude-code\2.1.0\claude.exe' }
    ) {
        Test-IsClaudeDesktopPath -Path $Path | Should -BeTrue
    }

    It 'does not match <Path>' -ForEach @(
        @{ Path = 'C:\Users\me\.local\bin\claude.exe' }
        @{ Path = 'C:\Users\me\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\claude.exe' }
        @{ Path = '' }
    ) {
        Test-IsClaudeDesktopPath -Path $Path | Should -BeFalse
    }

    It 'handles a process with no readable path' {
        Test-IsClaudeDesktopPath -Path $null | Should -BeFalse
    }
}

Describe 'Test-AnthropicSignature' {
    BeforeAll {
        function Get-FakeSignature {
            param([string]$Status, [string]$Signer)
            $certificate = [pscustomobject]@{ Signer = $Signer }
            $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { $this.Signer }
            return [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
        }
    }

    It 'accepts a valid Anthropic signature' {
        Mock Get-AuthenticodeSignature { Get-FakeSignature -Status 'Valid' -Signer 'Anthropic, PBC' }
        (Test-AnthropicSignature -Path 'x.exe').IsValid | Should -BeTrue
    }

    It 'rejects a valid signature from another company that mentions Anthropic' {
        Mock Get-AuthenticodeSignature { Get-FakeSignature -Status 'Valid' -Signer 'Not Anthropic Ltd' }
        (Test-AnthropicSignature -Path 'x.exe').IsValid | Should -BeFalse
    }

    It 'rejects an invalid Anthropic signature' {
        Mock Get-AuthenticodeSignature { Get-FakeSignature -Status 'HashMismatch' -Signer 'Anthropic, PBC' }
        (Test-AnthropicSignature -Path 'x.exe').IsValid | Should -BeFalse
    }

    It 'rejects an unsigned file' {
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
        $result = Test-AnthropicSignature -Path 'x.exe'
        $result.IsValid | Should -BeFalse
        $result.Signer | Should -BeNullOrEmpty
    }
}

Describe 'Backup-ClaudeSetting' {
    BeforeEach {
        $script:desktop = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $script:desktop -Force
        Mock Write-Host {}
        $source = Join-Path $TestDrive 'Claude-Data\claude_x'
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'Claude Extensions Settings') -Force
        Set-Content -LiteralPath (Join-Path $source 'claude_desktop_config.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $source 'Claude Extensions Settings\ext.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $source 'buddy-tokens.json') -Value 'secret'
        $script:folders = @([pscustomobject]@{ Label = 'Claude-Data-claude_x'; Path = $source })
    }

    It 'copies MCP and extension settings but not token files' {
        $backupRoot = Backup-ClaudeSetting -Folders $script:folders -DestinationRoot $script:desktop
        $backupRoot | Should -BeLike "$($script:desktop)\Claude-Backup-*"
        $copied = Join-Path $backupRoot 'Claude-Data-claude_x'
        Test-Path -LiteralPath (Join-Path $copied 'claude_desktop_config.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $copied 'Claude Extensions Settings\ext.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $copied 'buddy-tokens.json') | Should -BeFalse
    }

    It 'returns nothing when there is nothing to back up' {
        $empty = @([pscustomobject]@{ Label = 'Empty'; Path = (Join-Path $TestDrive 'nope') })
        Backup-ClaudeSetting -Folders $empty -DestinationRoot $script:desktop | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $script:desktop).Count | Should -Be 0
    }
}
