
<#
.SYNOPSIS
	This is a sample script to deploy the required resources to execute scaling script in Microsoft Azure Automation Account.
	v0.1.7
	# //todo refactor stuff from https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help?view=powershell-5.1
#>
param(
	[Parameter(mandatory = $false)]
	[string]$SubscriptionId,
	
	[Parameter(mandatory = $false)]
	[string]$ResourceGroupName = "SQLIaaSResourceGroup",

	[Parameter(mandatory = $false)]
	[string]$AutomationAccountName = "SQLIaaSAutomationAccount",

	[Parameter(mandatory = $false)]
	[string]$Location = "Australia East",

	[Parameter(mandatory = $false)]
	[string]$ArtifactsURI = 'https://raw.githubusercontent.com/shaunjacob/sql-iaas-extension/main',

	[Parameter(mandatory = $false)]
	[string]$ScheduleName = 'DailySQLCheck'
)

# //todo refactor, improve error logging, externalize, centralize vars

# Setting ErrorActionPreference to stop script execution when error occurs
$ErrorActionPreference = "Stop"

# Initializing variables
[string]$RunbookName = "Deploy-SQLIaaS-Extension"

# Import Az and AzureAD modules
Import-Module Az.Resources
Import-Module Az.Accounts
Import-Module Az.Automation

[array]$RequiredModules = @(
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.PolicyInsights'
	'Az.SqlVirtualMachine'
)

# Function to check if the module is imported
function Wait-ForModuleToBeImported {
	param(
		[Parameter(mandatory = $true)]
		[string]$ResourceGroupName,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName
	)

	$StartTime = Get-Date
	$TimeOut = 30*60 # 30 min

	while ($true) {
		if ((Get-Date).Subtract($StartTime).TotalSeconds -ge $TimeOut) {
			throw "Wait timed out. Taking more than $TimeOut seconds"
		}
		$AutoModule = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue
		if ($AutoModule.ProvisioningState -eq 'Succeeded') {
			Write-Output "Successfully imported module '$ModuleName' into Automation Account Modules"
			break
		}
		Write-Output "Waiting for module '$ModuleName' to get imported into Automation Account Modules ..."
		Start-Sleep -Seconds 30
	}
}

# Function to add required modules to Azure Automation account
function Add-ModuleToAutoAccount {
	param(
		[Parameter(mandatory = $true)]
		[string]$ResourceGroupName,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName,

		# if not specified latest version will be imported
		[Parameter(mandatory = $false)]
		[string]$ModuleVersion
	)

	[string]$Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName $ModuleVersion%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40"

	[array]$SearchResult = Invoke-RestMethod -Method Get -Uri $Url
	if ($SearchResult.Count -gt 1) {
		$SearchResult = $SearchResult[0]
	}

	if (!$SearchResult) {
		throw "Could not find module '$ModuleName' on PowerShell Gallery."
	}
	if ($SearchResult.Length -gt 1) {
		throw "Module name '$ModuleName' returned multiple results. Please specify an exact module name."
	}
	$PackageDetails = Invoke-RestMethod -Method Get -Uri $SearchResult.Id

	if (!$ModuleVersion) {
		$ModuleVersion = $PackageDetails.entry.properties.version
	}

	# Check if the required modules are imported
	$ImportedModule = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue
	if ($ImportedModule -and $ImportedModule.Version -ge $ModuleVersion) {
		return
	}

	[string]$ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

	# Test if the module/version combination exists
	try {
		Invoke-RestMethod $ModuleContentUrl | Out-Null
	}
	catch {
		throw [System.Exception]::new("Module with name '$ModuleName' of version '$ModuleVersion' does not exist. Are you sure the version specified is correct?", $PSItem.Exception)
	}

	# Find the actual blob storage location of the module
	$Res = $null
	do {
		$ActualUrl = $ModuleContentUrl
		$Res = Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -SkipHttpErrorCheck -ErrorAction Ignore
		$ModuleContentUrl = $Res.Headers['Location']
	} while ($ModuleContentUrl)

	New-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ContentLink $ActualUrl -Verbose
	Wait-ForModuleToBeImported -ModuleName $ModuleName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
}

# Note: the URL for the scaling script will be suffixed with current timestamp in order to force the ARM template to update the existing runbook script in the auto account if any
$URISuffix = "?time=$(get-date -f "yyyy-MM-dd_HH-mm-ss")"
$ScriptURI = "$ArtifactsURI/DeployIaaSExtension.ps1"

# Creating an automation account & runbook and publish the scaling script file
$DeploymentStatus = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri "$ArtifactsURI/runbookCreationTemplate.json" -AutomationAccountName $AutomationAccountName -RunbookName $RunbookName -location $Location -scriptUri "$ScriptURI$($URISuffix)" -Force -Verbose

if ($DeploymentStatus.ProvisioningState -ne 'Succeeded') {
	throw "Some error occurred while deploying a runbook. Deployment Provisioning Status: $($DeploymentStatus.ProvisioningState)"
}

# Required modules imported from Automation Account Modules gallery for Scale Script execution
foreach ($ModuleName in $RequiredModules) {
	Add-ModuleToAutoAccount -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ModuleName $ModuleName
}

#$StartTime = Get-Date "23:00:00"
#$EndTime = $StartTime.AddYears(1)
#New-AzAutomationSchedule -AutomationAccountName $automationAccountName -ResourceGroupName $ResourceGroupName -Name $ScheduleName -StartTime $StartTime -ExpiryTime $EndTime -DayInterval 1

