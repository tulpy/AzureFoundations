
function ConvertTo-HashTable {
    param (
        [Parameter(Mandatory, ValueFromPipeline)] [PSCustomObject] $Object
    )

    $HasbTable = [ordered] @{}

    $Object.psobject.Properties | ForEach-Object { $HasbTable[$_.Name] = $_.Value }
    $HasbTable
}

function Set-cAzSubscriptionRBACPermissions {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory)]$rbacAccessObj,
        [Parameter(Mandatory)]$ProductAndEnvironmentName,
        [Parameter(Mandatory)]$SubscriptionID,
        [Parameter()][Switch]$SkipServicePrincipal
    )

    # Create the SP only if SkipServicePrincipal is not provided
    if (-not $SkipServicePrincipal) {
        # Setup New Service Principal to be used by Azure DevOps, this automatically assigns the Contributor Role to the subscription selected (so no need to code for it), 
        # Note: SP Secrets must be completed later and added to DevOps

        $spName = "Azure-$ProductAndEnvironmentName-sp".ToLower()
        $servicePrincipal = Get-AzADServicePrincipal -DisplayName $spName
        # Create the service principal only if it doesnt exists
        If ($null -eq $servicePrincipal) {
            $servicePrincipal = New-AzADServicePrincipal -DisplayName $spName    
            Write-Host "`nCreated '$spName' Service Principal"

            # Set secret for the service principal. Run this only if the sp is was not created above
            Add-Type -AssemblyName System.Web
            $passwordString =  $([System.Web.Security.Membership]::GeneratePassword(32, 5)) # Generate 32 characters random complex password
            $passwordString  | Out-File "$PSScriptRoot\$spName.txt"
            #Write-Host $passwordString

            $appObject = Get-AzADApplication -ApplicationId $servicePrincipal.ApplicationId # Get the application object
            Remove-AzADAppCredential -ApplicationObject $appObject -Force # remove the existing secret created during the creation of the service principal

            # Create a new secret for the service principal
            New-AzADAppCredential -ApplicationObject $appObject -Password (ConvertTo-SecureString $passwordString -AsPlainText -Force) -StartDate $(Get-Date) -EndDate $((Get-Date).AddYears(1)) | Out-Null
        } else {
            Write-Host "`'$spName' Service Principal already exists. Skipping"
        }
    } else {
        Write-Host "`n-SkipServicePrincipal' switch proivded."
    }
    
    $rbacRoles = ($rbacAccessObj | Get-Member | Where-Object {$_.MemberType -eq 'NoteProperty'}).Name

    foreach ($rbacRole in $rbacRoles) {
        
        $aadGroupName  = "Azure-$ProductAndEnvironmentName-$rbacRole".ToLower()
        $azureADGroup = Get-AzADGroup -DisplayName $aadGroupName
        
        # Create the group if it doesnt exist
        if ($null -eq $azureADGroup) {
            $azureADGroup = New-AzADGroup -DisplayName $aadGroupName -MailNickName $aadGroupName
            Write-Host "`nCreated '$aadGroupName' group"
        } else {
            Write-Host "`n'$aadGroupName' group already exists. Skipping"
        }
        
        # assing rbac permissions to the group
        $azureADRoleAssginment = Get-AzRoleAssignment -ObjectId $azureADGroup.Id -RoleDefinitionName $rbacRole -Scope "/subscriptions/$SubscriptionID"
                
        If ($null -eq $azureADRoleAssginment) {
            $retryCount = 10
            $count = 0
            $success = $false
            do {
                try {
                    New-AzRoleAssignment -ObjectId $azureADGroup.Id -RoleDefinitionName $rbacRole -Scope "/subscriptions/$SubscriptionID" -ErrorAction Stop | Out-Null
                    Write-Host "Created '$rbacRole' role assginment for subscription id $SubscriptionID"
                    $success = $true
                }
                catch {
                    Write-host "Couldnt create the role assignment. Retrying in 10 seconds. Failed due to: $_"
                    Start-sleep -Seconds 10 # sleep for 10 seconds in case of a failure
                }
                $count++
    
            } until($count -eq $retryCount -or $success)
        } else {
            Write-Host "'$($azureADGroup.DisplayName)' role assginment for subscription id $SubscriptionID already exists. Skipping"
        }

        # add Azure AD user to a group
        If ( $rbacAccessObj.$rbacRole) {
            $users =   $rbacAccessObj.$rbacRole -split ";" # splitting the user list using ;get-az

            foreach ($user in $users) {
                $user = $user.trim()
                $azureADUser = Get-AzADUser -UserPrincipalName $user 
                
                #If user is found in Azure AD add to the group
                If ($azureADUser) {
                    try {
                        $groupMember = Get-AzADGroupMember -GroupDisplayName $aadGroupName | Where-Object {$_.UserPrincipalName -eq $user}
                        
                        If ($groupMember) {
                            Write-Host "'$user' already member '$aadGroupName'"
                        } else { # the user is not present in the group
                            Add-AzADGroupMember -MemberUserPrincipalName $user -TargetGroupDisplayName $aadGroupName -ErrorAction Stop
                            Write-Host "Added '$user' to '$aadGroupName'"
                        }
                    } catch {
                        Write-Host "Could not add '$user' to '$aadGroupName' due to $_ "
                    }
                } else {
                    Write-Host "Could not find '$user'"
                } 
            }
        } else {
            Write-Host "No users defined for '$rbacRole' role, skipping" 
        }
    }
}

