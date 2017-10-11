# needed for URL encoding
Add-Type -AssemblyName System.Web

function new_documentDB_rest_client {
    param(
        [ValidateNotNullOrEmpty()]$documentDBEndpointUri = $(throw "Please pass in the endpoint Uri for documentDB"),
        [ValidateNotNullOrEmpty()]$documentDBMasterKey = $(throw "Please pass the document DB master key as a parameter")
    )

    $obj = New-Object PSObject -Property @{
        DocumentDBEndpointUri = $documentDBEndpointUri
        DocumentDBMasterKey   = $documentDBMasterKey
    }

    $obj | Add-Member -Type ScriptMethod -Name CreateDatabase -Value { param($databaseName)

        $uri = $this.DocumentDBEndpointUri + "/dbs"
        $hdr = BuildHeaders -resType "dbs" -action "post" -resourceId "" -primaryKey $this.DocumentDBMasterKey
        $body = (@{"id" = "$databaseName"} | ConvertTo-Json)
 
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $hdr -Body $body
        }
        catch {
            Write-Host "Error:$($_.Exception.Response.StatusDescription | ConvertTo-Json)"
        }
        Write-Host "Created database"
        Write-Host "Response: $($response | ConvertTo-Json)"
    }

    $obj | Add-Member -Type ScriptMethod -Name CreateCollection -Value { param($databaseName, $collectionName,[System.Array]$indexes=$null)

        $uri = $this.DocumentDBEndpointUri + "/dbs/$databaseName/colls"
        $headers = BuildHeaders -resType "colls" -action POST -resourceId "dbs/$databaseName" -primaryKey $this.DocumentDBMasterKey

        $body = GenerateBody -indexes $indexes -collectionName $collectionName
        
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        }
        catch {
            Write-Host "Error:$($_.Exception.Response.StatusDescription | ConvertTo-Json)"
        }
     
        Write-Host "Created collection"
        Write-Host "Response: $($response | ConvertTo-Json -Depth 5)"
    }

     $obj | Add-Member -Type ScriptMethod -Name GenerateIndex -Value {param(
          [ValidateSet('Hash','Range','Spatial')]$indexKind,
          [ValidateSet('Number','String','Point','LineString','Polygon')]$dataType,
          [int]$precision
     )
        $index = @{"dataType" = $dataType; "precision" = $precision; "kind" = $indexKind}
        $index
     }

    $obj
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
        $body
    }

    function GenerateEncodedSignature($Verb, $ResourceId, $ResourceType, $Date) {
     
        $payloadInBytes = GeneratePayloadToBeSigned $Verb $ResourceId $ResourceType $Date
        $signature = SignPayload $payloadInBytes
        [System.Web.HttpUtility]::UrlEncode($('type=master&ver=1.0&sig=' + $signature))
    }

    function GeneratePayloadToBeSigned($Verb, $ResourceId, $ResourceType, $Date) {
    
        $text = $Verb.ToLowerInvariant() + "`n" + $ResourceType.ToLowerInvariant() + "`n" + $ResourceId + "`n" + $Date.ToLowerInvariant() + "`n" + "" + "`n"
        $body = [Text.Encoding]::UTF8.GetBytes($text)
        $body
    }

    function SignPayload($payload) {

        $keyBytes = [System.Convert]::FromBase64String($this.DocumentDBMasterKey)
        $hmacsha = new-object -TypeName System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keyBytes) 
        $hash = $hmacsha.ComputeHash($payload)
        $signature = [System.Convert]::ToBase64String($hash)
        $signature
    }

    function GetUTDate() {
        $date = get-date
        $date = $date.ToUniversalTime();
        return $date.ToString("r", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    function BuildHeaders ($action, $resType, $resourceId) {
        $date = GetUTDate
        $authorizeHeader = GenerateEncodedSignature -Verb $action -ResourceType $resType -ResourceId $resourceId -Date $date
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", $authorizeHeader)
        $headers.Add("x-ms-version", '2017-02-22')
        $headers.Add("x-ms-date", $date)
        $headers.Add("Content-Type", "application/json")
        $headers
    }
