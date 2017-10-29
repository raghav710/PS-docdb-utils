# needed for URL encoding
Add-Type -AssemblyName System.Web

function new_documentDB_rest_client {
    param(
        [ValidateNotNullOrEmpty()]$documentDBEndpointUri = $(throw "Please pass in the endpoint Uri for documentDB"),
        [ValidateNotNullOrEmpty()]$documentDBMasterKey = $(throw "Please pass the document DB master key as a parameter")
    )

    function CreateDatabase([String]$DatabaseName) {
        $Uri = $documentDBEndpointUri + "/dbs"
        $Headers = BuildHeaders -resType 'dbs' -action 'post' -resourceId '' -primaryKey $DocumentDBMasterKey
        $Body = (@{"id" = $databaseName} | ConvertTo-Json)

        try {
            $Response = Invoke-RestMethod -Uri $Uri -Method 'POST' -Headers $Headers -Body $Body
        } 
        catch {
            Write-Error "$($_.Exception.Response.StatusDescription | ConvertTo-Json)"
        }

        Write-Output "Created Database"
        Write-Output "Response: $($Response | ConvertTo-Json)"
    }

    function CreateCollection([String]$DatabaseName, $collectionName, [System.Array]$Indexes=$null) {
        $Uri = $documentDBEndpointUri + "/dbs/$databaseName/colls"
        $Headers = BuildHeaders -resType "colls" -action POST -resourceId "dbs/$databaseName" -primaryKey $documentDBMasterKey
        $Body = GenerateBody -indexes $Indexes -collectionName $collectionName

        try {
            $Response = Invoke-RestMethod -Uri $Uri -Method 'POST' -Headers $Headers -Body $Body
        }
        catch {
            Write-Error "Error: $($_.Exception.Response.StatusDescription | ConvertTo-Json)"
        }

        Write-Output "Created Collection"
        Write-Output "Response: $($Response | ConvertTo-Json -Depth 5)"
    }

    function GenerateIndex {
        [CmdletBinding()]
        param(
            [Parameter()][ValidateSet('Hash','Range','Spatial')][String]$indexKind,
            [Parameter()][ValidateSet('Number','String','Point','LineString','Polygon')][String]$dataType,
            [Parameter()][Int]$Precision
        )

        $Index = @{"dataType" = $dataType; "precision" = $precision; "kind" = $indexKind}
        Write-Output $Index
    }

    function GenerateBody($collectionName, $indexes){
        $body = @{"id" = "$collectionName"}
        if($indexes -ne $null){
            $body.Add(
            "indexingPolicy", 
            @{"automatic" = $true; "indexingMode" = "Consistent";
                "includedPaths" = @(
                    @{"path"      = "/*";
                        "indexes" = $indexes
                    }
                )
            })
        }
        $body = ($body | ConvertTo-Json -Depth 5)
        Write-Output $body
    }

    function GenerateEncodedSignature($Verb, $ResourceId, $ResourceType, $Date) {
     
        $payloadInBytes = GeneratePayloadToBeSigned $Verb $ResourceId $ResourceType $Date
        $signature = SignPayload $payloadInBytes
        [System.Web.HttpUtility]::UrlEncode($('type=master&ver=1.0&sig=' + $signature))
    }

    function GeneratePayloadToBeSigned($Verb, $ResourceId, $ResourceType, $Date) {
    
        $text = $Verb.ToLowerInvariant() + "`n" + $ResourceType.ToLowerInvariant() + "`n" + $ResourceId + "`n" + $Date.ToLowerInvariant() + "`n" + "" + "`n"
        $body = [Text.Encoding]::UTF8.GetBytes($text)
        Write-Output $body
    }

    function SignPayload($payload) {

        $keyBytes = [System.Convert]::FromBase64String($this.DocumentDBMasterKey)
        $hmacsha = new-object -TypeName System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keyBytes) 
        $hash = $hmacsha.ComputeHash($payload)
        $signature = [System.Convert]::ToBase64String($hash)
        Write-Output $signature
    }

    function GetUTDate() {
        $date = get-date
        $date = $date.ToUniversalTime();
        Write-Output $date.ToString("r", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    function BuildHeaders ($action, $resType, $resourceId) {
        $date = GetUTDate
        $authorizeHeader = GenerateEncodedSignature -Verb $action -ResourceType $resType -ResourceId $resourceId -Date $date
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", $authorizeHeader)
        $headers.Add("x-ms-version", '2017-02-22')
        $headers.Add("x-ms-date", $date)
        $headers.Add("Content-Type", "application/json")
        Write-Output $headers
    }
}