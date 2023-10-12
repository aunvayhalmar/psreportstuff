

function ConvertFrom-PaddedStrings {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        $InputObject
    )
    $PropertyNames = $InputObject[0].psobject.Properties.Name
    foreach ($eachpropertyname in $PropertyNames) {
        $PropertyValuesContainingSpaces = $InputObject.$eachpropertyname -match "^\s|\s$"
        if ($PropertyValuesContainingSpaces) {
            for ($index = 0 ;$index -lt ($InputObject.count);$index++) {
                if ($InputObject[$index].$eachpropertyname -is [string]) {
                    $InputObject[$index].$eachpropertyname = $InputObject[$index].$eachpropertyname.Trim()
                }
            }
        }
    }
    return $InputObject
}


function Confirm-NotUnique {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        $InputObject,
        [String]$Property
    )
    $ObjectGroups = $InputObject | Group-Object -Property $Property -AsHashTable
    $NotUnique = @()
    foreach ($eachpropertyname in $ObjectGroups.Keys) {
        if ($ObjectGroups[$eachpropertyname].Count -ne 1) {
            $NotUnique += $ObjectGroups[$eachpropertyname]
        }
    }
    return $NotUnique
}


function Update-Table {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        $InputObject,
        [Parameter(Mandatory)]
        [String]$KeyProperty,
        $UpdateObject,
        [String]$UpdateKeyProperty,
        [hashtable]$ModifyUpdateHeader,
        [String[]]$KeepUpdateHeaders,
        [Parameter(Mandatory=$True)]
        [ValidateSet("Add","Remove","Update","AddRemove")]
        [String]$Mode,
        [Parameter(Mandatory = $true, ParameterSetName = 'Return')]
        [Switch]$Return,
        [Parameter(Mandatory = $true, ParameterSetName = 'Explore')]
        [Switch]$Explore,
        [Switch]$CloneInputObject,
        [Switch]$DontUpdateValueWithEmpty
    )
    if (-not $UpdateKeyProperty) {
         $UpdateKeyProperty = $KeyProperty
    }
    $PreModifyUpdateKeyProperty = $UpdateKeyProperty
    $InputObjectHeader = $InputObject[0].psobject.Properties.Name
    $UpdateObjectOriginalHeader = $UpdateObject[0].psobject.Properties.Name
    $UpdateObjectNewHeader = $UpdateObject[0].psobject.Properties.Name
    $KeepUpdateNewHeader = [Array]::CreateInstance([string],$UpdateObjectNewHeader.Count)
    $MissingHeaders = @()
    if ($ModifyUpdateHeader) {
        foreach ($eachkey in @($ModifyUpdateHeader.keys)) {
            if ($eachkey -is [int] -and $eachkey -lt $UpdateObjectOriginalHeader.count) {
                $Index_of_key = $eachkey
            } elseif ($eachkey -in $UpdateObjectOriginalHeader) {
                $Index_of_key = $UpdateObjectOriginalHeader.IndexOf($eachkey)
            } else {
                $MissingHeaders += $eachkey
                continue
            }
            $UpdateObjectNewHeader[$Index_of_key] = $ModifyUpdateHeader[$eachkey]
            $KeepUpdateNewHeader[$Index_of_key] = $ModifyUpdateHeader[$eachkey]
            if ($ModifyUpdateHeader[$eachkey] -eq $UpdateKeyProperty) {
                $PreModifyUpdateKeyProperty = $UpdateObjectOriginalHeader[$Index_of_key]
            }
        }
        $check_UpdateObjectNewHeader = @{}
        foreach ($h in $UpdateObjectNewHeader){
            if(-not $check_UpdateObjectNewHeader[$h]){
                $check_UpdateObjectNewHeader[$h] = $true
            } else {
                throw "The Updated Header contains $h more then once."
            }
        }
        Write-Host "Original Header: $($UpdateObjectOriginalHeader -join ",")"
        Write-Host " Updated Header: $($UpdateObjectNewHeader -join ",")"
    }
    if ($KeyProperty -notin $InputObjectHeader -or $UpdateKeyProperty -notin $UpdateObjectNewHeader) {
        throw "The InputObject and UpdateObject do not have a Property named $KeyProperty." #fixme
    }
    if ($KeepUpdateHeaders) {
        foreach($key in $KeepUpdateHeaders) {
            if($key -in $UpdateObjectNewHeader){
                $Index_of_key = $UpdateObjectNewHeader.IndexOf($key)
                $KeepUpdateNewHeader[$Index_of_key] = $key
            } else {
                $MissingHeaders += $key
            }
        }
        $KeepUpdateNewHeader = $KeepUpdateNewHeader -ne $null -ne $UpdateKeyProperty | Select-Object -Unique
        $NewHeader = $InputObjectHeader + $KeepUpdateNewHeader | Select-Object -Unique
    } else {
        $KeepUpdateNewHeader = $UpdateObjectNewHeader -ne $UpdateKeyProperty
        $NewHeader = $InputObjectHeader + $KeepUpdateNewHeader | Select-Object -Unique
    }
    if ($MissingHeaders) {
        Write-Host "MissingHeaders: $($MissingHeaders -join ",")"
    }
    $CompareOptions = @{
        ReferenceObject=$InputObject.$KeyProperty;
        DifferenceObject=$UpdateObject.$PreModifyUpdateKeyProperty
    }
    $AddsAndRemoves = Compare-Object @CompareOptions
    $Adds,$Removes = $AddsAndRemoves.Where({$_.SideIndicator -eq "=>"}, "Split")
    if ($Explore) {
        $AddsAndRemoves | Add-Member -MemberType AliasProperty -Name " " -Value 'SideIndicator'
        if ($Mode -in "Remove","AddRemove") {
            $Removes | Add-Member -NotePropertyName "SideIndicator" -NotePropertyValue "-" -Force    
        }
        if ($Mode -in "Add","AddRemove") {
            $Adds | Add-Member -NotePropertyName "SideIndicator" -NotePropertyValue "+" -Force
        }
        Write-Host ($AddsAndRemoves | Where-Object {$_.' ' -in "+","-"} | Format-Table -Property " ","InputObject" -HideTableHeaders | Out-String)
    } elseif ($Return) {
        if ($CloneInputObject) {
            $InputObject = $InputObject | ConvertTo-Json | ConvertFrom-Json
        }
        if ($ModifyUpdateHeader) {
            $UpdateObject = $UpdateObject | ConvertTo-Csv | ConvertFrom-Csv -Header $UpdateObjectNewHeader
        }
        $Header_diff = Compare-Object -ReferenceObject $InputObjectHeader -DifferenceObject $NewHeader | Where-Object {$_.SideIndicator -eq "=>"}
        if ($Header_diff) {
            $New_Header_Table = [ordered]@{}
            foreach ($eachheader in $Header_diff.InputObject) {
                $New_Header_Table[$eachheader] = ""
            }
            $InputObject | Add-Member -NotePropertyMembers $New_Header_Table
        }
        $InputObject_Table = [ordered]@{}
        if ($Mode -in "Remove","AddRemove") {
            $RemovesList = $Removes.InputObject
            foreach ($eachObject in $InputObject) {
                if ($eachObject.$KeyProperty -notin $RemovesList) {
                    $InputObject_Table[$eachObject.$KeyProperty] = $eachObject
                }
            }
        } else {
            foreach ($eachObject in $InputObject) {
                $InputObject_Table[$eachObject.$KeyProperty] = $eachObject
            }
        }
        for ($index = 0 ;$index -lt ($UpdateObject.count);$index++) {
            $eachUpdateObject = $UpdateObject[$index]
            if ($InputObject_Table[$eachUpdateObject.$UpdateKeyProperty]) {
                $MatchedInputItem = $InputObject_Table[$eachUpdateObject.$UpdateKeyProperty]
                foreach ($eachProperty in $KeepUpdateNewHeader) {
                    if ($DontUpdateValueWithEmpty -and [String]::IsNullOrWhiteSpace($eachUpdateObject.$eachProperty)) {
                        continue
                    }
                    $MatchedInputItem.$eachProperty = $eachUpdateObject.$eachProperty
                }
            } elseif ($Mode -in "Add","AddRemove") {
                $InputObject_Table[$eachUpdateObject.$UpdateKeyProperty] = $eachUpdateObject | Select-Object -Property $NewHeader
                $InputObject_Table[$eachUpdateObject.$UpdateKeyProperty].$KeyProperty = $eachUpdateObject.$UpdateKeyProperty
            }
            $UpdateObject[$index] = $null
        }
        return $InputObject_Table.Values
    }
}


