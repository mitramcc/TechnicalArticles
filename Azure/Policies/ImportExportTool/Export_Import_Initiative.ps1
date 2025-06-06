<# 
Disclaimer: This script is not supported under any Microsoft standard support program or service. This script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the script and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the script be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the current script or documentation, even if Microsoft has been advised of the possibility of such damages.
## Version: 1.2
#>

param (
  [Parameter(Mandatory, HelpMessage="Enter one of the valid directions: Export, Import, Full.")] [ValidateSet('Full','Export','Import')] $direction, 
  [Parameter(Mandatory, HelpMessage="Enter the Initiative Name (not displayname)")] [Alias("i", "ini")] $initativeId, 
  [Parameter(Mandatory, HelpMessage="Enter the scope (Subscription or ManagementGroup)")] [ValidateSet('Sub','mg','Subscription', 'ManagementGroup')] $scope="subscription", 
  [Parameter(HelpMessage="Enter the source subscription or Management Group (guid)")] [Alias("src")] $source, 
  [Parameter(HelpMessage="Enter the target subscription or Management Group (guid)")] [Alias("t", "trgt")] $target, 
  [switch] [Alias("ow")] $overwrite,
  [Parameter(HelpMessage="Enter the destinaton subscription or Management Group (guid)")] [Alias("dcat")] $defaultCategory="ExportImportScript", 
  [Parameter(HelpMessage="Enter the destinaton subscription or Management Group (guid)")] [Alias("owcat")] $overwriteCategory
)

function Export-Policy {
    param (
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $folderPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $PolicyId,
        [Parameter(Mandatory)] $csvPath,
        [switch] $overwrite
    )
    Write-Verbose "#############################################################################"
    Write-Verbose "############################## Export Policy ################################"
    Write-Verbose "#############################################################################"

    $policyObj                   = Get-AzPolicyDefinition -ResourceId $PolicyId
    $policyName                  = $policyObj | Select-Object -Property Name
    $propertiesExist = [bool]($policyObj.PSobject.Properties.name -match "Properties")
    if($propertiesExist){
        $policyDefinitionProperties  = $policyObj | Select-Object -ExpandProperty properties | Select-Object -Property PolicyRule, @{Name='Parameter'; Expression='Parameters'}, DisplayName, Metadata, PolicyType
    } else {
        $policyDefinitionProperties  = $policyObj
    }

    if (([string]::IsNullOrEmpty($policyDefinitionProperties.DisplayName))) {
        $policyDisplayName = $policyName.Name
    } else {
        $policyDisplayName = $policyDefinitionProperties.DisplayName
    }
    
    Write-Output "Exporting PolicyName: $($policyName.Name)"
    Write-Output "Exporting PolicyDisplayName: $($policyDisplayName)"
    Write-Debug "Exporting policyDefRule: $($policyDefinitionProperties.PolicyRule |  ConvertTo-Json -Depth 100)"
    Write-Debug "Exporting policyDefParams: $($policyDefinitionProperties.Parameter |  ConvertTo-Json -Depth 100)"
    Write-Output "Exporting policyType: $($policyDefinitionProperties.PolicyType)"
    
    if ($policyDefinitionProperties.PolicyType -eq "Custom"){     
        Write-Verbose "Exporting PolicyRuleJsonPath: $($folderPath)\$($policyName.Name)-def.json"
        Write-Verbose "Exporting PolicyParamsJsonPath: $($folderPath)\$($policyName.Name)-params.json"

        if ($policyDefinitionProperties.Metadata.category -eq $null) {
            $policyCategory = $defaultCategory
        } else {
            $policyCategory = $policyDefinitionProperties.Metadata.category
        }

        $csvDataRow = [ordered] @{
            Id       = $policyName.Name
            Name     = $policyDisplayName
            Category = $policyCategory
        }
        $csvData = @()
        $csvData = New-Object psobject -Property $csvDataRow 

        $policyDefJson    = $policyDefinitionProperties.PolicyRule | ConvertTo-Json -Depth 100
        $policyParameters = $policyDefinitionProperties.Parameter | ConvertTo-Json -Depth 100
        $policyDefinitionFilePath = Join-Path $folderPath "$($policyName.Name)-def.json"
        $policyParametersFilePath = Join-Path $folderPath "$($policyName.Name)-params.json"
        if($overwrite){
            $policyDefJson | Out-File -FilePath $policyDefinitionFilePath
            
            if( $policyParameters -ne "{}" -and $policyParameters -ne $null -and $policyParameters -ne "null"){
                $policyParameters | Out-File -FilePath $policyParametersFilePath
            }
        } else {
            $policyDefJson | Out-File -FilePath $policyDefinitionFilePath -NoClobber
            
            if( $policyParameters -ne "{}" -and $policyParameters -ne $null -and $policyParameters -ne "null" ){
                $policyParameters | Out-File -FilePath $policyParametersFilePath -NoClobber
            }
        }

        if( $policyParameters -eq "{}"){
            Write-Verbose "No parameters for this policy."
        }

        $csvData | Export-Csv -append -Path $csvPath
    }

}

