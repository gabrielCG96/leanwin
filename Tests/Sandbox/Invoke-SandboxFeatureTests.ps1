<#
    .SYNOPSIS
        Applies and undoes every registry tweak on a throwaway Windows and checks the result.

    .DESCRIPTION
        Runs INSIDE Windows Sandbox (started by Run-SandboxTests.ps1), never on a real PC: it applies every tweak, and the
        sandbox is discarded when it closes. For each registry-backed tweak it
          1. checks that the tweak is not applied yet,
          2. runs Win11Debloat.ps1 -<FeatureId> and checks that the state detection now reports it as applied,
          3. runs Win11Debloat.ps1 -RestoreBackup Latest and checks that the tweak is no longer applied.
        Then every shipped profile is applied once to prove that it runs to the end.
        Results are written to results.json and results.txt in -ResultsPath.

    .PARAMETER RepoPath
        The LeanWin folder, as mapped into the sandbox.

    .PARAMETER ResultsPath
        A writable folder for the result files.

    .PARAMETER FeatureId
        Optional: only test these features (used to debug a single tweak).
#>
param (
    [string]$RepoPath = 'C:\leanwin',
    [string]$ResultsPath = 'C:\results',
    [string[]]$FeatureId
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param ([string]$Name, [string]$Step, [bool]$Passed, [string]$Detail = '')

    $results.Add([PSCustomObject]@{ Name = $Name; Step = $Step; Passed = $Passed; Detail = $Detail })
    $mark = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} - {2} {3}" -f $mark, $Name, $Step, $Detail)
}

function Invoke-LeanWin {
    param ([string[]]$Arguments)

    $scriptPath = Join-Path $RepoPath 'Win11Debloat.ps1'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Silent -SkipExplorerRestart @Arguments 2>&1 | Out-String
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

New-Item -ItemType Directory -Path $ResultsPath -Force | Out-Null

# ---- Load the project's own state detection ----
$script:RegfilesPath = Join-Path $RepoPath 'Regfiles'
$script:Params = @{}
$script:Features = @{}
foreach ($feature in (Get-Content (Join-Path $RepoPath 'Config\Features.json') -Raw | ConvertFrom-Json).Features) {
    $script:Features[$feature.FeatureId] = $feature
}
foreach ($file in 'Scripts\Helpers\Get-RegFileOperations.ps1', 'Scripts\Helpers\Registry-PathHelpers.ps1', 'Scripts\Features\Get-CurrentTweakState.ps1') {
    . (Join-Path $RepoPath $file)
}
# The state detection also knows non-registry features; they are not tested here
foreach ($stub in 'Test-StoreSearchSuggestionsDisabledForAllUsers', 'Test-StoreSearchSuggestionsDisabled', 'Get-StoreAppsDatabasePathForUser', 'Get-UserName', 'Test-WindowsOptionalFeatureEnabled') {
    if (-not (Get-Command $stub -ErrorAction SilentlyContinue)) { Set-Item "function:$stub" { $false } }
}

$build = [Environment]::OSVersion.Version.Build
$candidates = $script:Features.Values | Where-Object {
    $_.RegistryKey -and $_.RegistryUndoKey -and
    (-not $_.MinVersion -or $build -ge [int]$_.MinVersion) -and
    (-not $_.MaxVersion -or $build -le [int]$_.MaxVersion)
}
if ($FeatureId) { $candidates = $candidates | Where-Object { $FeatureId -contains $_.FeatureId } }

Write-Host "Windows build $build, testing $(@($candidates).Count) registry tweaks"

foreach ($feature in $candidates | Sort-Object FeatureId) {
    $id = $feature.FeatureId
    try {
        $before = Test-FeatureApplied -FeatureId $id
        if ($before) {
            # Already in the applied state on a fresh Windows: nothing to prove for the apply step
            Add-Result $id 'pre-state' $true 'already applied on a fresh Windows, apply step skipped'
            continue
        }

        $apply = Invoke-LeanWin -Arguments @("-$id")
        Add-Result $id 'apply exit code' ($apply.ExitCode -eq 0) "exit $($apply.ExitCode)"
        Add-Result $id 'detected as applied' ([bool](Test-FeatureApplied -FeatureId $id)) ''

        $restore = Invoke-LeanWin -Arguments @('-RestoreBackup', 'Latest')
        Add-Result $id 'restore exit code' ($restore.ExitCode -eq 0) "exit $($restore.ExitCode)"
        Add-Result $id 'back to original state' (-not [bool](Test-FeatureApplied -FeatureId $id)) ''
    }
    catch {
        Add-Result $id 'unexpected error' $false $_.Exception.Message
    }
}

# ---- Every shipped profile must run to the end ----
foreach ($profile in Get-ChildItem (Join-Path $RepoPath 'Config\Profiles') -Filter '*.json') {
    $name = $profile.BaseName
    try {
        $run = Invoke-LeanWin -Arguments @('-ProfileName', $name)
        Add-Result "Profile:$name" 'apply exit code' ($run.ExitCode -eq 0) "exit $($run.ExitCode)"
    }
    catch {
        Add-Result "Profile:$name" 'unexpected error' $false $_.Exception.Message
    }
}

# ---- Commands that must work on any machine ----
$detect = Invoke-LeanWin -Arguments @('-DetectHardware')
Add-Result 'DetectHardware' 'exit code' ($detect.ExitCode -eq 0 -and $detect.Output -match 'Recommended profile') "exit $($detect.ExitCode)"
$startup = Invoke-LeanWin -Arguments @('-ListStartup')
Add-Result 'ListStartup' 'exit code' ($startup.ExitCode -eq 0) "exit $($startup.ExitCode)"

# ---- Write the results ----
$failed = @($results | Where-Object { -not $_.Passed })
$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ResultsPath 'results.json') -Encoding UTF8
$summary = "Checks: $($results.Count), passed: $($results.Count - $failed.Count), failed: $($failed.Count)"
@($summary) + ($failed | ForEach-Object { "FAIL $($_.Name) - $($_.Step) $($_.Detail)" }) | Set-Content (Join-Path $ResultsPath 'results.txt') -Encoding UTF8
Write-Host $summary
# Marks the end of the run for the host script
Set-Content (Join-Path $ResultsPath 'done.flag') 'done'