function ConvertFrom-ReportCSV {
    [CmdletBinding(DefaultParameterSetName = 'Return')]
    param (
        [Parameter(ValueFromPipeline,Position=0)]
        [String]$InputObject,
        [ValidateScript({ Test-Path -Path $_ -PathType "Leaf" })]
        [String]$Path,
        [UInt32]$Count = 10,
        [UInt32]$Index = 0,
        [Parameter(Mandatory = $true, ParameterSetName = 'Return')]
        [Switch]$Return,
        [Parameter(ParameterSetName = 'Explore')]
        [Switch]$Test,
        [Parameter(ParameterSetName = 'Explore')]
        [Switch]$DumpHeader,
        [Parameter(ParameterSetName = 'Explore')]
        [Switch]$ReturnHeader,
        [Parameter(Mandatory = $true, ParameterSetName = 'Explore')]
        [Switch]$Explore,
        [String[]]$Header,
        [hashtable]$ModifyHeader,
        [switch]$IgnoreMissingHeaders
    )
    if (-not $InputObject -and -not $Path) {
        throw "The parameter InputObject or Path must be provided."
    } elseif ($InputObject -and $Path) {
        throw "The parameter InputObject and Path cannot both be provided."
    }
    if ($InputObject) {
        $AllLinesRead = $InputObject.Split([string[]]("`r`n","`n","`r"),[System.StringSplitOptions]::RemoveEmptyEntries)
        $FirstLines = [string[]]::new($Count)
        [array]::Copy($AllLinesRead,$FirstLines,$Count)
    } elseif ($Path -and $Return) {
        $AllLinesRead = Get-Content -Path $Path
    } elseif ($Path -and $Explore) {
        $FirstLines = Get-Content -Path $Path -TotalCount $Count
        $AllLinesRead = $FirstLines
    }
    $AllHeaders = @{}
    $headers_keys = "Original Header:","Header Parameter:","Updated Header:"
    $csvopt = @{}
    if ($Header) {
        $csvopt["Header"] = $Header
        $AllHeaders["Header Parameter:"] = $Header
        $m_header = Write-Output $Header
    } elseif (@($PSBoundParameters.Keys).Contains("Index")) {
        $h_obj = $AllLinesRead | Select-Object -Skip $Index -First 2 | ConvertFrom-Csv
        if ($h_obj) {
            $AllHeaders["Original Header:"] = $h_obj[0].psobject.Properties.Name
            $m_header = $h_obj[0].psobject.Properties.Name
        } else {
            throw "`"$($AllLinesRead[$Index])`" is not a valid CSV Header"
        }
    }
    if ($ModifyHeader -and @($PSBoundParameters.Keys).Contains("Index")) {
        $MissingHeaders = @()
        foreach ($key in @($ModifyHeader.keys)) {
            if ($key -is [int] -and $key -lt $m_header.count) {
                $m_header[$key] = $ModifyHeader[$key]
            } elseif ($m_header.IndexOf($key) -ne -1) {
                $Index_of = $m_header.IndexOf($key)
                $m_header[$Index_of] = $ModifyHeader[$key]
            } else {
                $MissingHeaders += $key
            }
        }
        $csvopt["Header"] = $m_header
        $AllHeaders["Updated Header:"] = Write-Output $m_header
    }
    $R_Index = $Index
    if ($ModifyHeader -and -not $Header) {
        $R_Index++
    }
    if ($Explore) {
        $template = [ordered]@{"Index"="";"Line"=""}
        $Lines = [Array]::CreateInstance([psobject],$Count)
        for ($i = 0 ;$i -lt  $Count;$i++) {
            $template["Index"] = $i
            $template["Line"] = $FirstLines[$i]
            $Lines[$i] = New-Object psobject -Property $template
        }
        if (@($PSBoundParameters.Keys).Contains("Index")) {
            $Lines[$Index]."Index" = "[$Index]"
        }
        if ($Test -or $DumpHeader -or $ReturnHeader) {
            $testing =  $FirstLines | Select-Object -Skip $R_Index | ConvertFrom-Csv @csvopt
            if ($Test -and $testing) {
                return $testing
            } elseif ($DumpHeader -and $testing) {
                return ($testing[0].psobject.Properties.Name | ConvertTo-Json -Compress ).Trim([char[]]@("[","]"))
            } elseif ($ReturnHeader -and $testing) {
                return $testing[0].psobject.Properties.Name
            } else {
                throw "Failed to Parse valid CSV Data"
            }
        } else {
            Write-Host "First $Count Lines of Input as <String[]>:" -NoNewline
            $Lines | Format-Table -Property @{Name="Index";expression={$_."Index"};alignment="center"},"Line" | Out-String | Write-Host
            $dh = @()
            foreach ($key in $headers_keys) {
                $test_template = [ordered]@{}
                if ($AllHeaders.ContainsKey($key)) {
                    $test_template["Header Index"]=$key
                    for ($i = 0 ;$i -lt $AllHeaders[$key].Count;$i++) {
                        $test_template["$i"]=$AllHeaders[$key][$i]
                    }
                    $dh += New-Object psobject -Property $test_template
                }
            }
            $dh | Format-Table | Out-String | Write-Host
            if ($MissingHeaders) {
                Write-Host "MissingHeaders:"
                Write-Host $MissingHeaders
            }
        }
    } elseif ($Return) {
        $AllLinesRead | Select-Object -Skip $R_Index | ConvertFrom-Csv @csvopt
    }
}

