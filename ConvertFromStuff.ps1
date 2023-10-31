

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
        foreach ($eachUpdateObjectNewHeader in $UpdateObjectNewHeader){
            if(-not $check_UpdateObjectNewHeader[$eachUpdateObjectNewHeader]){
                $check_UpdateObjectNewHeader[$eachUpdateObjectNewHeader] = $true
            } else {
                throw "The Updated Header contains $eachUpdateObjectNewHeader more then once."
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
                $KeepUpdateNewHeader[$UpdateObjectNewHeader.IndexOf($key)] = $key
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
        "ReferenceObject" = $InputObject.$KeyProperty
        "DifferenceObject" = $UpdateObject.$PreModifyUpdateKeyProperty
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
            $UpdateObject = $UpdateObject | ConvertTo-Csv | Select-Object -Skip 1 | ConvertFrom-Csv -Header $UpdateObjectNewHeader
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
    $CSVParameters = @{"WarningAction"="SilentlyContinue"}
    if ($Header) {
        $CSVParameters["Header"] = $Header
        $AllHeaders["Header Parameter:"] = $Header
        $ModifiedHeader = Write-Output $Header
    } elseif (@($PSBoundParameters.Keys).Contains("Index")) {
        $HeaderObject = $AllLinesRead | Select-Object -Skip $Index -First 2 | ConvertFrom-Csv
        if ($HeaderObject) {
            $AllHeaders["Original Header:"] = $HeaderObject[0].psobject.Properties.Name
            $ModifiedHeader = $HeaderObject[0].psobject.Properties.Name
        } else {
            throw "`"$($AllLinesRead[$Index])`" is not a valid CSV Header"
        }
    }
    if ($ModifyHeader -and @($PSBoundParameters.Keys).Contains("Index")) {
        $MissingHeaders = @()
        foreach ($eachModifyHeader in @($ModifyHeader.keys)) {
            if ($eachModifyHeader -is [int] -and $eachModifyHeader -lt $ModifiedHeader.count) {
                $the_index_of_key = $eachModifyHeader                
            } elseif ($eachModifyHeader -in $ModifiedHeader) {
                $the_index_of_key = $ModifiedHeader.IndexOf($eachModifyHeader)                
            } else {
                $MissingHeaders += $eachModifyHeader
                continue
            }
            $ModifiedHeader[$the_index_of_key] = $ModifyHeader[$eachModifyHeader]
        }
        $CSVParameters["Header"] = $ModifiedHeader
        $AllHeaders["Updated Header:"] = Write-Output $ModifiedHeader
    }
    $Shifted_Index = $Index
    if ($ModifyHeader -and -not $Header) {
        $Shifted_Index++
    }
    if ($Explore) {
        $Lines = [Array]::CreateInstance([psobject],$Count)
        for ($line_i = 0 ;$line_i -lt  $Count;$line_i++) {
            $Lines[$line_i] = New-Object psobject -Property ([ordered]@{"Index"=$line_i;"Line"=$FirstLines[$line_i]})
        }
        if (@($PSBoundParameters.Keys).Contains("Index")) {
            $Lines[$Index]."Index" = "[$Index]"
        }
        if ($Test -or $DumpHeader -or $ReturnHeader) {
            $testing =  $FirstLines | Select-Object -Skip $Shifted_Index | ConvertFrom-Csv @CSVParameters
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
            $HeaderInfo = @()
            foreach ($key in $headers_keys) {
                $eachHeaderInfoRow = [ordered]@{"Header Index"=$key;}
                if ($AllHeaders.ContainsKey($key)) {
                    for ($AllHeaders_i = 0 ;$AllHeaders_i -lt $AllHeaders[$key].Count;$AllHeaders_i++) {
                        $eachHeaderInfoRow["$AllHeaders_i"]=$AllHeaders[$key][$AllHeaders_i]
                    }
                    $HeaderInfo += New-Object psobject -Property $eachHeaderInfoRow
                }
            }
            $HeaderInfoProperties = $HeaderInfo[0].psobject.Properties.Name
            $HeaderInfo | Format-Table -Property $HeaderInfoProperties | Out-String | Write-Host
            if ($MissingHeaders) {
                Write-Host "MissingHeaders:"
                Write-Host $MissingHeaders
            }
        }
    } elseif ($Return) {
        $AllLinesRead | Select-Object -Skip $Shifted_Index | ConvertFrom-Csv @CSVParameters
    }
}


function ConvertFrom-Base64 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True,Position=0,ValueFromPipeline)]
        [string]$InputObject
    )
    $b64char = @{
        [char]"A"=0; [char]"B"=1; [char]"C"=2; [char]"D"=3; [char]"E"=4;
        [char]"F"=5; [char]"G"=6; [char]"H"=7; [char]"I"=8; [char]"J"=9;
        [char]"K"=10;[char]"L"=11;[char]"M"=12;[char]"N"=13;[char]"O"=14;
        [char]"P"=15;[char]"Q"=16;[char]"R"=17;[char]"S"=18;[char]"T"=19;
        [char]"U"=20;[char]"V"=21;[char]"W"=22;[char]"X"=23;[char]"Y"=24;
        [char]"Z"=25;[char]"a"=26;[char]"b"=27;[char]"c"=28;[char]"d"=29;
        [char]"e"=30;[char]"f"=31;[char]"g"=32;[char]"h"=33;[char]"i"=34;
        [char]"j"=35;[char]"k"=36;[char]"l"=37;[char]"m"=38;[char]"n"=39;
        [char]"o"=40;[char]"p"=41;[char]"q"=42;[char]"r"=43;[char]"s"=44;
        [char]"t"=45;[char]"u"=46;[char]"v"=47;[char]"w"=48;[char]"x"=49;
        [char]"y"=50;[char]"z"=51;[char]"0"=52;[char]"1"=53;[char]"2"=54;
        [char]"3"=55;[char]"4"=56;[char]"5"=57;[char]"6"=58;[char]"7"=59;
        [char]"8"=60;[char]"9"=61;[char]"+"=62;[char]"/"=63;[char]"="=64;
        [char]","=63;
        [char]"-"=62;[char]"_"=63;
    }
    $PaddingMultipliers = @(0,0,2,1)
    if($InputObject.IndexOf([char]"`n") -ne -1){
        $InputObject = [string]::Join("",($InputObject.Split([string[]]("`r`n","`n","`r"),[System.StringSplitOptions]::RemoveEmptyEntries)))
    }
    $InputObject += "="*$PaddingMultipliers[($InputObject.length % 4)]
    if ($InputObject[-2] -eq [char]"=") {
        $ReturnObjectLength = $InputObject.Length / 4 * 3 - 2        
    } elseif($InputObject[-1] -eq [char]"=") {
        $ReturnObjectLength = $InputObject.Length / 4 * 3 - 1
    } else {
        $ReturnObjectLength = $InputObject.Length / 4 * 3
    }
    $InputObjectLengthMinusOne = $InputObject.length / 4 - 1    
    $d64s = [byte[]]::new($ReturnObjectLength)
    for($f = 0 ;$f -lt  $InputObjectLengthMinusOne;$f++){
        $s = 4 * $f
        $a = 3 * $f
        $n = $b64char[$InputObject[$s]]
        foreach($i in 1,2,3){
            $n = $n -shl 6
            $n = $n + $b64char[$InputObject[$s+$i]]
        }
        $b = [bigint]::new($n)
        $ba = $b.ToByteArray($false,$true)
        $ba.CopyTo($d64s,$a)
    }
    $s = 4 * $f
    $a = 3 * $f
    $n = $b64char[$InputObject[$s]]
    foreach($i in 1,2,3){
        $n = $n -shl 6
        $n = $n + $b64char[$InputObject[$s+$i]]
    }
    if($InputObject[-2] -eq [char]"=") {
        $n = $n -shr 16
    } elseif($InputObject[-1] -eq [char]"=") {
        $n = $n -shr 8
    }
    $b = [bigint]::new($n)
    $ba = $b.ToByteArray($false,$true)
    $ba.CopyTo($d64s,$a)
    return $d64s
}
