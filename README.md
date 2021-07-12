# VM OnBoarding Runbook

If you are looking to on board VM's in a or set of subscription to a centralized workspace, you can use this runbooks to reconfigure and reinstall your VM's agents to point to a workspace passed to this runbook. It consists on two runbook
1) Parent - OnBoardAllSubVMCentralizedAgent.ps1-  It takes subscription csv list to iterate through the subscriptions and check if the agent is installed with the passed workspace. if not it will call the child runbook. 
2) Child - OnBoardMMAAgentOnAVM.ps1-  It is created by parent runbook for each VM. It will start the VM if stopped, reconfigure the VM and shut it down again. - 

