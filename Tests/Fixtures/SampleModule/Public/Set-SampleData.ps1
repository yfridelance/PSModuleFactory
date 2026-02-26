function Set-SampleData {
    # Alias: ssd, setsd
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [object]$Value
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Set sample data')) {
        Write-Verbose -Message "Setting data for '$Name' to '$Value'"
    }
}