function New-cAzADServicePrincipalSecret {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)] $ServicePrincipalName
    )

    Add-Type -AssemblyName System.Web
    $passwordString =  $([System.Web.Security.Membership]::GeneratePassword(32, 5)) # Generate 32 characters random complex password

    $appObject = Get-AzADApplication -DisplayName $ServicePrincipalName -ErrorAction SilentlyContinue

    if ($null -eq $appObject) {
        throw "Could not find the Service Princiapl $ServicePrincipalName due"
    } elseif ($appObject.Count -gt 1) {
        throw "More than one Service Principal with the same name has been found, quitting"
    } 

    New-AzADAppCredential -ApplicationObject $appObject -Password (ConvertTo-SecureString $passwordString -AsPlainText -Force) -StartDate $(Get-Date) -EndDate $((Get-Date).AddYears(1)) | Out-Null
    $passwordString
}

function New-cAzBudget {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string] $SubscriptionID,
        [Parameter(Mandatory)][string] $Amount,
        [Parameter(Mandatory)][string] $BudgetName,
        [Parameter()][string] $NotifyEmail,
        [Parameter(Mandatory)][string] $UpperThreshold,
        [Parameter(Mandatory, ValueFromPipeline)][string] $LowerThreshold
    )

    if (-not $(Get-AzContext | Where-Object {$_.Subscription -like $SubscriptionID})) {
        Set-AzContext -Subscription $SubscriptionID | Out-Null
    }

    if (-not  $(Get-AzConsumptionBudget -Name $BudgetName)) {
        try {
            New-AzConsumptionBudget -Amount $Amount -Name $BudgetName -Category Cost -TimeGrain Monthly -NotificationEnabled -ContactEmail $NotifyEmail `
                -NotificationKey 1 -NotificationThreshold $LowerThreshold -StartDate $(Get-Date $(Get-Date) -Day 1).ToString("yyyy-MM-dd") #first day of the month
            Set-AzConsumptionBudget -Name $BudgetName -NotificationThreshold $UpperThreshold -NotificationKey 2 -ContactEmail $NotifyEmail 
            Write-Host "Successfully created budget '$BudgetName'"
        } catch {
            Write-Host "Failed to create the budget '$BudgetName' due to $_"
        }
    } else {
        Write-Host "Budget '$BudgetName' already exists"
    }
}

function Remove-cAzAppLandingZoneComponents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()] $SubscriptionID,
        [Parameter(ParameterSetName='Individual')][switch] $RemoveNetworkPeering,
        [Parameter(ParameterSetName='Individual')][switch] $RemoveBudget,
        [Parameter(ParameterSetName='Individual')][switch] $RemoveServicePrincipal,
        [Parameter(ParameterSetName='All')][switch] $RemoveAll
    )
    
    Write-Host @"
    The script will remove the below:
        - Resource groups and its member resources
        - Service principal and its associated application
        - Budget data
        - Role assignments
        - vNet peering
"@
    $Prompt = Read-Host -Prompt 'Are you sure you want to proceed with the removal? Type "Y" to proceed else will exit the script'

    If ($Prompt -ne 'Y') {
        Write-Host "Exiting the script"
        Exit
    } else {
        write-host "Proceeding to the remove the compponents"
    }

    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue

    if(-not $subscription) {
        throw "Subscription with id '$SubscriptionId' not found, quitting"
    }
    
    try {
        if (-not $(Get-AzContext | Where-Object {$_.Subscription -like $subscription.id})) {
            Set-AzContext -Subscription $subscription.id -ErrorAction Stop | Out-Null
            Write-Host "Successfully set the context to '$($subscription.Name)'"
        }
    } catch {
        throw $_
    }

    # Remove network peering - DO NOT CHANGE THE ORDER OF THIS BLOCK 
    if ($RemoveNetworkPeering -or $RemoveAll) {
        # Create a custom object only with required fields. This code must before changing the context to the shared subscription
        $peers = @()

        Foreach ($vNet in $(Get-AzVirtualNetwork)) {
            $peers += [PSCustomObject] @{
                SourceVirtualNetworkName = $vNet.Name
                RemoteResourceGroupName = ($vNet.VirtualNetworkPeerings.RemoteVirtualNetwork.Id -split "/")[4]
                RemoteVirtualNetworkName = ($vNet.VirtualNetworkPeerings.RemoteVirtualNetwork.Id -split "/")[8]
            } | Where-Object {$_.RemoteResourceGroupName}
        }

        # If peering exist
        if ($peers) {
            # Set context to the Shared Services subscription so that the peering can be deleted
            try {
                $sharedSubscription = Get-AzSubscription -SubscriptionId "c0c8209e-5456-409b-9615-693a24c44079"

                Set-AzContext -Subscription $sharedSubscription.id -ErrorAction Stop | Out-Null
                Write-Host "Successfully set the context to '$($sharedSubscription.Name)'"
            } catch {
                throw $_
            }

            $lockName = "NetworkRGDoNotDelete"
            $lockNotes = "Added back after deleting the vNet peerings as part of 'Delete cloud landscape' SR"

            # get the unique list of all the applicable resource groups so that the locks can be removed
            $resourceGroupNames =  $peers | Select-Object -ExpandProperty RemoteResourceGroupName -Unique 

            # remove locks for each resource group
            foreach ($resourceGroupName in $resourceGroupNames) {
                # Get the resource group locks
                $lock = Get-AzResourceLock -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $lockName}     

                # Delete the lock if it exists. 
                if ($lock) {
                    try {
                        $lock | Remove-AzResourceLock -Force | Out-Null
                        Write-Host "Successfully deleted the lock '$($lock.LockID)'"
                    } catch {
                        Write-Host "Failed to delete the lock '$($lock.LockID)' due to $_"
                    }
                }
            }

            # Delete the peering by looping through each one it
            foreach ($peer in $peers) {
                $peerName = "$($peer.RemoteVirtualNetworkName)-$($peer.SourceVirtualNetworkName)" 
                $peerInfo = Get-AzVirtualNetworkPeering -VirtualNetworkName $peer.RemoteVirtualNetworkName -ResourceGroupName $peer.RemoteResourceGroupName -Name $peerName -ErrorAction SilentlyContinue

                if ($peerInfo) {
                    # Delete the peering if it exists
                    try {
                        $peerInfo | Remove-AzVirtualNetworkPeering -ErrorAction Stop
                        Write-Host "Successfully deleted the peer '$($peer.RemoteResourceGroupName)\$($peer.RemoteVirtualNetworkName)\$peerName'"
                    } catch {
                        Write-Host "Failed to delete the peer '$($peer.RemoteResourceGroupName)\$($peer.RemoteVirtualNetworkName)\$peerName' due to $_"
                    }
                } else {
                    Write-Host "'$($peer.RemoteResourceGroupName)\$($peer.RemoteVirtualNetworkName)\$peerName' not found. could be that it was manually deleted from the shared subscription, skipping"
                }
            }

            # set the locks for the resource groups which were previoulsy removed
            foreach ($resourceGroupName in $resourceGroupNames) {
                # Get the resource group locks
                $lock = Get-AzResourceLock -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $lockName}

                # create the new lock if it doesnt already exist
                if (-not $lock) {
                    try {
                        $createLock = New-AzResourceLock -LockName $lockName -LockNotes $lockNotes -LockLevel CanNotDelete -ResourceGroupName $resourceGroupName -Force 
                        Write-Host "Successfully created the lock '$($createLock.LockID)'"
                    } catch {
                        Write-Host "Failed to create the lock '$lockName' on '$resourceGroupName' due to $_"
                    }
                }
            }

            # remove the shared subscription context to avoid any impact
            Get-AzContext | Remove-AzContext -Force

            # setting again the subscription context to ensure it is not set to the shared subscrpiton or any other subscription
            try {
                Set-AzContext -Subscription $subscription.id -ErrorAction Stop | Out-Null
                Write-Host "Successfully set the context to '$($subscription.Name)'"
            } catch {
                throw $_
            }
        } else {
            Write-Host "No peering found, skipping"
        }
    } 

    # Remove resource groups
    if ($RemoveResourceGroups -or $RemoveAll) {
        $resourceGroups = Get-AzResourceGroup -ErrorAction SilentlyContinue

        if ($resourceGroups) {
            foreach ($resourceGroup in $resourceGroups) {
                try {
                    Remove-AzResourceGroup -Id $resourceGroup.ResourceId
                    Write-Host "Successfully deleted the resource group '$($resourceGroup.ResourceGroupName)'"
                } catch {
                    Write-Host "Failed to delete the resource group '$($resourceGroup.ResourceGroupName)' due to $_"
                }
            }
            
        } else {
            Write-Host "No resource groups exist, skipping"
        }
    }

    # Remove consumption budget
    if ($RemoveBudget -or $RemoveAll) {
        
        $budget = Get-AzConsumptionBudget -ErrorAction SilentlyContinue

        if ($budget) {
            try {
                $budget | Remove-AzConsumptionBudget
                Write-Host "Successfully deleted the budget"
            } catch {
                Write-Host "Failed to delete the budget due to $_"
            }
        } else {
            Write-Host "No budget exists, skipping"
        }
    }

    # Remove role assignments

    if ($RemoveRoleAssignments -or $RemoveAll) {

        $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" | Where-Object {$_.Scope -eq "/subscriptions/$($subscription.Id)" -and $_.DisplayName -like "Azure-*"}

        if ($roleAssignments) {
            try {
                $roleAssignments | Remove-AzRoleAssignment
                Write-Host "Successfully deleted the RBAC role assignments"
            } catch {
                Write-Host "Failed to delete the RBAC role assignments"
            }
        } else {
            Write-Host "No RBAC role assignments found on the subscription, skipping"
        }
    }

    # Remove service principal
    if ($RemoveServicePrincipal -or $RemoveAll) {
        
        $splitVars = $subscription.Name -split "-" # spliting the subscription name to pupulate the Azure AD group name
        $spName  = ("Azure-$($splitVars[2])-$($splitVars[1])-sp") -replace " ", "" # removing spaces
        $servicePrincipal = Get-AzADServicePrincipal -DisplayName $spName

        if ($servicePrincipal) {
            try {
                Remove-AzADServicePrincipal -ApplicationId $servicePrincipal.ApplicationId
                Write-Host "Successfully deleted the service principal"
            } catch {
                Write-Host "Failed to delete the service principal due to $_"
            }
        } else {
            Write-Host "No service principal exists, skipping"
        }

        # Remove application
        $application = Get-AzADApplication -DisplayName $spName 

        if ($application) {
            try {
                $application | Remove-AzADApplication
                Write-Host "Successfully deleted the service principal application"
            } catch {
                Write-Host "Failed to delete the service principal application due to $_"
            }
        } else {
            Write-Host "No service principal application exists, skipping"
        }
    }
}

function Install-cAzPreRequisiteModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()] $ModuleListPath,
        [Parameter(Mandatory)][ValidateSet('CurrentUser','AllUsers')] $Scope
    )

    if (-not $(Test-Path -Path $ModuleListPath) ) {
        throw "Could not find the '$ModuleListPath' file, exiting the script"
    }

    $modules = Get-Content $ModuleListPath | ConvertFrom-Json | ConvertTo-HashTable | Select-Object -ExpandProperty Values

    $failure = $false

    foreach ($module in $modules){
        
        $Prams = @{ Name = $module.Name } # Splatting

        if ($module.State -eq 'Allowed') {
            if ($module.MinimumVersion -ne '' ) {
                if (-not $(Get-InstalledModule -Name $module.Name -MinimumVersion $module.MinimumVersion -ErrorAction SilentlyContinue)) {
                    
                    Write-Host "Module '$($module.Name)' not found, installing in '$Scope' scope"
                    try  {
                        $Prams.Add('Scope', $Scope)
                        Install-Module -Name $module.Name -SkipPublisherCheck -Force
                        Write-Host "Successfully installed '$($module.Name)'"
                    } catch {
                        $failure = $true
                        Write-Host "Failed to install '$($module.Name)' due to $_"
                    }
                } else {
                    Write-Host "Module '$($module.Name)' lastest version is already installed, skipping"
                }
            } else {
                # Add AllowPreRelease to the Parms hash table for using splatting
                if ($module.AllowPreRelease -eq 'Yes') {
                    $Prams.Add('AllowPrerelease', $true)
                } 

                if (Get-InstalledModule @Prams -ErrorAction SilentlyContinue) {
                    Write-Host "Module '$($module.Name)' is already installed, skipping"
                } else {
                    
                    Write-Host "Module '$($module.Name)' not found, installing in '$Scope' scope"

                    # If module is not imported, not available on disk, but is in online gallery then install and import
                    if (Find-Module @Prams -ErrorAction SilentlyContinue) {
                        try {
                            $Prams.Add('Scope', $Scope)
                            Install-Module @Prams -Force 
                            Write-Host "Successfully installed '$($module.Name)'"
                        } catch {
                            $failure = $true
                            Write-Host "Failed to install '$($module.Name)' due to $_"
                        }
                    } else {
                        # If module is not imported, not available and not in online gallery then abort
                        Write-Host "Module '$($module.Name)' not imported, not available and not in online gallery, exiting"
                    }
                }
            }
        } else {
            if (Get-InstalledModule @Prams -ErrorAction SilentlyContinue) {
                $Prompt = Read-Host -Prompt "Module '$($module.Name)' must not be present on the machine. Do you want to proceed with the uninstallation? Type 'Y' to proceed else will skip"

                If ($Prompt -ne 'Y') {
                    Write-Host "Skipping the uninstallation of '$($module.Name)'"
                    $failure = $true
                } else {
                    try {
                        Uninstall-Module -Name $module.Name -Force
                        Write-Host "Successfully uninstalled '$($module.Name)'"
                    } catch {
                        Write-Host "Failed to uninstall '$($module.Name)'"
                    }
                }
            } else {
                Write-Host "Module '$($module.Name)' is not installed, ignoring"
            }
        }
    }

    $failure
}

function New-cAzBuiltInRBACRoleAssignment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $SubscriptionID,
        [Parameter(Mandatory)] $UserList,
        [Parameter(Mandatory)] $RBACRole
    )

    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionID
    $splitVars = $subscription.Name -split "-" # spliting the subscription name to pupulate the Azure AD group name
    $aadGroupName  = ("Azure-$($splitVars[2])-$($splitVars[1])-$rbacRole") -replace " ", "" # removing spaces
    $azureADGroup = Get-AzADGroup -DisplayName $aadGroupName
        
    # Create Azure AD group if it doesnt exist
    if ($null -eq $azureADGroup) {
        $azureADGroup = New-AzADGroup -DisplayName $aadGroupName -MailNickName $aadGroupName
        Write-Host "`nCreated '$aadGroupName' group"
    } else {
        Write-Host "`n'$aadGroupName' group already exists. Skipping"
    }
        
    # Assing RBAC permissions for the Azure AD group on the subscription
    $azureADRoleAssginment = Get-AzRoleAssignment -ObjectId $azureADGroup.Id -RoleDefinitionName $rbacRole -Scope "/subscriptions/$SubscriptionID"
                
    If ($null -eq $azureADRoleAssginment) {
        $retryCount = 10
        $count = 0
        $success = $false
        do {
            try {
                New-AzRoleAssignment -ObjectId $azureADGroup.Id -RoleDefinitionName $rbacRole -Scope "/subscriptions/$SubscriptionID" -ErrorAction Stop | Out-Null
                Write-Host "Created '$rbacRole' role assginment for subscription id $SubscriptionID"
                $success = $true
            }
            catch {
                Write-host "Couldnt create the role assignment. Retrying in 10 seconds. Failed due to: $_"
                Start-sleep -Seconds 10 # sleep for 10 seconds in case of a failure
            }
            $count++
    
        } until($count -eq $retryCount -or $success)
    } else {
        Write-Host "'$($azureADGroup.DisplayName)' role assginment for subscription id $SubscriptionID already exists. Skipping"
    }

    # Add Azure AD user to the group
    $users =  $UserList -split ";" | Where-Object {$_} # splitting the user list using ; remove empty values

    foreach ($user in $users) {
        $user = $user.trim()
        $azureADUser = Get-AzADUser -UserPrincipalName $user 
                    
        #If user is found in Azure AD, add to the group
        If ($azureADUser) {
            try {
                $groupMember = Get-AzADGroupMember -GroupDisplayName $aadGroupName | Where-Object {$_.UserPrincipalName -eq $user}
                            
                If ($groupMember) {
                    Write-Host "'$user' already member of '$aadGroupName'"
                } else { # the user is not present in the group
                    Add-AzADGroupMember -MemberUserPrincipalName $user -TargetGroupDisplayName $aadGroupName -ErrorAction Stop
                    Write-Host "Added '$user' to '$aadGroupName'"
                }
            } catch {
                Write-Host "Could not add '$user' to '$aadGroupName' due to $_ "
            }
        } else {
            Write-Host "Could not find '$user'"
        } 
    }
}


