<#
    .SYNOPSIS
    Deletes the contents of a folder and returns the number of bytes freed.

    .DESCRIPTION
    Files that are in use or cannot be deleted are skipped. With -WhatIf nothing is deleted and the size that would be freed is returned.
    Only the contents are removed, the folder itself is kept.
#>
function Remove-FolderContents {
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [int]$OlderThanDays = 0
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $freed = 0L
    $whatIf = $script:Params.ContainsKey("WhatIf")

    $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
    foreach ($file in $files) {
        $size = $file.Length
        if ($whatIf) { $freed += $size; continue }
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $freed += $size
        }
        catch { }
    }

    if (-not $whatIf) {
        # Remove folders that are now empty, deepest first
        Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    return $freed
}

function Write-FreedSpace {
    param ([long]$Bytes)

    $text = if ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) } else { "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($script:Params.ContainsKey("WhatIf")) {
        Write-Host "[WhatIf] Would free $text" -ForegroundColor Cyan
    }
    else {
        Write-Host "Freed $text"
    }
}

<#
    .SYNOPSIS
    Deletes temporary files from the user and Windows temp folders.

    .DESCRIPTION
    Only files older than one day are removed, so files that running programs still need are left alone.
#>
function Clear-TempFiles {
    $freed = 0L
    foreach ($folder in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Select-Object -Unique) {
        $freed += Remove-FolderContents -Path $folder -OlderThanDays 1
    }

    Write-FreedSpace -Bytes $freed
    return $true
}

<#
    .SYNOPSIS
    Deletes the downloaded Windows Update installation files.

    .DESCRIPTION
    Windows re-downloads whatever it still needs. The Windows Update and BITS services are stopped while the
    folder is cleaned and started again afterwards if they were running.
#>
function Clear-WindowsUpdateCache {
    $downloadPath = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'

    if ($script:Params.ContainsKey("WhatIf")) {
        Write-FreedSpace -Bytes (Remove-FolderContents -Path $downloadPath)
        return $true
    }

    $stopped = @()
    try {
        foreach ($name in 'wuauserv', 'bits') {
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Stop-Service -Name $name -Force -ErrorAction Stop
                $stopped += $name
            }
        }

        Write-FreedSpace -Bytes (Remove-FolderContents -Path $downloadPath)
        return $true
    }
    catch {
        Write-Warning "Failed to clean the Windows Update cache: $($_.Exception.Message)"
        return $false
    }
    finally {
        foreach ($name in $stopped) { Start-Service -Name $name -ErrorAction SilentlyContinue }
    }
}

<#
    .SYNOPSIS
    Permanently empties the Recycle Bin of every drive.
#>
function Clear-RecycleBinContents {
    if ($script:Params.ContainsKey("WhatIf")) {
        Write-Host "[WhatIf] Empty the Recycle Bin" -ForegroundColor Cyan
        return $true
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        return $true
    }
    catch {
        # Clear-RecycleBin throws when the bin is already empty
        if ($_.Exception.Message -match 'empty|vazia') { return $true }
        Write-Warning "Failed to empty the Recycle Bin: $($_.Exception.Message)"
        return $false
    }
}
