Function Set-ExternalFileFormat {
    [CmdletBinding()]
    <#
.Synopsis
Creates External File Formats
.Description
Get each ofhte external file formats from the source database.
If external file format does not exist on target server, it is created.
.Parameter dbcon
The source database connection
.Parameter targetcon
The target database connection
.Example
Set-ExternalFileFormat -DbCon $conn -targetCon $targetConn
#>
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [System.Data.SqlClient.SqlConnection]$targetCon
    )

    $sqlCommandText = "select eff.name, eff.format_type, eff.data_compression, eff.serde_method, eff.field_terminator, eff.date_format, eff.string_delimiter, eff.use_type_default, eff.encoding from sys.external_file_formats eff"
    $GetfieldformatListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetfieldformatListCmd.Connection = $DbCon
    $GetfieldformatListCmd.CommandText = $sqlCommandText
    $fieldformatListReader = $GetfieldformatListCmd.ExecuteReader();
    if ($fieldformatListReader.HasRows) {
        while ($fieldformatListReader.Read()) {
            $extFileFormatName = $fieldformatListReader.GetString(0)
            $extFileFormatType = $fieldformatListReader.GetString(1)
            $externalFileFormatOptions = $null
            if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("data_compression"))) {
                $extFileFormatCompression = $fieldformatListReader.GetString(2)
            }
            else {
                $extFileFormatCompression = $null
            }
            switch ($extFileFormatType) {
                "DELIMITEDTEXT" {
                    $extSerdeMethod = $null
                    $externalFileFormatOptions = ",FORMAT_OPTIONS (
                        "
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("field_terminator"))) {
                        $extFileFormatFieldTerminator = $fieldformatListReader.GetString(4)
                        $externalFileFormatOptions = $externalFileFormatOptions + "FIELD_TERMINATOR = '$extFileFormatFieldTerminator',"
                    }
                    else {$extFileFormatFieldTerminator = $null}
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("date_format"))) {
                        $extDateFormat = $fieldformatListReader.GetString(5)
                        $externalFileFormatOptions = $externalFileFormatOptions + "DATE_FORMAT = '$extDateFormat',"
                    }
                    else {$extDateFormat = $null}
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("string_delimiter"))) {
                        $extFileFormatStringDelimiter = $fieldformatListReader.GetString(6)
                        $externalFileFormatOptions = $externalFileFormatOptions + "STRING_DELIMITER = '$extFileFormatStringDelimiter',"
                    }
                    else {$extFileFormatStringDelimiter = $null}
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("use_type_default"))) {
                        $extUseTypeDefault = $fieldformatListReader.GetBoolean(7)
                        $externalFileFormatOptions = $externalFileFormatOptions + "USE_TYPE_DEFAULT = $extUseTypeDefault,"
                    }
                    else {$extUseTypeDefault = $null}
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("encoding"))) {
                        $extFileFormatEncoding = $fieldformatListReader.GetString(8)
                        $externalFileFormatOptions = $externalFileFormatOptions + "Encoding = '$extFileFormatEncoding',"
                    }
                    else {$extFileFormatEncoding = $null}
                    $externalFileFormatOptions = $externalFileFormatOptions.Substring(0, $externalFileFormatOptions.Length - 1) + ")"
                    break
                }
                "RCFILE" {
                    $externalFileFormatOptions = $null
                    if (!$fieldformatListReader.IsDBNull($fieldformatListReader.GetOrdinal("serde_method"))) {
                        $extSerdeMethod = $fieldformatListReader.GetString(3)
                    }
                    break
                }
                default {
                    $externalFileFormatOptions = $null
                    $extSerdeMethod = $null
                    break
                }
            }

            $sqlCreateExternalFile = "
            IF NOT EXISTS (select eff.name from sys.external_file_formats eff where eff.name = '$extFileFormatName')
            CREATE EXTERNAL FILE FORMAT $extFileFormatName  
                WITH (  
                    FORMAT_TYPE = $extFileFormatType
                    "
            if ($null -ne $extFileFormatCompression) {
                $sqlCreateExternalFile = $sqlCreateExternalFile + ",DATA_COMPRESSION = '$extFileFormatCompression'
                "
            }
            if ($null -ne $extSerdeMethod) {
                $sqlCreateExternalFile = $sqlCreateExternalFile + ",SERDE_METHOD = '$extSerdeMethod'
                "
            }
            if ($null -ne $externalFileFormatOptions) {
                $sqlCreateExternalFile = $sqlCreateExternalFile + $externalFileFormatOptions
            }
            $sqlCreateExternalFile = $sqlCreateExternalFile + " );"
            $TargetExternalFileCmd = New-Object System.Data.SqlClient.SqlCommand
            $TargetExternalFileCmd.Connection = $targetCon
            $TargetExternalFileCmd.CommandText = $sqlCreateExternalFile
            try {
                $TargetExternalFileCmd.ExecuteNonQuery() | Out-Null    
            }
            catch {
                $_.Exception
                Write-Host $sqlCreateExternalFile
                Throw $_.Exception
            }
        }
    }
}