function Add-cAzUserToRBACRole {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $SubscriptionID,
        [Parameter(Mandatory)] $UserList,
        [Parameter(Mandatory)] $RBACRole
    )

    $scope = "/subscriptions/$SubscriptionID"
    $aadGroupName = Get-AzRoleAssignment -Scope $scope | Where-Object {$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $RBACRole -and $_.ObjectType -eq 'Group'} | Select-Object -ExpandProperty DisplayName

    # add Azure AD user to a group
    $users =  $UserList -split ";" | Where-Object {$_} # splitting the user list using ; remove empty values

    foreach ($user in $users) {
        $user = $user.trim()
        $azureADUser = Get-AzADUser -UserPrincipalName $user 
                    
        #If user is found in Azure AD, add to the group
        If ($azureADUser) {
            try {
                $groupMember = Get-AzADGroupMember -GroupDisplayName $aadGroupName | Where-Object {$_.UserPrincipalName -eq $user}
                            
                If ($groupMember) {
                    Write-Host "'$user' already member of '$aadGroupName'"
                } else { # the user is not present in the group
                    Add-AzADGroupMember -MemberUserPrincipalName $user -TargetGroupDisplayName $aadGroupName -ErrorAction Stop
                    Write-Host "Added '$user' to '$aadGroupName'"
                }
            } catch {
                Write-Host "Could not add '$user' to '$aadGroupName' due to $_ "
            }
        } else {
            Write-Host "Could not find '$user'"
        } 
    }
}

