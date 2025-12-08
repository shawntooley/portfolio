# Define an array of scope configurations
$Scopes = @(
    @{
        Name = "DevNet_Scope"
        StartRange = "192.168.1.100"
        EndRange = "192.168.1.200"
        SubnetMask = "255.255.255.0"
        Router = "192.168.1.1"
        DnsServer = "192.168.1.10"
        LeaseDuration = "8.00:00:00"
    },
    @{
        Name = "ProdNet_Scope"
        StartRange = "192.168.2.100"
        EndRange = "192.168.2.200"
        SubnetMask = "255.255.255.0"
        Router = "192.168.2.1"
        DnsServer = "192.168.2.10"
        LeaseDuration = "8.00:00:00"
    }
)

# Loop through each scope configuration and create the scope
foreach ($Scope in $Scopes) {
    Add-DhcpServerv4Scope -Name $Scope.Name `
        -StartRange $Scope.StartRange `
        -EndRange $Scope.EndRange `
        -SubnetMask $Scope.SubnetMask `
        -Router $Scope.Router `
        -DnsServer $Scope.DnsServer `
        -LeaseDuration $Scope.LeaseDuration `
        -Activate
    Write-Host "Scope '$($Scope.Name)' created and activated."
}