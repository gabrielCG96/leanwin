# Where -UpdateAppList downloads the app catalog from. Only this exact HTTPS address is ever used.
$script:AppListUpdateUrl = 'https://raw.githubusercontent.com/gabrielCG96/leanwin/master/Config/Apps.json'
$script:AppListMaxBytes = 2MB

<#
    .SYNOPSIS
        Checks a downloaded app catalog and returns a description of the first problem, or $null when it is valid.

    .DESCRIPTION
        The catalog decides which packages get removed, so it is validated strictly before it is ever used: the
        format version must match, every entry needs the expected fields with allowed values, every AppId must
        look like a package identifier (letters, digits, dots, dashes, underscores) and every preset may only
        reference apps that exist in the catalog.
#>
function Test-AppListContent {
    param (
        [Parameter(Mandatory)]
        [string]$Json,
        [string]$ExpectedVersion = '1.1'
    )

    if ($Json.Length -gt $script:AppListMaxBytes) { return 'The file is larger than expected.' }

    try { $catalog = $Json | ConvertFrom-Json -ErrorAction Stop }
    catch { return 'The file is not valid JSON.' }

    if ($catalog.Version -ne $ExpectedVersion) { return "Unsupported catalog version '$($catalog.Version)' (expected $ExpectedVersion)." }
    if (-not $catalog.Apps -or @($catalog.Apps).Count -eq 0) { return 'The catalog contains no apps.' }

    $idPattern = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
    $knownIds = @{}
    foreach ($app in @($catalog.Apps)) {
        if ([string]::IsNullOrWhiteSpace($app.FriendlyName) -or $app.FriendlyName -isnot [string]) { return 'An app has no FriendlyName.' }
        if ($app.Recommendation -notin 'safe', 'optional', 'unsafe') { return "App '$($app.FriendlyName)' has an invalid Recommendation." }
        if ($app.RemovalMethod -notin 'Appx', 'WinGet') { return "App '$($app.FriendlyName)' has an invalid RemovalMethod." }
        if ($app.SelectedByDefault -isnot [bool]) { return "App '$($app.FriendlyName)' has an invalid SelectedByDefault value." }

        $ids = @($app.AppId)
        if ($ids.Count -eq 0) { return "App '$($app.FriendlyName)' has no AppId." }
        foreach ($id in $ids) {
            if ($id -isnot [string] -or $id -notmatch $idPattern) { return "App '$($app.FriendlyName)' has an invalid AppId." }
            $knownIds[$id] = $true
        }

        # An app that is selected by default must not be one the project calls unsafe to remove
        if ($app.SelectedByDefault -eq $true -and $app.Recommendation -eq 'unsafe') { return "App '$($app.FriendlyName)' is unsafe but selected by default." }
    }

    foreach ($preset in @($catalog.Presets)) {
        foreach ($id in @($preset.AppIds)) {
            if (-not $knownIds.ContainsKey($id)) { return "Preset '$($preset.Name)' references an unknown app '$id'." }
        }
    }

    return $null
}

<#
    .SYNOPSIS
        Returns the AppIds of a catalog JSON text as a flat list.
#>
function Get-AppListIds {
    param ([string]$Json)

    $catalog = $Json | ConvertFrom-Json
    return @($catalog.Apps | ForEach-Object { $_.AppId } | ForEach-Object { $_ })
}

function Get-UserAppListPath {
    return (Join-Path $script:UserDataPath 'Apps.json')
}

<#
    .SYNOPSIS
        Points the script at the downloaded catalog when it is newer than the one shipped with the script.

    .DESCRIPTION
        A downloaded catalog never outlives a newer script: when the shipped Apps.json is newer than the
        download (for example after updating LeanWin) the shipped file wins. An invalid download is ignored.
#>
function Use-UpdatedAppList {
    $userCopy = Get-UserAppListPath
    if (-not (Test-Path -LiteralPath $userCopy)) { return }

    $bundled = Get-Item -LiteralPath $script:AppsListFilePath -ErrorAction SilentlyContinue
    $downloaded = Get-Item -LiteralPath $userCopy
    if ($bundled -and $bundled.LastWriteTimeUtc -ge $downloaded.LastWriteTimeUtc) { return }

    $problem = Test-AppListContent -Json (Get-Content -LiteralPath $userCopy -Raw -Encoding UTF8)
    if ($problem) {
        Write-Warning "Ignoring the downloaded app list ($problem). The one shipped with the script is used instead."
        return
    }

    $script:AppsListFilePath = $userCopy
    Write-Host "Using the app list updated on $($downloaded.LastWriteTime.ToString('yyyy-MM-dd'))"
}

<#
    .SYNOPSIS
        Downloads the latest app catalog from the repository, validates it and stores it for the next runs.

    .OUTPUTS
        System.Boolean. $true when the catalog is up to date or was updated.
#>
function Update-AppListFromRepository {
    Write-Host "Downloading the latest app list..."

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri $script:AppListUpdateUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $json = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()).TrimStart([char]0xFEFF)
    }
    catch {
        Write-Error "Unable to download the app list: $($_.Exception.Message)"
        return $false
    }

    $problem = Test-AppListContent -Json $json
    if ($problem) {
        Write-Error "The downloaded app list was rejected: $problem Nothing was changed."
        return $false
    }

    $currentJson = Get-Content -LiteralPath $script:AppsListFilePath -Raw -Encoding UTF8
    $currentIds = Get-AppListIds -Json $currentJson
    $newIds = Get-AppListIds -Json $json
    $added = @($newIds | Where-Object { $currentIds -notcontains $_ })
    $removed = @($currentIds | Where-Object { $newIds -notcontains $_ })

    if ($added.Count -eq 0 -and $removed.Count -eq 0 -and ($json.Trim() -eq $currentJson.Trim().TrimStart([char]0xFEFF))) {
        Write-Host "The app list is already up to date."
        return $true
    }

    Write-Host "Apps added: $($added.Count), apps dropped: $($removed.Count)"
    foreach ($id in $added | Select-Object -First 15) { Write-Host "  + $id" }
    foreach ($id in $removed | Select-Object -First 15) { Write-Host "  - $id" }

    if ($script:Params.ContainsKey('WhatIf')) {
        Write-Host "[WhatIf] Save the updated app list" -ForegroundColor Cyan
        return $true
    }

    if (-not $script:Params.ContainsKey('Silent')) {
        if ((Read-Host "Use this app list from now on? (y/n)") -ne 'y') {
            Write-Host "No changes were made."
            return $true
        }
    }

    try {
        $target = Get-UserAppListPath
        $directory = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $temp = "$target.download"
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($true)))
        Move-Item -LiteralPath $temp -Destination $target -Force
        Write-Host "App list saved to $target"
        Write-Host "Delete that file to go back to the app list shipped with the script."
        return $true
    }
    catch {
        Write-Error "Unable to save the app list: $($_.Exception.Message)"
        return $false
    }
}