function Import-Policy{

    param (
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $policyDefinitionFilePath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $policyName,
        [Parameter(Mandatory)] $nameMappings
    )

    Write-Verbose "#############################################################################"
    Write-Verbose "############################## Import Policy ################################"
    Write-Verbose "#############################################################################"

    $policyName = $_.Name.Replace("-def.json", "")
    Write-Output "PolicyName: $($policyName)"

    $policyDefinitionFilePath=$_.policyDefinitionFilePath
    Write-Verbose "PolicyDefinitionJsonFile: $($policyDefinitionFilePath)"

    $policyParametersFilePath=$policyDefinitionFilePath.Replace("-def.json", "-params.json")
    Write-Verbose "parametersPolicyFile: $($policyParametersFilePath)"

    $newPolicyCommand = "New-AzPolicyDefinition -Name ""$($policyName)"" -Policy ""$($policyDefinitionFilePath)"""
    
    if (Test-Path -Path $policyParametersFilePath -PathType Leaf) {
        $newPolicyCommand += " -Parameter ""$($policyParametersFilePath)"" "
    }
    
    if ($nameMappings){
        $displayName = $nameMappings."$($policyName)"[0]
        if ($displayName -ne $null) {
            $newPolicyCommand += " -DisplayName ""$($displayName)"" "
        }
        $policyCategory = $nameMappings."$($policyName)"[1]
        if ($policyCategory -ne $null) {
            $newPolicyCommand += " -Metadata '{""category"":""$($policyCategory)""}' "
        }
    }                 
    
    $newPolicyCommand = "$($newPolicyCommand) $scopeParameter $target"
    
    Write-Verbose $newPolicyCommand
    Invoke-Expression -Command $newPolicyCommand
}

##### Sanitize Parameters #### 
if($direction -eq "Export" -or $direction -eq "Import"){
    if($target -eq $null){
        $target=$source #Same id
    }
}

##### Sanitize Parameters #### 
if($scope -like "m*"){
    $scopeParameter = "-ManagementGroupName "
    $targetReplace  = "/providers/Microsoft.Management/managementGroups/"
} else {
    $scopeParameter = "-SubscriptionId "
    $targetReplace  = "/subscriptions/"
}