function Remove-cUserFromRBACRole {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $SubscriptionID,
        [Parameter(Mandatory)] $UserList,
        [Parameter(Mandatory)] $RBACRole
    )

    $scope = "/subscriptions/$SubscriptionID"
    $aadGroupName = Get-AzRoleAssignment -Scope $scope | Where-Object {$_.Scope -eq $scope -and $_.RoleDefinitionName -eq $RBACRole -and $_.ObjectType -eq 'Group'} | Select-Object -ExpandProperty DisplayName

    # add Azure AD user to a group
    $users =  $UserList -split ";" | Where-Object {$_} # splitting the user list using ; remove empty values

    foreach ($user in $users) {
        $user = $user.trim()
        $azureADUser = Get-AzADUser -UserPrincipalName $user 
                    
        #If user is found in Azure AD, add to the group
        If ($azureADUser) {
            try {
                $groupMember = Get-AzADGroupMember -GroupDisplayName $aadGroupName | Where-Object {$_.UserPrincipalName -eq $user}
                            
                If ($groupMember) { #user is present in the group
                    Remove-AzADGroupMember -MemberUserPrincipalName $user -GroupDisplayName $aadGroupName -ErrorAction Stop
                    Write-Host "Removed '$user' from '$aadGroupName'"
                } else { # the user is not present in the group
                    Write-Host "'$user' is not a member of '$aadGroupName'"
                }
            } catch {
                Write-Host "Could not remove '$user' from '$aadGroupName' due to $_ "
            }
        } else {
            Write-Host "Could not find '$user'"
        } 
    }
}

