function Invoke-SampleHelper {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Input
    )

    return "Processed: $Input"
}
