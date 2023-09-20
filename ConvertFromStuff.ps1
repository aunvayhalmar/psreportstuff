function ConvertFrom-PaddedStrings {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline,Position=0)]
        $InputObject
    )
    $fields = $InputObject[0].psobject.Properties.Name
    foreach($field in $fields){
        $f_c_s = $nodes.$field -match "^\s|\s$"
        if($f_c_s){
            for($i = 0 ;$i -lt ($InputObject.count);$i++){
                $InputObject[$i].$field = $InputObject[$i].$field.Trim()
            }
        }
    }
    return $InputObject
}

function Confirm-NotUnique {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline,Position=0)]
        $InputObject,
        [String]$Property
    )
    $groups = $InputObject | Group-Object -Property $Property -AsHashTable
    $NotUnique = @()
    foreach($group in $groups.Keys){        
        if($groups[$group].Count -ne 1){
            $NotUnique += $groups[$group]
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
        [hashtable]$ModifyUpdateHeader,
        [String[]]$KeepUpdateHeaders,
        [Parameter(Mandatory=$False)]
        [ValidateSet("Add","Remove","Update","AddRemove")]
        [String]$Mode,
        [Parameter(Mandatory = $true, ParameterSetName = 'Return')]
        [Switch]$Return,
        [Parameter(Mandatory = $true, ParameterSetName = 'Explore')]
        [Switch]$Explore,
        [Switch]$CloneInputObject
    )
    $InputObjectHeader          = $InputObject[0].psobject.Properties.Name
    $UpdateObjectOriginalHeader = $UpdateObject[0].psobject.Properties.Name
    $UpdateObjectNewHeader = $UpdateObject[0].psobject.Properties.Name
    if($CloneInputObject){ $InputObject = $InputObject | ConvertTo-Json | ConvertFrom-Json }
    $UpdateObject = $UpdateObject | ConvertTo-Json | ConvertFrom-Json
    $keep_un_headers = [Array]::CreateInstance([string],$UpdateObjectNewHeader.Count)
    $MissingHeaders = @()
    if ($ModifyUpdateHeader) {
        foreach($key in @($ModifyUpdateHeader.keys)) {
            if ($key -is [int] -and $key -lt $UpdateObjectOriginalHeader.count) {
                $UpdateObjectNewHeader[$key] = $ModifyUpdateHeader[$key]
                $keep_un_headers[$key] = $ModifyUpdateHeader[$key]
                $UpdateObject | Add-Member -MemberType AliasProperty -Name $UpdateObjectNewHeader[$key] -Value $UpdateObjectOriginalHeader[$key]
            } elseif ($UpdateObjectOriginalHeader.IndexOf($key) -ne -1) {
                $Index_of = $UpdateObjectOriginalHeader.IndexOf($key)
                $UpdateObjectNewHeader[$Index_of] = $ModifyUpdateHeader[$key]
                $keep_un_headers[$Index_of] = $ModifyUpdateHeader[$key]
                $UpdateObject | Add-Member -MemberType AliasProperty -Name $UpdateObjectNewHeader[$Index_of] -Value $UpdateObjectOriginalHeader[$Index_of]
            } else {
                $MissingHeaders += $key
            }
        }
        Write-Host "Original Header:" -NoNewline
        Write-Host $UpdateObjectOriginalHeader -Separator ","
        Write-Host "Updated Header:" -NoNewline
        Write-Host $UpdateObjectNewHeader  -Separator ","        
    }
    if ($KeyProperty -notin $UpdateObjectOriginalHeader -or $KeyProperty -notin $UpdateObjectNewHeader) {
        throw "The InputObject and UpdateObject do not have a Property named $KeyProperty."
    }
    if ($KeepUpdateHeaders) {
        foreach($key in $KeepUpdateHeaders) {
            if($key -in $UpdateObjectNewHeader){
                $Index_of = $UpdateObjectNewHeader.IndexOf($key)
                $keep_un_headers[$Index_of] = $key
            } else {
                $MissingHeaders += $key
            }
        }        
    }
    if($MissingHeaders){
        Write-Host "MissingHeaders:" -NoNewline
        Write-Host $MissingHeaders -Separator ","
    }    
    if ($keep_un_headers -ne $null) {
        $Index_of = $UpdateObjectNewHeader.IndexOf($KeyProperty)
        $keep_un_headers[$Index_of] = $KeyProperty
        $keep_un_headers = $keep_un_headers -ne $null | Select-Object -Unique
        $U_Object = $UpdateObject #| Select-Object -Property $keep_un_headers
        $NewHeader = $InputObjectHeader + $keep_un_headers | Select-Object -Unique
    } else {
        $U_Object = $UpdateObject
        $NewHeader = $InputObjectHeader + $UpdateObjectNewHeader | Select-Object -Unique
        $keep_un_headers = $UpdateObjectNewHeader
    }
    $u_header = $keep_un_headers -ne $KeyProperty
    $diff = Compare-Object -ReferenceObject $InputObject -DifferenceObject $U_Object -Property $KeyProperty
    $diff | Add-Member -MemberType AliasProperty -Name " " -Value 'SideIndicator'
    $adds,$removes = $diff.Where({$_.SideIndicator -eq "=>"}, "Split")
    if($Explore){
        $adds | Add-Member -NotePropertyName "SideIndicator" -NotePropertyValue "+" -Force
        $removes | Add-Member -NotePropertyName "SideIndicator" -NotePropertyValue "-" -Force
        Write-Host ($diff | Format-Table -Property " ",$KeyProperty | Out-String)
    }
    if($Return){
        $h_diff = Compare-Object -ReferenceObject $InputObjectHeader -DifferenceObject $NewHeader | Where-Object {$_.SideIndicator -eq "=>"}
        if($h_diff){
            $new_h = [ordered]@{}
            foreach($h in $h_diff.InputObject){
                $new_h[$h] = ""
            }
            $InputObject | Add-Member -NotePropertyMembers $new_h
        }
        $irows = [ordered]@{}
        foreach($row in $I_Object){
            $irows[$row.$KeyProperty] = $row
        }
        for($i = 0 ;$i -lt ($U_Object.count);$i++){
            $u = $U_Object[$i]
            if($null -ne $irows[$U_Object[$i].$KeyProperty]){
                $o = $irows[$u.$KeyProperty]
                foreach($field in $u_header){
                    $o.$field = $u.$field
                }
            } elseif ($Mode -in "Add","AddRemove") {
                $irows[$u.$KeyProperty] = $u | Select-Object -Property $NewHeader
            }
        }
        if ($Mode -in "Remove","AddRemove"){
            foreach($Remove in $removes){
                $irows[$Remove.$KeyProperty] = $null
            }
        }
        $ret = $irows.Values
        return $ret -ne $null
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
        [hashtable]$UpdateHeader,
        [switch]$IgnoreMissingHeaders
    )
    if(-not $InputObject -and -not $Path){    
        throw "The parameter InputObject or Path must be provided."
    } elseif ($InputObject -and $Path) {
        throw "The parameter InputObject and Path cannot both be provided."
    }
    if($InputObject){
        $all = $InputObject.Split([string[]]("`r`n","`n","`r"),[System.StringSplitOptions]::RemoveEmptyEntries)
        $head = [string[]]::new($Count)
        [array]::Copy($all,$head,$Count)
    } elseif ($Path -and $Return) {
        $all = Get-Content -Path $Path
    } elseif ($Path -and $Explore) {
        $head = Get-Content -Path $Path -TotalCount $Count
        $all = $head
    }
    $headers_all = @{}
    $headers_keys ="Original Header:","Header Parameter:","Updated Header:"
    $csvopt = @{}    
    if($Header){
        $csvopt["Header"] = $Header
        $headers_all["Header Parameter:"] = $Header
        $m_header = Write-Output $Header
    } elseif(@($PSBoundParameters.Keys).Contains("Index")){
        $h_obj = $all | Select-Object -Skip $Index -First 2 | ConvertFrom-Csv
        if($h_obj){
            $headers_all["Original Header:"] = $h_obj[0].psobject.Properties.Name
            $m_header = $h_obj[0].psobject.Properties.Name
        } else {
            throw "`"$($all[$Index])`" is not a valid CSV Header"
        }
    }
    if($UpdateHeader -and @($PSBoundParameters.Keys).Contains("Index")){
        $MissingHeaders = @()
        foreach($key in @($UpdateHeader.keys)) {
            if($key -is [int] -and $key -lt $m_header.count){
                $m_header[$key] = $UpdateHeader[$key]
            } elseif ($m_header.IndexOf($key) -ne -1) {
                $Index_of = $m_header.IndexOf($key)
                $m_header[$Index_of] = $UpdateHeader[$key]
            } else{
                $MissingHeaders += $key
            }
        }
        $csvopt["Header"] = $m_header
        $headers_all["Updated Header:"] = Write-Output $m_header
    }
    $R_Index = $Index
    if($UpdateHeader -and -not $Header){
        $R_Index++
    }    
    if ($Explore) {
        $template = [ordered]@{"Index"="";"Line"=""}
        $Lines = [Array]::CreateInstance([psobject],$Count)
        for($i = 0 ;$i -lt  $Count;$i++){
            $template["Index"] = $i
            $template["Line"] = $head[$i]
            $Lines[$i] = New-Object psobject -Property $template
        }
        if(@($PSBoundParameters.Keys).Contains("Index")){
            $Lines[$Index]."Index" = "[$Index]"
        }
        if (($Test -or $DumpHeader -or $ReturnHeader)) {            
            $testing =  $head | Select-Object -Skip $R_Index | ConvertFrom-Csv @csvopt
            if ($Test -and $testing) {
                return $testing
            } elseif ($DumpHeader -and $testing){
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
            foreach($key in $headers_keys) {
                $test_template = [ordered]@{}
                if($headers_all.ContainsKey($key)){
                    $test_template["Header Index"]=$key
                    for($i = 0 ;$i -lt $headers_all[$key].Count;$i++){
                        $test_template["$i"]=$headers_all[$key][$i]
                    }
                    $dh += New-Object psobject -Property $test_template
                }
            }
            $dh | Format-Table | Out-String | Write-Host
            if($MissingHeaders){
                Write-Host "MissingHeaders:"
                Write-Host $MissingHeaders
            }
        }
    } elseif ($Return) {
        $all | Select-Object -Skip $R_Index | ConvertFrom-Csv @csvopt
    }
}
