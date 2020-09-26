function Login-AzureSubscription {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $false)] [System.Management.Automation.PSCredential]$Credential     
    )

    Write-Verbose "Login-AzureSubscription is running."
    Write-Verbose "Obtaining subscriptions."

    $context = Get-AzContext

    if ($null -eq $context.Account) {        
        Login-AzAccount -Credential $Credential
    }
    $subscriptions = Get-AzContextSubscription -ErrorAction SilentlyContinue

    if ($null -eq $subscriptions) {
        throw "Login failed. Please rerun the script."
    }

    return $subscriptions
}

function Login-Azure (
    [Parameter(Mandatory = $false)][bool]$SkipLogin
) {
    if ($SkipLogin) {
        Write-Verbose ("Skipping login as requested.")
        $context = Get-AzContext -ErrorAction SilentlyContinue

        if ($null -eq $context) {
            throw "Cannot skip login as you're not connected to Azure!"
        }
    }
    else {
        Write-Host -ForegroundColor Magenta "`r`nPlease specify your credntials to Az.`r`n"

        $cred = Get-Credential -ErrorAction SilentlyContinue

        if ($cred) {
            $login = Login-AzureSubscription -Credential $cred 
            Write-Verbose ("Login of Az completed, pending correct credentials.")
        }
        else {
            throw "No credentials provided!"
        }
    }
}

function Logout-Azure (
    [Parameter(Mandatory = $false)][bool]$SkipLogin
) {
    if ($SkipLogin) {
        Write-Verbose ("Skipping logout as requested.")
    }
    else {
        Remove-AzAccount | Out-Null
        Write-Verbose ("Logout of Az completed.")
    }
}

function New-AzureADGroup(
    [Parameter(Mandatory = $true)][string]$GroupName
) {
    Write-Verbose "Creating $groupName"
    $group = Get-AzADGroup -DisplayName $GroupName
    if ($null -eq $group) {
        $group = New-AzADGroup -DisplayName $GroupName -MailNickName $GroupName
    } 
    else {
        Write-Verbose "$groupName already exists. Skipping..."
    }
    return $group
}
function New-AzureADGroupRBAC(
    [Parameter(Mandatory = $true)][string]$GroupName,
    [Parameter(Mandatory = $true)][string]$ResourceId,
    [Parameter(Mandatory = $true)][string]$RoleName
) {
    $group = New-AzureADGroup -GroupName $GroupName
    $object = New-Object -TypeName psobject 
    Add-Member -InputObject $object –MemberType NoteProperty –Name "resourceId" –Value $resourceId
    Add-Member -InputObject $object –MemberType NoteProperty –Name "groupName" –Value $groupName
    Add-Member -InputObject $object –MemberType NoteProperty –Name "groupId" –Value $group.id
    Add-Member -InputObject $object –MemberType NoteProperty –Name "role" –Value $roleName

    return $object
}

