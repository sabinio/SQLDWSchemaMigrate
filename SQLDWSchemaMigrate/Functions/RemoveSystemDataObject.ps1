function Remove-SystemDataObject {
    <#
.Synopsis
dispose of system data objects
.Description
Clear out objects/free up resources
.Parameter systemDataObject
The object we wish to dispose of.
.Example
$sourceResultSet = New-Object "System.Data.DataSet" "DsSumOfCOlumns"
$targetResultSet = New-Object "System.Data.DataSet" "DsSumOfCOlumns"
    ...
Remove-SystemDataObject -systemdataobject $sourceResultSet
Remove-SystemDataObject -systemdataobject $targetResultSet
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, mandatory = $true)]
        $SystemDataObject
    )
    try {
        $SystemDataObject.Dispose()
        Write-Host "Disposed of object $SystemDataObject"
        Return
    }
    catch {
        Write-Host $_.Exception
        Return
    }
}