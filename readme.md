# Identify and Install the SQL IaaS Extension

 

The purpose of this document is to describe the process of identifying all SQL VM’s that are deployed in a subscription. This will be done via the in-guest policy definition, after which all identified SQL VM’s can have the SQL IaaS extension deployed via PowerShell

The SQL Server IaaS Agent extension allows for integration with the Azure portal, and depending on the management mode, unlocks a number of feature benefits for SQL Server on Azure VMs:

- **Feature benefits**: The extension unlocks a number of automation feature benefits, such as portal management, license flexibility, automated backup, automated patching and more. See [Feature benefits](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-server-iaas-agent-extension-automate-management?tabs=azure-powershell#feature-benefits) later in this article for details.
- **Compliance**: The extension offers a simplified method of fulfilling the requirement to notify Microsoft that the Azure Hybrid Benefit has been enabled as is specified in the product terms. This process negates needing to manage licensing registration forms for each resource.
- **Free**: The extension in all three manageability modes is completely free. There is no additional cost associated with the extension, or with changing management modes.
- **Simplified license management**: The extension simplifies SQL Server license management, and allows you to quickly identify SQL Server VMs with the Azure Hybrid Benefit enabled using the [Azure Portal](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/manage-sql-vm-portal), PowerShell or the Azure CLI.

 



 

# Step 1: Assign Azure Policies

 

## 1.   Guest Configuration Policy

The first set of policies that need to be applied are grouped as an Initiative. This is named as:

**[Preview]: Deploy prerequisites to enable Guest Configuration policies on virtual machines**

This Initiative contains the following policy definitions:

- Add system-assigned managed identity to enable Guest Configuration assignments on virtual machines with no identities
- Add system-assigned managed identity to enable Guest Configuration assignments on VMs with a user-assigned identity
- Deploy the Windows Guest Configuration extension to enable Guest Configuration assignments on Windows VMs
- Deploy the Linux Guest Configuration extension to enable Guest Configuration assignments on Linux VMs

 

 
 

1. Select **Assign** to assign this initiative to your chosen subscription(s), you may add exclusions if required.

![Guest Configuration 1](https://github.com/shaunjacob/sql-iaas-extension/blob/main/Images/Guest%20Config%201.png)



2. Under remediation, you will notice that a managed identity will be created. This is necessary to allow the scanning of deployed software inside a guest VM. This identity can be created in a location if your choice. Tick the box to “Create a remediation task”, which will add the system assigned managed identity to existing VM’s

![Guest Configuration 2](https://github.com/shaunjacob/sql-iaas-extension/blob/main/Images/Guest%20Config%202.png)


3. Review and Create.

![Guest Configuration 2](https://github.com/shaunjacob/sql-iaas-extension/blob/main/Images/Guest%20Config%203.png)

 

## 2.   In-guest application policy

 

The final policy that needs to be applied is:

**Audit Windows machines that don’t have the specified applications installed.**

This policy works by scanning the registry for the application name, and if found it marks the VM as compliant.

1. Select **Assign** to assign this policy to your chosen subscription(s), you may add exclusions if required

![img](file:///C:/Users/SHAUNJ~1/AppData/Local/Temp/msohtmlclip1/01/clip_image008.jpg)



 

2. Define the applications to scan and report back on: 

   For example: ***Microsoft SQL Server SQL2019\****

 

![A picture containing text  Description automatically generated](file:///C:/Users/SHAUNJ~1/AppData/Local/Temp/msohtmlclip1/01/clip_image010.jpg)

3. Review and Create



 

# Step 2: Deploy IaaS Extension via PowerShell



The final step is to deploy the IaaS extension to all VMs that this assigned policy has detected SQL Server installed within the VMs.The script will scan through the policy definition and store each of the compliant VMs in a variable. The compliant VMs are the ones that have had SQL Server detected.

Once the $CompliantVMs variable has been populated, the script will cycle through and deploy the extension on each VM and place them into Lightweight mode. For more information on the modes, please click [here](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-server-iaas-agent-extension-automate-management?tabs=azure-powershell#management-modes)

 

\#Define the policy definition, this is the same ID across all Azure tenants

$PolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/ebb67efd-3c46-49b0-adfe-5599eb944998'

 

\#Identify the VM's that are Compliant, and have SQL installed

$CompliantVMs = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "Compliant" -and $_.PolicyDefinitionId -eq "$PolicyDefinitionId" }

 

\#Loop through and install the SQL extension on each discovered VM

foreach ($SQLVM in $CompliantVMs) {

 

  $vm = get-azresource -ResourceId $SQLVM.ResourceId

  $check = Get-AzSqlVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue

 

  if (!$check) {

  New-AzSqlVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Location $vm.Location -LicenseType AHUB -SqlManagementType LightWeight

  Write-Host $vm "has been created"

  }

} 

 

 

## Optional script

The script below will start the compliance scan manually on run. Usually, a compliance scan is run automatically every 24 hours, however it can be manually triggered. The method via PowerShell is as follows:

\#Store parameters and Start the Azure compliance scan

 

$compliancejob = Start-AzPolicyComplianceScan -AsJob

$endstate = "Completed"

$job = get-job -id $compliancejob.id

do {

  if($job.State -ne $endState) {

​    Write-Host "Waiting for compliance scan to complete..."

​    Start-Sleep -Seconds 5

  }             

 

} while ($job.State -ne $endState) 

 

This will run a compliance scan and only end once this is successful.

 

## Automation Account

 

An automation account in Azure can be created to run this script at regular intervals, ensuring that any SQL VM’s detected will always have the IaaS extension deployed. The script to create the account with the required modules is CreateAutomationAccount.ps1

