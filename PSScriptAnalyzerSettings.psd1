@{
    Severity     = @('Error', 'Warning', 'Information')
    # Write-Host is intentional: this is an interactive script with colored progress output.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
