$subIdCSVList = "--------Pass you subscription comma (,) seperated---------------"
$CorrectWorkspaceId = "---WorkspaceId to check ------"
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
    $subIdcsv = $subId + ".csv"
    Get-AzVM | Where { $_.StorageProfile.OSDisk.OSType -eq "Linux" -or  $_.StorageProfile.OSDisk.OSType -eq "Windows" } | Get-AzVMExtension | where-object { ($_.ExtensionType -eq "OmsAgentForLinux") -or ($_.ExtensionType -eq "MicrosoftMonitoringAgent") } | Select-Object VMName, Location, ResourceGroupName, ExtensionType, @{l="WorkspaceID"; e={ ($_.PublicSettings | ConvertFrom-Json).workspaceId }}, @{l="CorrectWorkspace";e={($_.PublicSettings | ConvertFrom-Json).workspaceId  -eq $CorrectWorkspaceId}} | Export-Csv -path $subIdcsv
}


