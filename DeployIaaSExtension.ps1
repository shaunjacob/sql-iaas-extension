$connectionName = "AzureRunAsConnection"

try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint -Subscription $servicePrincipalConnection.SubscriptionId 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Scale Up Starts Here
$Start = Get-Date

#Define the policy definition, this is the same ID across all Azure tenants
$PolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/ebb67efd-3c46-49b0-adfe-5599eb944998'

#Identify the VM's that are Compliant, and have SQL installed
$CompliantVMs = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "Compliant" -and $_.PolicyDefinitionId -eq "$PolicyDefinitionId" }

#Loop through and install the SQL extension on each discovered VM
foreach ($SQLVM in $CompliantVMs) {

    $vm = get-azresource -ResourceId $SQLVM.ResourceId
    $check = Get-AzSqlVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue

    if (!$check) {
    New-AzSqlVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Location $vm.Location -LicenseType AHUB -SqlManagementType LightWeight
    Write-Host $vm "has been created"
    }
} 


$Stop = Get-Date
$TimeTaken = ($Stop - $Start).TotalSeconds
Write-Output "The time to run this script was $TimeTaken seconds"
Write-Output "Done"