function Set-AzureRBAC (
    [Parameter(Mandatory = $true)][array]$Assignments
) {
    foreach ($assignment in $assignments) {
        $existingAssignments = Get-AzRoleAssignment -ObjectId $assignment.groupId -Scope $assignment.resourceId
        if ($null -eq $existingAssignments) {
            New-AzRoleAssignment -ObjectId $assignment.groupId -RoleDefinitionName $assignment.role -Scope $assignment.resourceId | Out-Null
            Write-Host ("Assigment made for AzureAD\" + $assignment.groupName + ".")
        }
        else {
            Write-Host ("Assigment already exists for AzureAD\" + $assignment.groupName + ". Skipping...")
        }
    }
}

function New-AzureBudget {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline)][string] $amount,
        [Parameter(Mandatory = $true, ValueFromPipeline)][string] $budgetName,
        [Parameter(Mandatory = $false, ValueFromPipeline)][string] $resourceGroupName,
        [Parameter(Mandatory = $false, ValueFromPipeline)][string] $NotifyEmail,
        [Parameter(Mandatory = $true, ValueFromPipeline)][string] $UpperThreshold,
        [Parameter(Mandatory = $true, ValueFromPipeline)][string] $LowerThreshold
    )

    $DateTime = Get-FirstLastDayOfMonth
    $startofmonth = $DateTime[1].ToString("yyyy-MM-dd")

    New-AzConsumptionBudget `
        -Amount $amount `
        -Name $budgetName `
        -Category Cost `
        -StartDate $startofmonth `
        -TimeGrain Monthly `
        -ContactEmail $NotifyEmail `
        -NotificationKey 1 `
        -NotificationEnabled `
        -NotificationThreshold $LowerThreshold `
        -ErrorAction SilentlyContinue
    Set-AzConsumptionBudget `
        -Name $budgetName `
        -NotificationThreshold $UpperThreshold `
        -NotificationKey 2 `
        -ContactEmail $NotifyEmail `
        -ErrorAction SilentlyContinue
}
function Get-FirstLastDayOfMonth ( $aDate = $(get-date) ) {
    $aDateSet = @($aDate)
    $firstDay = Get-Date $aDate -day 1 -hour 0 -minute 0 -second 0
    $lastDay = (($firstDay).AddMonths(1).AddSeconds(-1))
    $aDateSet += $firstDay
    $aDateSet += $lastDay
    Return $aDateSet
}
function New-EASubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Specify The Product Name between 5 and 15 Chracters')][ValidateLength(5, 15)][string]$ProductName,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Specify The Asset Name')][string]$AssetName,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Enter the Environment the subscription is for eg pov, pit, prd or npe' )][ValidateSet("pov", "pit", "prd", "npe")][string]$Environment,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Specify The Offer type, can only be MS-AZR-0017P (Prod) or MS-AZR-0148P (Dev/Test' )][ValidateSet("MS-AZR-0017P", "MS-AZR-0148P")][string]$OfferType,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Enter the ObjectID of the Account that has permission to create Subscriptions' )][string]$EnrollmentAccountObjectId
    )

    $partnerID = 1158331
    
    #Create Subscription
    $subscription = New-AzSubscription -OfferType $OfferType -Name "$Assetname-$Environment-$ProductName" -EnrollmentAccountObjectId $EnrollmentAccountObjectId -ErrorVariable CreateError
    if ($CreateError) {
        Write-Host "Subscription could not be created, investigate the issue and retry"
        Break
    }

    if (-not $(Get-AzManagementPartner -PartnerId $partnerID)) {
        New-AzManagementPartner -PartnerId $partnerID
    } else {
        Write-Host "PartnerID already configured"
    }

    #Set the management group of the new subscription based on the environment
    New-AzManagementGroupSubscription -GroupName "$Environment-mg" -SubscriptionId $subscription.Id
}

function Set-SubscriptionRBAC {
    [CmdletBinding(DefaultParametersetName = 'None')]
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Specify The Product Name between 5 and 15 Chracters')][string] $ProductName,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Specify The Asset Name')][string] $AssetName,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Enter the Environment the subscription is for eg pov, pit, prd or npe' )][ValidateSet("pov", "pit", "prd", "npe")][string] $Environment,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Id of the subscription')][string] $subscriptionName
    )
    # Setup New Service Principal to be used by Azure DevOps, This automatically assigns the Contributor Role to the subscription selected (so no need to code for it), Note: SP Secrets must be completed later and added to DevOps
    #Known issue on running below using a SP: https://github.com/Azure/azure-powershell/issues/3215
    $currentAzureContext = Get-AzContext    
    $Subscription = Get-AzSubscription -SubscriptionName $subscriptionName
    $sp = New-AzADServicePrincipal -DisplayName ('Azure-' + $ProductName + '-' + $Environment + '-sp')    
    $tenantId = $currentAzureContext.Tenant.Id
    $accountId = $currentAzureContext.Account.Id	
    $ID = $Subscription.Id
    $SubResourceID = ('/subscriptions/' + $ID)
    # Create the Groups and assign RBAC
    $RBACRoles = $null
    $RBACRoles = @('Reader', 'Contributor', 'Owner')
    foreach ($RBACType in $RBACRoles) {
        #Create Group
        $AADdisplayName = $('Azure-' + $ProductName + '-' + $Environment + '-' + $RBACType)
        $GrpObjID = New-AzureADGroup ($AADdisplayName)
        $count = 0
        $success = $false
        do {
            try {
                New-AzRoleAssignment -ObjectId $GrpObjID.Id -Scope $SubResourceID -RoleDefinitionName $RBACType -ErrorAction Stop
                $success = $true
            }
            catch {
                Write-Host "Next attempt in 10 seconds to Wait for Azure to Create the Group" ('Azure-' + $ProductName + '-' + $RBACType)
                Start-sleep -Seconds 10
                # Put the start-sleep in the catch statement so we
                # don't sleep if the condition is true and waste time
            }
            $count++

        }until($count -eq 20 -or $success)
    }
}

function Get-ObjectMembers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key" }
    }
}
function New-AvDCStorageAccountTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)][string]$SubscriptionName,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)][string]$StorageAccount,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)][string]$ResourceGroup,
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)][string]$AzureLocation
    )
    # Create operations Resoruce Group and the Storage Account
    Write-Host ("`r`nCreating Pre-requisites: (Resource Group and Storage Account)") -ForegroundColor Yellow

    # Check if resource group exists
    $storageARG_Arm = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
    if (!$storageARG_Arm) {
        # Creates resource group if it doesn't exist.
        New-AzResourceGroup -Name $ResourceGroup -Tag @{Environment = ""; SecondaryOwner = "code"; Owner = "code"; DeploymentType = "Automated"; CostCentre = "code"; BusinessUnit = "code"; SolutionName = "" } -Location $AzureLocation -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep 3
        $storageARG_Arm = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
        Write-Host ("-- Finished creating resource group " + $ResourceGroup) -ForegroundColor Green
    }

    # Check if storage account exists
    $storageAccount_result = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount -ErrorAction SilentlyContinue
    if (!$storageAccount_result) {
        # Creates storage account if it doesn't exist.
        $storageAccount_result = New-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount -EnableHttpsTrafficOnly $true -Location $storageARG_Arm.Location -SkuName Standard_LRS -Kind StorageV2 -Tag @{storageType = "Standard_LRS"; version = "Version2" }
        Write-Host ("-- Finished creating storage account https://" + $StorageAccount + ".blob.core.windows.net") -ForegroundColor Green
        $storageAccount_result | Set-AzStorageAccount -EnableHttpsTrafficOnly $true | Out-Null
    }
    else {
        Write-Host ("-- The Storage Account " + $StorageAccount + " already exists.") -ForegroundColor Cyan
    }
    $Container = "code"
    $AzStrKey = Get-AzStorageAccountKey -Name $storageAccount_result.StorageAccountName -ResourceGroupName $storageAccount_result.ResourceGroupName
    $AzStrCtx = New-AzStorageContext -StorageAccountName $storageAccount_result.StorageAccountName -StorageAccountKey $AzStrKey[0].Value
    $StorageAccountContainer = Get-AzStorageContainer -Name $Container -Context $AzStrCtx.Context -ErrorAction SilentlyContinue

    if (-not($StorageAccountContainer)) {
        $StorageAccountContainer = New-AzStorageContainer -Context $AzStrCtx.Context -Name $Container -ErrorAction SilentlyContinue
        Write-Host ("-- Finished creating the " + $Container + " container in https://" + $StorageAccount + ".blob.core.windows.net") -ForegroundColor Green
    }
    else {
        Write-Host ("-- The container in " + $SubscriptionName + "/" + $StorageAccount + "/" + $Container + " already exists.") -ForegroundColor Cyan
    }

    $SASToken = New-AzStorageContainerSASToken -Container $StorageAccountContainer.Name -Context $AzStrCtx.Context -Permission r -ExpiryTime (Get-Date).AddDays(30)
    $SASTokenLong = New-AzStorageContainerSASToken -Container $StorageAccountContainer.Name -Context $AzStrCtx.Context -Permission r -ExpiryTime (Get-Date).AddYears(2)
    return $SASToken, $SASTokenLong, $Container, $AzStrCtx, $storageAccount_result.StorageAccountName
}
function InsightASCIIPrint {

    Write-Host "
    _  _     ___           _       _     _
  _| || |_  |_ _|_ __  ___(_) __ _| |__ | |_
 |_  ..  _|  | ||  _ \/ __| |/ _  |  _ \| __|
 |_      _|  | || | | \__ \ | (_| | | | | |_
   |_||_|   |___|_| |_|___/_|\__  |_| |_|\__|
                             |___/
" -ForegroundColor Magenta
}
function Format-Json([Parameter(Mandatory, ValueFromPipeline)][String] $json) {
    $indent = 0;
    ($json -Split '\n' |
        ForEach-Object {
            if ($_ -match '[\}\]]') {
                # This line contains  ] or }, decrement the indentation level
                $indent--
            }
            $line = (' ' * $indent * 2) + $_.TrimStart().Replace(':  ', ': ')
            if ($_ -match '[\{\[]') {
                # This line contains [ or {, increment the indentation level
                $indent++
            }
            $line
        }) -Join "`n"
}
function configure-Templates($allSubscriptions, $companyCode, $suffixFormat, $azureRegionCode, $templatesARM, $locationPrimary, $codePath, $networkIntegrated, $budgetData, $hubData, $locationSecondary) {
    foreach ($Sub in $allSubscriptions) {

        #Get the Subscription
        $subscriptionName = (Get-AzSubscription | Where-Object { $_.Id -eq $Sub.Value.id }).Name
        try {
            $companyCode = $companyCodeMaster
            $computedNumberCompanyCode = 0;

            Write-Host "`r`n======================================================" -ForegroundColor Magenta;
            Write-Host ("Azure Subscription: " + $subscriptionName) -ForegroundColor Magenta;
            Write-Host "======================================================" -ForegroundColor Magenta;
            
            $templatesARMToProvision = $templatesARM | Where-Object { $_.templateFullName }
            $spokeSubscriptionID = $Sub.value.id
            $SpokeSubscriptionCode = ($Sub.Value.subscriptionCode).ToLower();
            $NetworkInfo = $spokeSubscription.Values.Networks
            $SpokeNetworkInfo = $NetworkInfo;
            $prefix = ($companyCode + $delimiter + $azureRegionCode + $delimiter + $Sub.Value.subscriptionCode + $delimiter + "arg" + $delimiter).ToLower()
            $storageARG = ($companyCode + $delimiter + $azureRegionCode + $delimiter + $Sub.Value.subscriptionCode + $delimiter + "arg" + $delimiter + "operations").ToLower();
            do {
                try {
                    # The Azure Storage Account naming standard to be used.
                    $RandomDigit = Get-Random -Maximum 999 -Minimum 100
                    $storageAccountName = $companyCode.ToLower() + $azureRegionCode.ToLower() + $Sub.Value.subscriptionCode.ToLower() + "sta" + ($RandomDigit).ToString();
                    # Create Azure Storage Account tokens. If it doesnt create the storage account and resource group, then do the tokens.
                    $storageAccountInformation = New-AvDCStorageAccountTokens -SubscriptionName $subscriptionName -StorageAccount $storageAccountName -ResourceGroup $storageARG -AzureLocation $locationPrimary.azureRegion -ErrorAction Stop
                    $success = $true
                    if ($storageAccountInformation) {
                        $storageAccount = $true
                        $storageSasToken = $storageAccountInformation[0]
                        $storageSasToken_LongTerm = $storageAccountInformation[1]

                    }
                    else {
                        Write-Host "ERROR: The location code could not be determined for the storage account name. Does the environment hash table have the Azure region of the resource group?" -ForegroundColor Red
                    }
                    Write-Host "`r"
                }
                catch {
                    # Exception is stored in the automatic variable _
                    Write-Host "Next attempt will try and obtain a unique Storage Account across Azure."
                    Start-sleep -Seconds 2
                    # Put the start-sleep in the catch statement so we
                    # don't sleep if the condition is true and waste time
                }$count++

            } until($count -eq 20 -or $success)            

            Write-Host ("Creating parameter templates from the values in the master file:") -ForegroundColor Yellow
            $computedNumberCompanyCode = $RandomDigit = Get-Random -Maximum 999 -Minimum 100
            foreach ($template in $templatesARMToProvision) {
                $fileName = $template.templateName -replace "(\.((Spoke)(Template)|(Template)))", ("." + $sub.Key) -replace ".MultiRegion", "" -replace ".SingleRegion", ""
                Write-Verbose ("Creating " + $template.templateResource + "/" + $fileName)

                $newFilePath = $template.templateSave -replace "(\.((Spoke)(Template)|(Template)))", ("." + $sub.Key) -replace ".MultiRegion", "" -replace ".SingleRegion", ""
                $newFileContent = Get-Content $template.templateFullName

                # Apply values from the master.json file
                $newFileContent = $newFileContent -replace "<<COMPANY>>", $companyCode.ToLower();
                $newFileContent = $newFileContent -replace "<<SUBSCRIPTION>>", ($Sub.Value.subscriptionCode).ToLower();
                $newFileContent = $newFileContent -replace "<<DELIMITER>>", $delimiter
                $newFileContent = $newFileContent -replace "<<SUFFIX>>", $suffixFormat
                $newFileContent = $newFileContent -replace "<<SUBSCRIPTIONKEY>>", $Sub.Key
                $newFileContent = $newFileContent -replace "<<SUBSCRIPTIONID>>", $Sub.value.id
                $newFileContent = $newFileContent -replace "<<RANDOMGUID>>", [guid]::NewGuid();
                $newFileContent = $newFileContent -replace "<<BUILDTIME>>", $buildDateTime;
                $newFileContent = $newFileContent -replace "<<STORAGEACCOUNT>>", $storageAccountName;
                $newFileContent = $newFileContent -replace "<<SASTOKEN>>", $storageSasToken.ToString();
                $newFileContent = $newFileContent -replace "<<SASTOKEN-Long>>", $storageSasToken_LongTerm.ToString();
                $newFileContent = $newFileContent -replace "<<SPOKE-SUBSCRIPTION-LOWER>>", $SpokeSubscriptionCode.ToLower();
                $newFileContent = $newFileContent -replace "<<SPOKE-SUBSCRIPTIONID>>", $spokeSubscriptionID.ToLower();
                $newFileContent = $newFileContent -replace "<<ENVIRONMENT>>", $Sub.Value.environmentTag
                $newFileContent = $newFileContent -replace "<<COSTCENTRE>>", $costCentre;
                $newFileContent = $newFileContent -replace "<<DEPLOYMENTTYPE>>", $deploymentType;
                $newFileContent = $newFileContent -replace "<<BUSINESSUNIT>>", $businessUnit;
                $newFileContent = $newFileContent -replace "<<ARG-PREFIX>>", $prefix.ToLower();
                $newFileContent = $newFileContent -replace "<<OWNER>>", $owner;
                $newFileContent = $newFileContent -replace "<<SECONDARYOWNER>>", $SecondaryOwner;
                $newFileContent = $newFileContent -replace "<<3DIGITNUMBER>>", $computedNumberCompanyCode
                $newFileContent = $newFileContent -replace "<<LOCATIONCODE-PRIMARY>>", ($locationPrimary.locationCode).ToLower();
                $newFileContent = $newFileContent -replace "<<LOCATIONCODE-SECONDARY>>", ($locationSecondary.locationCode).ToLower();
                $newFileContent = $newFileContent -replace "<<LOCATION-PRIMARY>>", ($AllAzureLocations | Where-Object { $_.Location -eq $locationPrimary.azureRegion }).DisplayName
                $newFileContent = $newFileContent -replace "<<LOCATION-SECONDARY>>", ($AllAzureLocations | Where-Object { $_.Location -eq $locationSecondary.azureRegion }).DisplayName
                $newFileContent = $newFileContent -replace "<<LOCATION-PRIMARY-AZURE>>", $locationPrimary.azureRegion
                $newFileContent = $newFileContent -replace "<<LOCATION-SECONDARY-AZURE>>", $locationSecondary.azureRegion
                $newFileContent = $newFileContent -replace "<<PASSWORD>>", ("#(" + $companyCode + ")" + (([char[]]([char]48..[char]57) + [char[]]([char]65..[char]90) + ([char[]]([char]97..[char]122)) + 0..9 | Sort-Object { Get-Random })[0..15] -join '').ToString() + (Get-Date).AddYears([int](Get-Random -Minimum 1 -Maximum 9)).ToString("yyyy") + "#")
                $SpokePrimaryVNetNameSpokeTrim = $SpokeNetworkInfo.Primary.addressSpace -Replace ".{3}$";
                $SpokeSecondaryVNetNameSpokeTrim = $SpokeNetworkInfo.Secondary.addressSpace -Replace ".{3}$";

                if ($networkIntegrated -eq $false) {
                    $newFileContent = $newFileContent -replace "<<CREATEPEERS>>", "false";
                }
                else {
                    $newFileContent = $newFileContent -replace "<<CREATEPEERS>>", "true";
                }
                #HubData
                $newFileContent = $newFileContent -replace "<<ASC-EMAIL>>", $hubData.azureSecurityCenterEmail;
                $newFileContent = $newFileContent -replace "<<ASC-PHONE>>", $hubData.azureSecurityCentrePhone;
                $newFileContent = $newFileContent -replace "<<ASC-TIER>>", $hubData.azureSecurityCentreTier; 
                $newFileContent = $newFileContent -replace "<<HUB-OMS-WORKSPACE>>", $hubData.logAnalyticsWorkspaceName;
                $newFileContent = $newFileContent -replace "<<HUB-ARG-OMS>>", $hubData.logAnalyticsResourceGroup;
                $newFileContent = $newFileContent -replace "<<HUB-SUBSCRIPTION-ID>>", $hubData.subscriptionId;

                # For different kinds of ARM templates, determined by splitting the fileName before first full stop.
                switch ($fileName.Split(".")[0]) {
                    { ($_ -eq "networking") } {
                        if ($networkIntegrated -eq $false) {
                            #Generic CIDR ranges
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-vNET-NAME>>", "172.31.0.0"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-vNET>>", "172.31.0.0/17"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET1-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet1;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET1>>", "172.31.0.0/24"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET2-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet2;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET2>>", "172.31.1.0/24"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET3-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet3;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET3>>", "172.31.2.0/24"
            
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-vNET-NAME>>", "172.31.128.0"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-vNET>>", "172.31.128.0/17"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET1-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet1;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET1>>", "172.31.128.0/24"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET2-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet2;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET2>>", "172.31.129.0/24"
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET3-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet3;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET3>>", "172.31.130.0/24"
                           
                            $newFileContent = $newFileContent -replace "<<HUB-NETWORK-ARG>>", $null;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-vNET-NAME>>", $null;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-vNET-NAME>>", $null;
                            $newFileContent = $newFileContent -replace "<<NETWORK-INTEGRATED>>", $false;
                        }
                        else {
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-vNET-NAME>>", $SpokePrimaryVNetNameSpokeTrim;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-vNET>>", $SpokeNetworkInfo.Primary.addressSpace;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET1-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet1;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET1>>", $SpokeNetworkInfo.Primary.subnets.Subnet1CIDR;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET2-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet2;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET2>>", $SpokeNetworkInfo.Primary.subnets.Subnet2CIDR;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET3-NAME>>", $SpokeNetworkInfo.Primary.subnets.Subnet3;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-PRIMARY-SUBNET3>>", $SpokeNetworkInfo.Primary.subnets.Subnet3CIDR;


                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-vNET-NAME>>", $SpokeSecondaryVNetNameSpokeTrim;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-vNET>>", $SpokeNetworkInfo.Secondary.addressSpace;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET1-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet1;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET1>>", $SpokeNetworkInfo.Secondary.subnets.Subnet1CIDR;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET2-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet2;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET2>>", $SpokeNetworkInfo.Secondary.subnets.Subnet2CIDR;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET3-NAME>>", $SpokeNetworkInfo.Secondary.subnets.Subnet3;
                            $newFileContent = $newFileContent -replace "<<SPOKE-NETWORK-SECONDARY-SUBNET3>>", $SpokeNetworkInfo.Secondary.subnets.Subnet3CIDR;
                            
                            $newFileContent = $newFileContent -replace "<<HUB-NETWORK-ARG>>", $hubData.virtualNetworkResourceGroup;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-vNET-NAME>>", $hubData.primaryVirtualNetwork;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-1>>", $hubData.primaryDNS1;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-2>>", $hubData.primaryDNS2;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-3>>", $hubData.primaryDNS3;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-4>>", $hubData.primaryDNS4;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-5>>", $hubData.primaryDNS5;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-6>>", $hubData.primaryDNS6;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-7>>", $hubData.primaryDNS7;
                            $newFileContent = $newFileContent -replace "<<HUB-PRIMARY-DNS-8>>", $hubData.primaryDNS8;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-vNET-NAME>>", $hubData.secondaryVirtualNetwork;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-1>>", $hubData.secondaryDNS1;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-2>>", $hubData.secondaryDNS2;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-3>>", $hubData.secondaryDNS3;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-4>>", $hubData.secondaryDNS4;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-5>>", $hubData.secondaryDNS5;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-6>>", $hubData.secondaryDNS6;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-7>>", $hubData.secondaryDNS7;
                            $newFileContent = $newFileContent -replace "<<HUB-SECONDARY-DNS-8>>", $hubData.secondaryDNS8;
                            $newFileContent = $newFileContent -replace "<<NETWORK-INTEGRATED>>", $true;
                        }
                    }
                }

                Set-Content -Path $newFilePath -Value $newFileContent -Force
                Write-Host ("-- Finished creating template: code/arm/" + $fileName) -ForegroundColor Green
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error $ErrorMessage
            throw "Something has gone wrong."
        }

        if ($storageAccount) {
            Write-Host "`r`nUploading ARM templates to storage account:" -ForegroundColor Yellow

            # Upload to storage
            try {
                $files = Get-ChildItem $CodePath -File -Recurse
                $CodePathRemove = $CodePath
                foreach ($file in $files) {
                    $fileLocation = $file.FullName.Replace($CodePathRemove, "")
                    Set-AzStorageBlobContent -File $file.FullName -Blob $fileLocation -Container $storageAccountInformation[2] -Context $storageAccountInformation[3] -Force | Out-Null
                }
                Write-Host ("-- Finished uploading templates to https://" + $storageAccountInformation[4] + ".blob.core.windows.net/" + $Container + "`r`n") -ForegroundColor Green
            }
            catch {
                throw "Something has gone wrong with uploading the templates."
            }
        }
    }

    $AvDCTemplateFile = $CodePath + "\arm\AppLandingZone.json"
    $AvDCParametersFolder = $CodePath + "\arm\parameters\"
    Run-Deployment -allSubscriptions $allSubscriptions `
        -AvDCTemplateFile $AvDCTemplateFile `
        -AvDCParametersFolder $AvDCParametersFolder `
        -SkipLogin `
        -budgetData $budgetData	`
        -networkIntegrated $networkIntegrated `
        -hubData $hubData `
        -locationPrimary $locationPrimary `
        -locationSecondary $locationSecondary `
        -prefix $prefix `
        -OutputDeployment
}
function Prepare-Templates($TemplateFilesAll, $CodePath, $networkIntegrated, $budgetData, $hubData, $locationPrimary, $locationSecondary, $ToCopytoCodePath) {
    $templatesARM = @();    
    foreach ($template in $TemplateFilesAll) {
        #Create psObject to create ARM templates.
        $savePath = $template.FullName.Replace($TemplatePath, $CodePath)
        $rootPath = Split-Path  $template.FullName -Parent
        $rootName = $rootPath.Split("\")[$rootPath.Split("\").Count - 2]

        $object = New-Object -TypeName psobject
        Add-Member -InputObject $object -MemberType NoteProperty -Name "templateFor" -Value $template.Name.Split(".")[0]
        Add-Member -InputObject $object -MemberType NoteProperty -Name "templateResource" -Value $rootName
        Add-Member -InputObject $object -MemberType NoteProperty -Name "templateName" -Value $template.Name
        Add-Member -InputObject $object -MemberType NoteProperty -Name "templateFullName" -Value $template.FullName
        Add-Member -InputObject $object -MemberType NoteProperty -Name "templateSave" -Value $savePath
		
        if ($template.FullName -like "*.json") {
            $templatesARM += $object
        }
    }
    # Remove old items so the code is repeatable
    Get-ChildItem -Recurse -Path $CodePath | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
    foreach ($item in $ToCopytoCodePath) {
        if ($item.Directory) {
            New-Item -itemtype Directory -Path ($item.Directory).FullName.Replace($TemplatePath, $CodePath) -Force | Out-Null
        }
        Copy-Item $item.FullName $item.FullName.Replace($TemplatePath, $CodePath) -Force -ErrorAction SilentlyContinue | Out-Null
    }

    configure-Templates -allSubscriptions $allSubscriptions `
        -companyCode $companyCode `
        -suffixFormat $suffixFormat `
        -azureRegionCode $azureRegionCode `
        -templatesARM $templatesARM `
        -locationPrimary $locationPrimary `
        -codePath $CodePath `
        -networkIntegrated $networkIntegrated `
        -budgetData $budgetData `
        -hubData $hubData `
        -locationSecondary $locationSecondary
}
function Get-MasterConfig {
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory = $true)] [string] $MasterFile,
        [Parameter(Mandatory = $true)] [string] $TemplatePath,
        [Parameter(Mandatory = $true)] [string] $CodePath        
    )
    #Module-Checker
    #InsightASCIIPrint	
    Write-Host "Running the deployment process for the Application Landing Zone...`r`n" -ForegroundColor Blue

    #Get the contents of the master file
    $master = Get-Content $MasterFile -Raw | ConvertFrom-Json | Get-ObjectMembers
    $spokeSubscription = $master | Where-Object { $_.Key -eq "spokeSubscription" } | Select-Object -ExpandProperty Value
    $spokeSubscription = @{Key = "Spoke"; Value = $spokeSubscription }
    $allSubscriptions = $spokeSubscription
    $allSubscriptions = $allSubscriptions | ConvertTo-Json | ConvertFrom-Json | Sort-Object Key

    #Values from master.json
    $companyCodeMaster = $master | Where-Object { $_.Key -eq "companyCode" } | Select-Object -ExpandProperty Value
    $azureRegionCode = $master | Where-Object { $_.Key -eq "azureRegionCode" } | Select-Object -ExpandProperty Value
    $delimiter = $master | Where-Object { $_.Key -eq "delimiter" } | Select-Object -ExpandProperty Value;
    $suffixFormat = $master | Where-Object { $_.Key -eq "suffixFormat" } | Select-Object -ExpandProperty Value;
    $LocationsList = $master | Where-Object { $_.Key -eq "locations" } | Select-Object -ExpandProperty Value | Get-ObjectMembers
    $networkIntegrated = $master | Where-Object { $_.Key -eq "networkIntegrated" } | Select-Object -ExpandProperty Value

    #Budget Data
    $budgetData = $master | Where-Object { $_.Key -eq "budget" } | Select-Object -ExpandProperty Value

    #Hub details
    $hubData = $master | Where-Object { $_.Key -eq "hubData" } | Select-Object -ExpandProperty Value


    # Tags from master.json
    $tags = $master | Where-Object { $_.Key -eq "tags" } | Select-Object -ExpandProperty Value;
    $costCentre = $tags.costCentre
    $owner = $tags.owner
    $SecondaryOwner = $tags.secondaryOwner
    $deploymentType = $tags.deploymentType
    $businessUnit = $tags.businessUnit
	
    Select-AzSubscription -Subscription $spokeSubscription.value.id | Out-Null	

    #Used for unique deployments
    $buildDateTime = Get-Date -Format "yyyyMMddhhmmss"
    $AllAzureLocations = Get-AzLocation
    $storageAccountName = "<<STORAGEACCOUNT>>"
    $storageSasToken = "<<SASTOKEN>>"
    $storageSasToken_LongTerm = "<<SASTOKEN>>"
    $storageAccount = $null;

    # Get ARM Templates
    $CodePath = Get-Item $CodePath
    $TemplatePath = Get-Item $TemplatePath
    $templatesARM = @();    
    $TemplateFilesAll = Get-ChildItem -Recurse -Path $TemplatePath

    #Define the code folder
    if (!$CodePath.ToString().EndsWith("\")) {
        $CodePath = $CodePath + "\"
    }

    #Define the Primary and Secondary locations
    $locationPrimary = $LocationsList | Where-Object { $_.Key -eq "Primary" } | Select-Object -ExpandProperty Value

    if (($LocationsList | Measure-Object).count -eq 2) {
        $locationSecondary = $LocationsList | Where-Object { $_.Key -eq "Secondary" } | Select-Object -ExpandProperty Value
        $RegionMulti = $true;
        $TemplateFilesAll = $TemplateFilesAll | Where-Object { $_.Name -match ".Template." -and $_.Name -notmatch '.SingleRegion.' }
        $ToCopytoCodePath = Get-ChildItem -Recurse -Path $TemplatePath | Where-Object { $_.Name -notmatch ".Template." -and $_.Name -notmatch '.SingleRegion.' }
    }
    else {
        $locationSecondary = $LocationsList | Where-Object { $_.Key -eq "Primary" } | Select-Object -ExpandProperty Value
        $RegionMulti = $false;
        $TemplateFilesAll = $TemplateFilesAll | Where-Object { $_.Name -match ".Template." -and $_.Name -notmatch '.MultiRegion.' }
        $ToCopytoCodePath = Get-ChildItem -Recurse -Path $TemplatePath | Where-Object { $_.Name -notmatch ".Template." -and $_.Name -notmatch '.MultiRegion.' }

    }
    # Display Write host for overview of all tasks.
    Write-Host "Overview of all Tasks:" -ForegroundColor Yellow
    Write-Host "-- Application Landing Zone templates will be created based off the master file." -ForegroundColor White
    Write-Host "-- A storage account will be created to host these templates." -ForegroundColor White
    Write-Host "-- Templates will be uploaded into a container within this Storage Account." -ForegroundColor White
    Write-Host "-- All templates will be validated & tested prior to deployment." -ForegroundColor White
    Write-Host "-- All templates will be deployed to create the Application Landing Zone." -ForegroundColor White

    # If deploying paired regions.
    if ($RegionMulti) {
        Write-Host "-- The proposed deployment approach will use Azure paired regions." -ForegroundColor White
        Write-Host "-- The Primary Azure Region will be the" $locationPrimary.azureRegion "Azure region." -ForegroundColor White
        Write-Host "-- The Secondary Azure Region will be the" $locationSecondary.azureRegion "Azure region." -ForegroundColor White
    }
    # Otherwise it is a single region.
    else {
        Write-Host "-- The proposed deployment approach will use a single Azure region." -ForegroundColor White
        Write-Host "-- The single Azure Region will be the" $locationPrimary.azureRegion "Azure region." -ForegroundColor White
    }
    #Prepare ARM templates
    Prepare-Templates -TemplateFilesAll $TemplateFilesAll `
        -CodePath $CodePath `
        -networkIntegrated $networkIntegrated  `
        -budgetData $budgetData `
        -hubData $hubData `
        -locationPrimary $locationPrimary `
        -locationSecondary $locationSecondary `
        -ToCopytoCodePath $ToCopytoCodePath

}
function RegisterProvider($ProviderNamespace) {

    $providerCheck = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace | Where-Object { $_.RegistrationState -ne "Registered" }

    if ($providerCheck) {
        $sleepDuration = 10
        
        Register-AzResourceProvider -ProviderNamespace $ProviderNamespace | Out-Null
        Start-Sleep $sleepDuration # wait for 10 seconds befor retrying 
        
        do {
            $RegistrationState = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace | Where-Object { $_.RegistrationState -eq "Registering" }
            if ($null -eq $RegistrationState) {
                Write-Host "Completed registering $ProviderNamespace provider"
            } else {
                Write-Host "Waiting for registring $ProviderNamespace provider.Retrying in $sleepDuration seconds"
                Start-Sleep $sleepDuration
            }
        } until ($null -eq $RegistrationState) # Retry until there is no 'Registering' state and the provider is completely 'Registered'
    } else {
        Write-Host "$ProviderNamespace provider already registered. Skipping"
    }

    
}

function Run-Deployment ($allSubscriptions, $AvDCTemplateFile, $AvDCParametersFolder, $budgetData, $networkIntegrated, $hubData, $locationPrimary, $locationSecondary, $prefix) {

    # Get the Template and Parameter files
    $AvDCTemplateFile = Get-Item $AvDCTemplateFile
    $ParameterFiles = Get-ChildItem $AvDCParametersFolder

    # Validate the deployment
    Write-Host "Validating Deployment:" -ForegroundColor Yellow

    $subscriptionName = ($subscription | Where-Object { $_.Id -eq $Sub.Value.id }).Name
    Select-AzSubscription -Subscription $Sub.Value.id | Out-Null

    # Stop the automatic creation of Network watcher objects
    $NWcheck = Get-AzProviderFeature -ProviderNamespace Microsoft.Network -FeatureName DisableNetworkWatcherAutocreation | Where-Object { $_.RegistrationState -ne "Registered" }
    if ($NWcheck) {
        Register-AzProviderFeature -FeatureName DisableNetworkWatcherAutocreation -ProviderNamespace Microsoft.Network
        Register-AzResourceProvider -ProviderNamespace Microsoft.Network
    }
	
    #Register the resource providers that are required if they are not already - this is different to the network watcher as these have no specific features. 	
    RegisterProvider -ProviderNamespace Microsoft.Security
    RegisterProvider -ProviderNamespace Microsoft.Insights
    RegisterProvider -ProviderNamespace Microsoft.Storage

    # Get the template parameter files
    $ParameterFile = $ParameterFiles | Where-Object { $_.FullName -match $sub.Key }

    # Do a test deployment to make sure everything is correct.
    $testARM = Test-AzDeployment -Location $locationPrimary.AzureRegion -TemplateFile $AvDCTemplateFile -TemplateParameterFile $ParameterFile.FullName

    if ($testARM) {
        Write-Host "Template errors have been detected." -ForegroundColor Red
        $testARM | Select-Object -ExpandProperty Details -ExpandProperty Message

        Write-Host "Please remediate errors before trying again." -ForegroundColor Red
        throw "FATAL ERROR: Script has to exit. Issue found with templates and cannot proceed until fixed."
    }
    else {
        Write-Host "-- Finished validating & testing deployment, proceed with the actual deployment.`r`n" -ForegroundColor Green
    }

    #Now do the deployment
    Write-Host "Starting Deployment:" -ForegroundColor Yellow

    try {
        $subscription = Get-AzSubscription
        $subscriptionName = ($subscription | Where-Object { $_.Id -eq $Sub.Value.id }).Name
        $tenantdomain = ($subscription | Select-Object -First 1 -ExpandProperty ExtendedProperties).Account.Split("@")[1]
        $ParameterFile = $ParameterFiles | Where-Object { $_.FullName -match $sub.Key }

        # Do the actual deployment
        if ($OutputDeployment) {
            # Verbose output.
            Write-Host ("-- Please monitor the full deployment within the Azure Portal: https://portal.azure.com/#@" + $tenantdomain + "/resource/subscriptions/" + $Sub.Value.Id + "/subdeployments`r") -ForegroundColor Cyan
            New-AzSubscriptionDeployment -Name ("ApplicationLandingZone" + $Sub.Key + "-" + (Get-Date -Format "yyyyMMddhhmmss")) -Location $locationPrimary.AzureRegion -TemplateFile $AvDCTemplateFile -TemplateParameterFile $ParameterFile.FullName -Verbose -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            # Clean output.
            Write-Host ("-- Please monitor the full deployment within the Azure Portal: https://portal.azure.com/#@" + $tenantdomain + "/resource/subscriptions/" + $Sub.Value.Id + "/subdeployments`r") -ForegroundColor Cyan
            New-AzSubscriptionDeployment -Name ("ApplicationLandingZone" + $Sub.Key + "-" + (Get-Date -Format "yyyyMMddhhmmss")) -Location $locationPrimary.AzureRegion -TemplateFile $AvDCTemplateFile -TemplateParameterFile $ParameterFile.FullName -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Error $ErrorMessage
        throw "Something has gone wrong. Please contact Insight for script debugging assistance."
    }
    # If VNET peering is required configure this.
    if ($networkIntegrated -eq $true) {
        $spokeNetworkRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName.ToLower() -eq $prefix + "network" }
        $spokePrimaryVnet = Get-AzVirtualNetwork | Where-Object { $_.ResourceGroupName.ToLower() -eq $spokeNetworkRG.ResourceGroupName -and $_.Location -eq $locationPrimary.AzureRegion }
        Create-AzureNetworkPeering -Vnet1 $spokePrimaryVnet.Name -Vnet1ResourceGroup $spokeNetworkRG.ResourceGroupName -Vnet1SubscriptionId $Sub.Value.id -Vnet2 $hubData.primaryVirtualNetwork -Vnet2ResourceGroup $hubData.virtualNetworkResourceGroup -Vnet2SubscriptionId $hubData.subscriptionId

        if ($locationPrimary.AzureRegion -ne $locationSecondary.AzureRegion) { # if only one region is specified, do not create the secondary peering
            $spokeSecondaryVnet = Get-AzVirtualNetwork | Where-Object { $_.ResourceGroupName.ToLower() -eq $spokeNetworkRG.ResourceGroupName -and $_.Location -eq $locationSecondary.AzureRegion }
            Create-AzureNetworkPeering -Vnet1 $spokeSecondaryVnet.Name -Vnet1ResourceGroup $spokeNetworkRG.ResourceGroupName -Vnet1SubscriptionId $Sub.Value.id -Vnet2 $hubData.secondaryVirtualNetwork -Vnet2ResourceGroup $hubData.virtualNetworkResourceGroup -Vnet2SubscriptionId $hubData.subscriptionId
        }
    }

    #Now the deployment is done do the post ARM configs
    #budgets	# there is an ErrorAction Silently..., which is not good, but consuption API only available on EA subscriptions
    New-AzureBudget -budgetName ($SubscriptionName + '-Budget') `
        -NotifyEmail $budgetData.notifyEmail `
        -amount $budgetData.amount `
        -UpperThreshold $budgetData.upperThreshold `
        -LowerThreshold $budgetData.lowerThreshold | Out-Null

    # Finalise Deployment.
    Write-Host "`r`nFinalising Deployment:" -ForegroundColor Yellow
    Write-Host "-- Deployment of the Application Landing Zone in" $locationPrimary.azureRegion "&" $locationSecondary.azureRegion "has been completed.`r`n" -ForegroundColor Green
}
function Create-AzureNetworkPeering {
    Param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Vnet1 name")]
        $Vnet1,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Resource group name for vnet1")]
        $Vnet1ResourceGroup,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Subscription for vnet1")]
        $Vnet1SubscriptionId,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Vnet2 name")]
        $Vnet2,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Resource group name for vnet2")]
        $Vnet2ResourceGroup,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Subscription for vnet1")]
        $Vnet2SubscriptionId
    )

    Select-AzSubscription -Subscription $Vnet1SubscriptionId | Out-Null
    $VirtualNetwork1 = Get-AzVirtualNetwork -Name $Vnet1 -ResourceGroupName $Vnet1ResourceGroup
    $peer1 = Get-AzVirtualNetworkPeering -Name $vnet1-$vnet2 -VirtualNetwork $VirtualNetwork1.Name -ResourceGroupName $Vnet1ResourceGroup -ErrorAction SilentlyContinue

    Select-AzSubscription -Subscription $Vnet2SubscriptionId | Out-Null
    $VirtualNetwork2 = Get-AzVirtualNetwork -Name $Vnet2 -ResourceGroupName $Vnet2ResourceGroup
    $peer2 = Get-AzVirtualNetworkPeering -Name $vnet2-$vnet1 -VirtualNetwork $VirtualNetwork2.Name -ResourceGroupName $Vnet2ResourceGroup -ErrorAction SilentlyContinue

    Select-AzSubscription -Subscription $Vnet1SubscriptionId | Out-Null
    if ($null -eq $peer1) {
        Add-AzVirtualNetworkPeering -Name $vnet1-$vnet2 -VirtualNetwork $VirtualNetwork1 -RemoteVirtualNetworkId $VirtualNetwork2.Id -AllowForwardedTraffic -UseRemoteGateways | Out-Null
        $PeeringStateVNET1 = (Get-AzVirtualNetworkPeering -ResourceGroupName $Vnet1ResourceGroup -VirtualNetworkName $Vnet1 | Select-Object PeeringState).PeeringState
        Write-Host "Peering status for $VNET1 is $PeeringStateVNET1"
    }

    Select-AzSubscription -Subscription $Vnet2SubscriptionId | Out-Null
    if ($null -eq $peer2) {
        #THis is the core
        Add-AzVirtualNetworkPeering -Name $vnet2-$vnet1 -VirtualNetwork $VirtualNetwork2 -RemoteVirtualNetworkId $VirtualNetwork1.Id -AllowForwardedTraffic -AllowGatewayTransit | Out-Null
        $PeeringStateVNET2 = (Get-AzVirtualNetworkPeering -ResourceGroupName $Vnet2ResourceGroup -VirtualNetworkName $Vnet2 | Select-Object PeeringState).PeeringState
        Write-Host "Peering status for $VNET2 is $PeeringStateVNET2"
    }
    #Go back to spoke
    Select-AzSubscription -Subscription $Vnet1SubscriptionId | Out-Null
}
function Deploy-AppLandingZone($MasterFile, $TemplatePath, $CodePath, $SkipLogin) {
    $login = Login-Azure $SkipLogin
    Get-MasterConfig -MasterFile $MasterFile -TemplatePath $TemplatePath -CodePath $CodePath
}
