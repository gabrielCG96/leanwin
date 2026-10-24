<#
    .SYNOPSIS
    Activates a built-in Windows power plan using powercfg.

    .DESCRIPTION
    The High performance plan is hidden on some devices (for example Modern Standby laptops). When it is not listed,
    it is recreated from the built-in template before being activated.

    .OUTPUTS
    System.Boolean. $true when the plan is activated or previewed; otherwise $false.
#>
function Set-PowerPlan {
    param (
        [Parameter(Mandatory)]
        [ValidateSet('HighPerformance', 'Balanced')]
        [string]$Plan
    )

    $schemeGuid = switch ($Plan) {
        'HighPerformance' { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        'Balanced'        { '381b4222-f694-41f0-9685-ff5bb260df2e' }
    }

    if ($script:Params.ContainsKey("WhatIf")) {
        Write-Host "[WhatIf] Activate power plan: $Plan" -ForegroundColor Cyan
        return $true
    }

    try {
        $listed = (powercfg /list | Out-String)
        if ($listed -notmatch [regex]::Escape($schemeGuid)) {
            powercfg /duplicatescheme $schemeGuid $schemeGuid | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Unable to create the '$Plan' power plan on this device."
                return $false
            }
        }

        powercfg /setactive $schemeGuid | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Unable to activate the '$Plan' power plan."
            return $false
        }
        return $true
    }
    catch {
        Write-Warning "Failed to set the '$Plan' power plan: $($_.Exception.Message)"
        return $false
    }
}
