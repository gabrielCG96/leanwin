<#
    .SYNOPSIS
    Decides from a StartupApproved value whether the startup entry is disabled.

    .DESCRIPTION
    Task Manager (and this manager) store the state of a startup entry in the StartupApproved registry keys.
    The lowest bit of the first byte is set when the entry is disabled. A missing value means enabled.
#>
function Test-StartupApprovedDisabled {
    param ($Bytes)

    if ($null -eq $Bytes -or $Bytes -isnot [byte[]] -or $Bytes.Length -eq 0) { return $false }
    return (($Bytes[0] -band 1) -eq 1)
}

<#
    .SYNOPSIS
    Builds the 12 byte StartupApproved value for an enabled or disabled startup entry.
#>
function ConvertTo-StartupApprovedBytes {
    param (
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $bytes = New-Object byte[] 12
    if ($Enabled) {
        $bytes[0] = 2
    }
    else {
        $bytes[0] = 3
        [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()).CopyTo($bytes, 4)
    }
    return , $bytes
}

<#
    .SYNOPSIS
    Lists the programs that start with Windows for the current machine and the current user.

    .DESCRIPTION
    Covers the Run registry keys and the Startup folders. Scheduled tasks and services are not included.
    Each entry carries the StartupApproved location that holds its enabled state, so disabling is
    reversible and does not delete the entry.

    .OUTPUTS
    PSCustomObject with Name, Command, Source, Scope, Enabled, ApprovedKey and ApprovedName.
#>
function Get-StartupEntries {
    $approvedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $runSources = @(
        @{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'User'; Approved = "HKCU:\$approvedBase\Run" },
        @{ Hive = 'HKLM'; Path = 'Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Machine'; Approved = "HKLM:\$approvedBase\Run" },
        @{ Hive = 'HKLM'; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Machine'; Approved = "HKLM:\$approvedBase\Run32" }
    )
    $folderSources = @(
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'User'; Approved = "HKCU:\$approvedBase\StartupFolder" },
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'Machine'; Approved = "HKLM:\$approvedBase\StartupFolder" }
    )

    $entries = @()

    foreach ($source in $runSources) {
        try { $runKey = Get-Item -LiteralPath "$($source.Hive):\$($source.Path)" -ErrorAction Stop } catch { continue }
        $approvedKey = Get-Item -LiteralPath $source.Approved -ErrorAction SilentlyContinue

        foreach ($valueName in $runKey.GetValueNames()) {
            if ([string]::IsNullOrEmpty($valueName)) { continue }
            $approvedBytes = if ($approvedKey) { $approvedKey.GetValue($valueName) } else { $null }
            $entries += [PSCustomObject]@{
                Name         = $valueName
                Command      = [string]$runKey.GetValue($valueName)
                Source       = 'Registry'
                Scope        = $source.Scope
                Enabled      = -not (Test-StartupApprovedDisabled -Bytes $approvedBytes)
                ApprovedKey  = $source.Approved
                ApprovedName = $valueName
            }
        }
    }

    foreach ($source in $folderSources) {
        if (-not (Test-Path -LiteralPath $source.Path)) { continue }
        $approvedKey = Get-Item -LiteralPath $source.Approved -ErrorAction SilentlyContinue

        foreach ($file in Get-ChildItem -LiteralPath $source.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            $approvedBytes = if ($approvedKey) { $approvedKey.GetValue($file.Name) } else { $null }
            $entries += [PSCustomObject]@{
                Name         = $file.BaseName
                Command      = $file.FullName
                Source       = 'Folder'
                Scope        = $source.Scope
                Enabled      = -not (Test-StartupApprovedDisabled -Bytes $approvedBytes)
                ApprovedKey  = $source.Approved
                ApprovedName = $file.Name
            }
        }
    }

    return $entries
}

<#
    .SYNOPSIS
    Enables or disables one startup entry from Get-StartupEntries.

    .OUTPUTS
    System.Boolean. $true when the state was written or previewed with -WhatIf.
#>
function Set-StartupEntryState {
    param (
        [Parameter(Mandatory)]
        $Entry,
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $action = if ($Enabled) { 'Enable' } else { 'Disable' }
    if ($script:Params -and $script:Params.ContainsKey('WhatIf')) {
        Write-Host "[WhatIf] $action startup item: $($Entry.Name)" -ForegroundColor Cyan
        return $true
    }

    try {
        if (-not (Test-Path -LiteralPath $Entry.ApprovedKey)) {
            New-Item -Path $Entry.ApprovedKey -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -LiteralPath $Entry.ApprovedKey -Name $Entry.ApprovedName -Value (ConvertTo-StartupApprovedBytes -Enabled $Enabled) -Type Binary -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "Failed to $($action.ToLower()) startup item '$($Entry.Name)': $($_.Exception.Message)"
        return $false
    }
}

<#
    .SYNOPSIS
    Finds a startup entry by name. Throws when the name matches none or more than one entry.
#>
function Find-StartupEntry {
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    $found = @($Entries | Where-Object { $_.Name -ieq $Name })
    if ($found.Count -eq 0) {
        throw "No startup item named '$Name' was found. Run with -ListStartup to see the names."
    }
    if ($found.Count -gt 1) {
        $where = ($found | ForEach-Object { "$($_.Scope)/$($_.Source)" }) -join ', '
        throw "More than one startup item is named '$Name' ($where). Use the graphical interface to pick one."
    }
    return $found[0]
}

<#
    .SYNOPSIS
    Prints the startup entries as a table.
#>
function Write-StartupList {
    param ($Entries)

    if (@($Entries).Count -eq 0) {
        Write-Host 'No startup programs were found.'
        return
    }

    # Names are printed in full, they are what -DisableStartupItem and -EnableStartupItem expect
    $nameWidth = [math]::Max(8, ($Entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum) + 2
    Write-Host ("{0,-9}{1}{2,-9}{3}" -f 'State', 'Name'.PadRight($nameWidth), 'Scope', 'Command') -ForegroundColor Cyan
    foreach ($entry in $Entries | Sort-Object Name) {
        $state = if ($entry.Enabled) { 'Enabled' } else { 'Disabled' }
        $color = if ($entry.Enabled) { 'Gray' } else { 'DarkGray' }
        Write-Host ("{0,-9}{1}{2,-9}{3}" -f $state, $entry.Name.PadRight($nameWidth), $entry.Scope, $entry.Command) -ForegroundColor $color
    }
}

<#
    .SYNOPSIS
    Runs the startup manager commands of the command line (-ListStartup, -DisableStartupItem, -EnableStartupItem).

    .OUTPUTS
    System.Boolean. $false when a requested change failed.
#>
function Invoke-CliStartupManager {
    param (
        [switch]$List,
        [string]$DisableName,
        [string]$EnableName
    )

    $ok = $true
    $entries = @(Get-StartupEntries)

    foreach ($change in @(@{ Name = $DisableName; Enabled = $false }, @{ Name = $EnableName; Enabled = $true })) {
        if ([string]::IsNullOrWhiteSpace($change.Name)) { continue }
        try {
            $entry = Find-StartupEntry -Name $change.Name -Entries $entries
        }
        catch {
            Write-Error "$_"
            $ok = $false
            continue
        }

        if (Set-StartupEntryState -Entry $entry -Enabled $change.Enabled) {
            Write-Host "$(if ($change.Enabled) { 'Enabled' } else { 'Disabled' }) startup item: $($entry.Name)"
        }
        else {
            $ok = $false
        }
    }

    if ($List -or (-not $DisableName -and -not $EnableName)) {
        Write-StartupList -Entries (Get-StartupEntries)
    }

    return $ok
}
