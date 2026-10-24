<#
    .SYNOPSIS
    Keeps the list of changes that failed during a run, so the interface can show what went wrong and why.
#>
function Reset-ChangeIssues {
    $script:ChangeIssues = [System.Collections.Generic.List[object]]::new()
}

<#
    .SYNOPSIS
    Records one failed change with a short reason.
#>
function Add-ChangeIssue {
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Message
    )

    if (-not $script:ChangeIssues) { Reset-ChangeIssues }
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = Get-Translation -Key 'ApplyIssueGeneric' }
    $script:ChangeIssues.Add([PSCustomObject]@{ Name = $Name; Message = $Message.Trim() })
}

function Get-ChangeIssues {
    if (-not $script:ChangeIssues) { return @() }
    return @($script:ChangeIssues)
}

<#
    .SYNOPSIS
    Turns error records into one short line, without duplicates.
#>
function ConvertTo-IssueMessage {
    param ($ErrorRecords)

    $messages = @($ErrorRecords | ForEach-Object {
        $text = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
        ($text -replace '\s+', ' ').Trim()
    } | Where-Object { $_ } | Select-Object -Unique)

    return ($messages -join ' ')
}