function Set-cAzTags {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $SubscriptionId,
        [Parameter(ParameterSetName='Object')] $Tags,
        [Parameter(ParameterSetName='Tags')] $Owner,
        [Parameter(ParameterSetName='Tags')] $SecondaryOwner,
        [Parameter(ParameterSetName='Tags')] $BusinessUnit,
        [Parameter(ParameterSetName='Tags')] $CostCentre,
        [Parameter(ParameterSetName='Tags')] $SupportTeamDL
    )

    # If Tags object is not set
    if (-not $PSBoundParameters.ContainsKey('Tags')) {
        $Tags = [ordered]@{}
        
        #Add to the Tags hash table only if the Paramters are set i.e not null or empty
        $variables = @('Owner', 'SecondaryOwner', 'BusinessUnit', 'CostCentre', 'SupportTeamDL') # add new tags here as well
        foreach ($variable in $variables) {
            # assigning $variable = value
            if($(Get-Variable -Name $variable -ValueOnly)) {$Tags.Add($variable,$(Get-Variable -Name $variable -ValueOnly))}
        }
    }

    $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue
    if(-not $subscription) {
        Throw "Subscription with id '$SubscriptionId' not found, quitting"
    }

    if (-not $(Get-AzContext | Where-Object {$_.Subscription -like $SubscriptionID})) {
        Set-AzContext -Subscription $SubscriptionID | Out-Null
    }

    try {
        Update-AzTag -ResourceId "/subscriptions/$SubscriptionId" -Tag $Tags -Operation Merge | Out-Null
        Write-Host "Successfully updated tags on the subscription '$($subscription.Name)'"
    } catch {
        Write-Host "Failed to update tags on the subscription '$($subscription.Name)' due to $_"
    }

    foreach ($resourceGroup in $(Get-AzResourceGroup)) {
        try {
            Update-AzTag -ResourceId $resourceGroup.ResourceId -Tag $Tags -Operation Merge | Out-Null
            Write-Host "Successfully updated tags on the resource group '$($resourceGroup.ResourceGroupName)'"
        } catch {
            Write-Host "Failed to update tags on the resource group '$($resourceGroup.ResourceGroupName)' due to $_"
        }
    }

    foreach ($resource in $(Get-AzResource)) {
        try {
            Update-AzTag -ResourceId $resource.ResourceId -Tag $Tags -Operation Merge | Out-Null
            Write-Host "Successfully updated tags on the resource '$($resource.Name)'"
        } catch {
            Write-Host "Failed to update tags on the resource '$($resource.Name)' due to $_"
        }
    }
}

