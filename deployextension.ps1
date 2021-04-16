#Define the policy definition, this is the same ID across all Azure tenants
$PolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/d3b823c9-e0fc-4453-9fb2-8213b7338523'

#Identify the VM's that are Compliant, and have SQL installed
$CompliantVMs = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "Compliant" -and $_.PolicyDefinitionId -eq "$PolicyDefinitionId" }

#Loop through and install the SQL extension on each discovered VM
foreach ($SQLVM in $CompliantVMs) {

    $vm = get-azresource -ResourceId $CompliantVMs.ResourceId
    New-AzSqlVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Location $vm.Location -LicenseType AHUB -SqlManagementType LightWeight
} 
