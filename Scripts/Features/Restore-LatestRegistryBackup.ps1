<#
    .SYNOPSIS
    Restores a registry backup from the command line (the "undo everything" of the CLI).

    .DESCRIPTION
    Backups are created automatically before registry tweaks are applied. 'Latest' restores the newest one,
    otherwise the value is the path of a backup file. Apps, services and the power plan are not part of a
    registry backup, use a system restore point for those.

    .OUTPUTS
    System.Boolean. $true when the backup was restored.
#>
function Invoke-CliRegistryRestore {
    param (
        [Parameter(Mandatory)]
        [string]$BackupPath
    )

    if ($BackupPath -ieq 'Latest') {
        $latest = $null
        if (Test-Path -LiteralPath $script:RegistryBackupsPath) {
            $latest = Get-ChildItem -LiteralPath $script:RegistryBackupsPath -Filter '*.json' -File | Sort-Object LastWriteTime | Select-Object -Last 1
        }
        if (-not $latest) {
            Write-Error "No registry backups were found in $script:RegistryBackupsPath"
            return $false
        }
        $BackupPath = $latest.FullName
    }

    try {
        $backup = Import-RegistryBackup -FilePath $BackupPath
    }
    catch {
        Write-Error "$_"
        return $false
    }

    Write-Host "Restoring registry backup: $BackupPath"
    Write-Host "Created: $($backup.CreatedAt)"

    $confirmUntrustedValues = {
        param($mismatches)
        if ($script:Params.ContainsKey('Silent')) { return $false }
        return ((Read-Host "Restore these unrecognized executable settings anyway? (y/n)") -eq 'y')
    }

    try {
        $result = Restore-RegistryBackupState -Backup $backup -ConfirmUntrustedValues $confirmUntrustedValues
    }
    catch {
        Write-Error "Restore failed: $($_.Exception.Message)"
        return $false
    }

    return ($result -and $result.Result -eq $true)
}
