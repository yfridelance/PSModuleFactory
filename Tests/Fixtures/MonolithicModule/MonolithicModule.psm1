enum SampleStatus {
    Active
    Inactive
    Pending
    Archived
}

class BaseModel {
    [string]$Id
    [datetime]$CreatedAt

    BaseModel() {
        $this.Id = [guid]::NewGuid().ToString()
        $this.CreatedAt = Get-Date
    }
}

class DerivedModel : BaseModel {
    [string]$Name
    [string]$Description

    DerivedModel([string]$Name) : base() {
        $this.Name = $Name
    }
}

function Invoke-SampleHelper {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Input
    )

    return "Processed: $Input"
}

function Get-SampleData {
    # Alias: gsd
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Name = 'Default'
    )

    [PSCustomObject]@{
        Name      = $Name
        Timestamp = Get-Date
    }
}

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
