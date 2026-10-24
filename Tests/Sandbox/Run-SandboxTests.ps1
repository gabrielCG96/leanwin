<#
    .SYNOPSIS
        Starts Windows Sandbox, applies and undoes every tweak inside it and reports the result.

    .DESCRIPTION
        Windows Sandbox is a disposable copy of Windows, so every tweak can be applied without touching this PC.
        The repository is mapped read-only into the sandbox and a results folder is mapped read-write.
        Requires the "Windows Sandbox" optional feature (Windows 11 Pro, Enterprise or Education).
        Enable it once from an elevated PowerShell:  Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM

    .PARAMETER TimeoutMinutes
        How long to wait for the sandbox to finish.

    .PARAMETER FeatureId
        Optional: only test these features.

    .PARAMETER KeepOpen
        Leaves the sandbox window open after the run, for debugging.
#>
[CmdletBinding()]
param (
    [int]$TimeoutMinutes = 30,
    [string[]]$FeatureId,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sandboxExe = Join-Path $env:windir 'System32\WindowsSandbox.exe'

if (-not (Test-Path -LiteralPath $sandboxExe)) {
    Write-Error "Windows Sandbox is not installed. Enable it with: Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM (then restart)."
    exit 1
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsHost = Join-Path ([System.IO.Path]::GetTempPath()) "leanwin-sandbox-$runId"
New-Item -ItemType Directory -Path $resultsHost -Force | Out-Null

$featureArgument = if ($FeatureId) { " -FeatureId " + (($FeatureId | ForEach-Object { "'$_'" }) -join ',') } else { '' }
$shutdown = if ($KeepOpen) { '' } else { '; shutdown /s /t 5' }
$logonCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"& 'C:\leanwin\Tests\Sandbox\Invoke-SandboxFeatureTests.ps1'$featureArgument$shutdown`""

# XML-escape everything that goes into the configuration file
$esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
$configuration = @"
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>Disable</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$(& $esc $repoRoot)</HostFolder>
      <SandboxFolder>C:\leanwin</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$(& $esc $resultsHost)</HostFolder>
      <SandboxFolder>C:\results</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$(& $esc $logonCommand)</Command>
  </LogonCommand>
</Configuration>
"@

$configPath = Join-Path $resultsHost 'leanwin.wsb'
Set-Content -LiteralPath $configPath -Value $configuration -Encoding UTF8

Write-Host "Starting Windows Sandbox (results in $resultsHost)..."
Start-Process -FilePath $sandboxExe -ArgumentList "`"$configPath`""

$doneFlag = Join-Path $resultsHost 'done.flag'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $doneFlag)) {
    if ((Get-Date) -gt $deadline) {
        Write-Error "Timed out after $TimeoutMinutes minutes. Partial output may be in $resultsHost"
        exit 1
    }
    Start-Sleep -Seconds 5
}

Write-Host ""
Get-Content -LiteralPath (Join-Path $resultsHost 'results.txt')
$failures = @(Get-Content -LiteralPath (Join-Path $resultsHost 'results.json') -Raw | ConvertFrom-Json | Where-Object { -not $_.Passed })
Write-Host ""
Write-Host "Full results: $resultsHost"
exit $(if ($failures.Count -eq 0) { 0 } else { 1 })
