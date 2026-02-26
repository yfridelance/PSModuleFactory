function ConvertTo-SortedClassFileName {
    <#
    .SYNOPSIS
        Converts a class name and sort index into a standardised, numerically-prefixed class file name.

    .DESCRIPTION
        Generates a canonical class file name that follows the module factory naming convention:

            {zero-padded two-digit index}_{ClassName}.Class.ps1

        The sort index is 0-based. It is incremented by 1 and zero-padded to two digits before
        being prepended to the class name. This ensures that files sort correctly in numeric
        order in the file system (01_..., 02_..., 03_..., etc.).

        Examples:
            SortIndex=0, ClassName='BaseModel'    → '01_BaseModel.Class.ps1'
            SortIndex=4, ClassName='CustomerOrder' → '05_CustomerOrder.Class.ps1'

    .PARAMETER ClassName
        The name of the PowerShell class. Used verbatim as the middle segment of the file name.

    .PARAMETER SortIndex
        A 0-based integer indicating the position of the class in the load order. Will be
        incremented by 1 and formatted as a zero-padded two-digit number.

    .EXAMPLE
        ConvertTo-SortedClassFileName -ClassName 'BaseEntity' -SortIndex 0
        # Returns: '01_BaseEntity.Class.ps1'

    .EXAMPLE
        $Classes = @('BaseEntity', 'Customer', 'Order', 'OrderItem')
        for ($i = 0; $i -lt $Classes.Count; $i++) {
            ConvertTo-SortedClassFileName -ClassName $Classes[$i] -SortIndex $i
        }
        # Returns:
        #   01_BaseEntity.Class.ps1
        #   02_Customer.Class.ps1
        #   03_Order.Class.ps1
        #   04_OrderItem.Class.ps1
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ClassName,

        [Parameter(Mandatory = $true, Position = 1)]
        [int]$SortIndex
    )

    Write-Verbose "ConvertTo-SortedClassFileName: ClassName='$ClassName', SortIndex=$SortIndex"

    $FileName = "{0:D2}_{1}.Class.ps1" -f ($SortIndex + 1), $ClassName

    Write-Verbose "ConvertTo-SortedClassFileName: Result='$FileName'"
    return $FileName
}