if($direction -eq "Export" -or $direction -eq "Import" -or $direction -eq "Full"){
    
    #############################################################################
    ################################## Export  ##################################
    #############################################################################
    if($direction -eq "Export" -or $direction -eq "Full"){

        Write-Output "###### Export ######"
        if ($scopeParameter -like "-SubscriptionId*"){
            # If you are not connected yet you will need to run this to connect
            #Connect-AzAccount -UseDeviceAuthentication
            $context = Set-AzContext -Subscription $source
            
            if (!$context) {
                throw "Error setting the context for subscription $($source)"
            }
        }

        # To export multiple initiatives adjust the expression to return multiple initiatives. example: Get-AzPolicySetDefinition -Custom to get all custom initiatives.
        if ($initativeId -eq "*") {
            $fetchInitiaveExpression = "Get-AzPolicySetDefinition -Custom $scopeParameter $source"
        } else {
            $fetchInitiaveExpression = "Get-AzPolicySetDefinition -Name ""$($initativeId)""  $scopeParameter $source"
        }
        $initiativeList = Invoke-Expression -Command $fetchInitiaveExpression
        $initiativeList | ForEach-Object {
            $nameMappings = @()
            $InitiativeID = $_.Name
            Write-Output "--------------------------------------"
            Write-Output "Exporting Initiative: $($InitiativeID)"
            $folderPath =  Join-Path $PSScriptRoot $InitiativeID
            if (Test-Path -Path $folderPath) {
                "Directory $($folderPath) exists"
            } else {
                "Directory $($folderPath) created"
                mkdir $folderPath
            }
            
            $propertiesExist = [bool]($_.PSobject.Properties.name -match "Properties")
            if($propertiesExist){
                $properties              = $_ | Select-object -ExpandProperty Properties        
                $initiativeName          = $properties | Select-Object -Property DisplayName
                $initiativeParams        = $properties | Select-object -ExpandProperty  Parameters | ConvertTo-Json -Depth 100 
                $InitiativeDefinitionObj = $properties | Select-object -ExpandProperty PolicyDefinitions
                $metadata                = $properties | Select-object -ExpandProperty Metadata
                $policyGroups            = $properties | Select-object -ExpandProperty PolicyDefinitionGroup
            } else {
                $initiativeName          = $_ | Select-Object -Property DisplayName
                $initiativeParams        = $_ | Select-object -ExpandProperty  Parameter | ConvertTo-Json -Depth 100 
                $InitiativeDefinitionObj = $_ | Select-object -ExpandProperty PolicyDefinition
                $metadata                = $_ | Select-object -ExpandProperty Metadata
                $policyGroups            = $_ | Select-object -ExpandProperty PolicyDefinitionGroup
            }
            Write-Verbose "Exporting InitiativeDisplayName: $($initiativeName.DisplayName)"

            if( $initiativeParams -ne "{}" -and $initiativeParams -ne $null -and $initiativeParams -ne "null" ){
                if($overwrite){
                    $initiativeParams | Out-File -FilePath "$($folderPath)-params.json"
                } else {
                    $initiativeParams | Out-File -FilePath "$($folderPath)-params.json" -NoClobber
                }
                Write-Verbose "Exporting InitiativeParamsJsonPath: $($folderPath)-params.json"
            } else {
                Write-Verbose "No parameters for the initiative."
            }
            
            $InitiativeDefinitionJson = $InitiativeDefinitionObj | ConvertTo-Json -Depth 100 -AsArray

            # if ($direction -eq "Full") {
            if ($target) {
                $finalTarget = "$($targetReplace)$target"
                $InitiativeDefinitionJson = $InitiativeDefinitionJson -replace '(.*\"\:\s)(.*)(?<Rest>\/providers/Microsoft.Authorization/policy.*)\"',('$1"' + $finalTarget + '${Rest}"')
            }

            if($overwrite){
                $InitiativeDefinitionJson | Out-File -FilePath "$($folderPath)-def.json"
                
                if (-not ([string]::IsNullOrEmpty($policyGroups))){
                    $policyGroups | ConvertTo-Json -Depth 100 -AsArray | Out-File -FilePath "$($folderPath)-groups.json"
                } 
            } else {
                $InitiativeDefinitionJson | Out-File -FilePath "$($folderPath)-def.json" -NoClobber
                
                if (-not ([string]::IsNullOrEmpty($policyGroups))){
                    $policyGroups | ConvertTo-Json -Depth 100 -AsArray | Out-File -FilePath "$($folderPath)-groups.json" -NoClobber
                } 
            }

            Write-Debug "Exporting policyDefRule: $($InitiativeDefinitionJson)"
            Write-Debug "Exporting policyDefParams: $($initiativeParams)"
            Write-Verbose "Exporting InitiativeDefJsonPath: $($folderPath)-def.json"
            Write-Verbose "Exporting policyGroups: $($folderPath)-groups.json"

            if (([string]::IsNullOrEmpty($initiativeName.DisplayName))){
                $initiativeDisplayName = $InitiativeID
            } else {
                $initiativeDisplayName = $initiativeName.DisplayName
            }

            #Category
            if ($metadata.category -eq $null) {
                $category = $defaultCategory
            } else {
                $category = $metadata.category
            }
            
            $mappingsCsvName = ".\Mappings-$($InitiativeID).csv"
            $csvDataRow = [ordered] @{
                Id       = $InitiativeID
                Name     = $initiativeDisplayName
                Category = $category
            }
            
            $nameMappings += New-Object psobject -Property $csvDataRow
            $nameMappings | Export-Csv -Path $mappingsCsvName -NoTypeInformation
            
            #loop through policies
            $InitiativeDefinitionObj | ForEach-Object {
                # save definition and variables file
                $policyId   = $_.policyDefinitionId
                
                if($overwrite){
                    Export-Policy -folderPath $folderPath -PolicyId $policyId -overwrite -csvPath $mappingsCsvName
                } else {
                    Export-Policy -folderPath $folderPath -PolicyId $policyId -csvPath $mappingsCsvName
                }
            }
        }
    }
    
    #############################################################################
    ################################## Import  ##################################
    #############################################################################
    if($direction -eq "Import" -or $direction -eq "Full") {

        Write-Output "###### Import ######"
        <#### IMPORTANT ######
        When running Import individually make sure the <initiativeId>-def.json file 
        contains the right target scope being that subscriptions or management groups.
        ##### IMPORTANT #####>

        if ($scopeParameter -like "-SubscriptionId*"){
            # If you are not connected yet you will need to run this to connect
            #Connect-AzAccount -UseDeviceAuthentication 
            $context = Set-AzContext -Subscription $target
            
            if (!$context) {
                throw "Error setting the context for subscription $($target)"
            }
        }
        
        # To import multiple initiatives at same time replace the $($initativeId) with * or use the parameter initativeId with value *
        Get-ChildItem -Path . -Filter "$($initativeId)-def.json" `
        | Select-Object Name, @{Name = 'initiativeDefinitionFilePath'; Expression = {$_.FullName}} `
        | Foreach-Object {
            $initiativeDefinitionFilePath = $_.initiativeDefinitionFilePath
            Write-Verbose "InitiativeJsonFile: $($initiativeDefinitionFilePath)"
            $initiativeName = $_.Name.Replace("-def.json", "")
            Write-Output "Importing policies from initiative: $($initiativeName)"
            
            $mappingsPath = ".\Mappings-$($initiativeName).csv"
            $fileExists = Test-Path -Path $mappingsPath
            $hash = @{} 
            if ($fileExists) {
                $nameMappings = Import-Csv -Path $mappingsPath
                $nameMappings | ForEach-Object { 
                    $hash[$_.Id] = @($_.Name, $_.Category)
                }
                $nameMappings = $hash
            } else {
                $nameMappings=$false;
            }
            
            $initiativePoliciesFolderPath = Join-Path "." "$($initiativeName)"
            Get-ChildItem -Path $initiativePoliciesFolderPath -Filter "*-def.json" `
            | Select-Object Name, @{Name = 'policyDefinitionFilePath'; Expression = {$_.FullName}}   `
            | Foreach-Object {
                Import-Policy -policyDefinitionFilePath $_.policyDefinitionFilePath -policyName $_.Name -nameMappings $nameMappings                
            }

            #check if has parameters file
            $initiativeParametersFilePath = $false
            Get-ChildItem -Path . -Filter "$($initiativeName)-params.json" `
            | Select-Object @{Name = 'initiativeParametersFilePath'; Expression = {$_.FullName}} `
            | Foreach-Object {
                $initiativeParametersFilePath = $_.initiativeParametersFilePath
                Write-Verbose "InitiativeParametesFile: $($initiativeParametersFilePath)"
            }

            #check if has groups file
            $initiativeGroupsFilePath = $false
            Get-ChildItem -Path . -Filter "$($initiativeName)-groups.json" `
            | Select-Object @{Name = 'initiativeGroupsFilePath'; Expression = {$_.FullName}} `
            | Foreach-Object {
                $initiativeGroupsFilePath = $_.initiativeGroupsFilePath
                Write-Verbose "InitiativeParametesFile: $($initiativeGroupsFilePath)"
            }
        
            $initiativeDefJson = Get-Content -Path $initiativeDefinitionFilePath
            
            # Replace the policy definitions ids by the id that will exist on the target.
            if ($target) {
                $finalTarget = "$($targetReplace)$target"
                $initiativeDefJson = $initiativeDefJson -replace '(.*\"\:\s)(.*)(?<Rest>\/providers/Microsoft.Authorization/policy.*)\"',('$1"' + $finalTarget + '${Rest}"')
                $initiativeDefJson | Out-File -FilePath "$($initativeId)-def-imported.json" -NoClobber
                $importFileName = "$($initativeId)-def-imported.json"
            }
            
            $json = $initiativeDefJson | ConvertTo-Json -Depth 100
            Write-Verbose $json

            $newInitiativeCommand = "New-AzPolicySetDefinition -Name ""$($initiativeName)"" -PolicyDefinition ""$($importFileName)"""
            
            if (Test-Path -Path $initiativeParametersFilePath -PathType Leaf) {
                $newInitiativeCommand += " -Parameter ""$($initiativeParametersFilePath)"" "
            }
            
            if (Test-Path -Path $initiativeGroupsFilePath -PathType Leaf) {
                $newInitiativeCommand += " -PolicyDefinitionGroup ""$($initiativeGroupsFilePath)"" "
            }
            
            if ($nameMappings){
                $displayName = $nameMappings."$($initiativeName)"[0]
                if ($displayName -ne $null) {
                    $newInitiativeCommand += " -DisplayName ""$($displayName)"" "
                }

                $initiativeCategory = $nameMappings."$($initiativeName)"[1]
                if($overwriteCategory){
                    $initiativeCategory = $overwriteCategory
                }
                if ($initiativeCategory -ne $null) {
                    $newInitiativeCommand += " -Metadata '{""category"":""$($initiativeCategory)""}' "
                }
            }
            
            $newInitiativeCommand += " $scopeParameter $target"
            
            Write-Output "Initiative: $($initiativeName)"
            Write-Verbose $newInitiativeCommand
            Invoke-Expression -Command $newInitiativeCommand

            #remove the file created to hold the string replacement
            Remove-Item -Path $importFileName

        }
    } 
} else {
    Write-Error "Unknow Error!"
}