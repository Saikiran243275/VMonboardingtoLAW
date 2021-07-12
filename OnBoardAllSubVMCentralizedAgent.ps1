<#  
.SYNOPSIS  
Installs OMS extension for Linux and Windows Azure VMs. The Runbook takes comma seperated list of SubscriptionIds and 
installs OMS Agent on each VMs in the subscription.

The runbook needs run as connection string to access VMs in other subscriptions.

This runbook calls child runbook Install-OMSVMExtension. The Install-OMSVMExtension should be available in the automation account.
This runbook can be used in scenario to mass onboard list of Azure VM for OMS update management solution.

If you are want to onboard both Classic and ARM VMs in a single runbook, please set the input
parameter $OnboardClassicVMs to $true. Onboard-VMsForOMSUpdateManagement will invoke Onboard-ClassicVMsForOMSUpdateManagement internally.
The advantage of doing that would be Onboard-VMsForOMSUpdateManagement takes only comma seperated list of subscriptionId as input and there is no 
neccessity to pass SubscriptionIds=SubscriptionName mapping and a single runbook will import both classic and ARM VMs. 

.EXAMPLE
.\Onboard-VMsForOMSUpdateManagement

.NOTES
If you are want to onboard both Classic and ARM VMs in a single runbook, please set the input
parameter $OnboardClassicVMs to $true. Onboard-VMsForOMSUpdateManagement will invoke Onboard-ClassicVMsForOMSUpdateManagement internally.
The advantage of doing that would be Onboard-VMsForOMSUpdateManagement takes only comma seperated list of subscriptionId as input and there is no 
neccessity to pass SubscriptionIds=SubscriptionName mapping and a single runbook will import both classic and ARM VMs.

AUTHOR: Azure Automation Team
LASTEDIT: 2017.06.22
#>

param 
(
    [Parameter(Mandatory=$true, HelpMessage="Comma seperated values of SubscriptionId")] 
    [String] $subIdCSVList,
    [Parameter(Mandatory=$false)] 
    [bool] $OnboardClassicVMs = $false,
    [Parameter(Mandatory=$true)] 
    [String] $ResourceGrpName,
    [Parameter(Mandatory=$true)] 
    [String] $workspaceId,
    [Parameter(Mandatory=$true)] 
    [bool] $RemoveExtentionBeforeReconfigureLinux = $true,
    [Parameter(Mandatory=$true)] 
    [bool] $RemoveExtentionBeforeReconfigureWindows = $false,
    [Parameter(Mandatory=$true)] 
    [String] $workspaceKey	
)

$AzureConnectionAssetName = "AzureRunAsConnection"
$OnboardClassicVmForOMSUpdateManagementRunbookName = "OnboardClassicVmForOMSUpdateManagement"
$InstallOMSVMExtensionRunbookName = "OnBoardMMAAgentOnAVM"

try 
{
    # Connect to Azure using service principal auth
    $ServicePrincipalConnection = Get-AutomationConnection -Name $AzureConnectionAssetName         
    Write-Output "Logging in to Azure..."
    $Null = Add-AzAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint 
}
catch 
{
    if(!$ServicePrincipalConnection) 
    {
        throw "Connection $AzureConnectionAssetName not found."
    }
    else 
    {
        throw $_.Exception
    }
}

$subIdSubNameList = @{};
$subIdList = $subIdCSVList.Split(",")
 
ForEach ($subId in $subIdList) 
{

    $subIdDetails = Get-AzSubscription -SubscriptionId $subId
    if ($subIdDetails -eq $null) 
    {
        Write-Output "Cannot get subscription for subId $($subId) check service principal and permissions"
        Continue
    }	
	
    Set-AzContext -SubscriptionId $subId
    $subInfo = Get-AzSubscription -SubscriptionId $subId
    if ($subInfo -ne $null) 
    {
        $subIdSubNameList.Add($subInfo.SubscriptionId, $subInfo.Name)
    }

    $VMs = Get-AzVM -ResourceGroupName $ResourceGrpName| Where { $_.StorageProfile.OSDisk.OSType -eq "Windows" -or  $_.StorageProfile.OSDisk.OSType -eq "Linux" }

    # Start each of the VMs
    foreach ($VM in $VMs) 
    {
        $ExtentionNameAndTypeValue = 'MicrosoftMonitoringAgent'
	    if ($VM.StorageProfile.OSDisk.OSType -eq "Linux") 
        {
            $ExtentionNameAndTypeValue = 'OmsAgentForLinux'	
	    }

       
        $VME = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name | where-object { $_.ExtensionType -eq $ExtentionNameAndTypeValue } 
        #$VME = Get-AzureRmVMExtension -ExtensionName $ExtentionNameAndTypeValue -ResourceGroup $VM.ResourceGroupName -VMName $VM.Name -ErrorAction 'SilentlyContinue'
        if ($VME -ne $null)
        {
            $workspace_id = ($VME.PublicSettings | ConvertFrom-Json).workspaceId;
            Write-Output "Existing workspace ID $($workspace_id)";
            
            if($workspace_id -eq $workspaceId)
            {
                Write-Output "MMAExtention is already installed for VM $($VM.Name) and rightly configure with $($workspaceId)";
            }
            else
            {
                Write-Output "MMAExtention needs reconfiguration  for VM $($VM.Name)";
                Start-Sleep -s 2 # just not to hit trottle limit
                $InstallJobId = Start-AutomationRunbook -Name $InstallOMSVMExtensionRunbookName -Parameters @{'subId'=$subId;'VMName'=$VM.Name;'RemoveExtentionBeforeReconfigure'=$RemoveExtentionBeforeReconfigureLinux;'ResourceGroupName'=$VM.ResourceGroupName;'workspaceId'=$workspaceId;'workspaceKey'=$workspaceKey}
                if($InstallJobId -ne $null)
                {
                    Write-Output "Extension installation Job started with JobId $($InstallJobId) on VM $($VM.Name)"
                }
            }
        }
        else
        {
            #Start-Sleep -s 2 # just not to hit trottle limit
            Write-Output "MMAExtention needs installation  for VM $($VM.Name)";
            $InstallJobId =  Start-AutomationRunbook -Name $InstallOMSVMExtensionRunbookName -Parameters @{'subId'=$subId;'VMName'=$VM.Name;'RemoveExtentionBeforeReconfigure'=$RemoveExtentionBeforeReconfigureWindows;'ResourceGroupName'=$VM.ResourceGroupName;'workspaceId'=$workspaceId;'workspaceKey'=$workspaceKey}
            if($InstallJobId -ne $null)
            {
                Write-Output "Extension installation Job started with JobId $($InstallJobId) on VM $($VM.Name)"
            }
        }
    }
}

<#if ($OnboardClassicVMs -eq $true) 
{
    $subIdSubNameCSVParam = ($subIdSubNameList.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }) -join ',' 
    $ClassicVmJob =  Start-AutomationRunbook -Name $OnboardClassicVmForOMSUpdateManagementRunbookName -Parameters @{'subIdSubNameCSVList'=$subIdSubNameCSVParam}
    if($ClassicVmJob -ne $null) 
    {
        Write-Output "Classic VM Install JobId  started $($ClassicVmJob)"
    }
    else
    {
        Write-Output "Failed to start OnboardClassicVmForOMSUpdateManagement Runbook"   
    }
}#>

