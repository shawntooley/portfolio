# ============================
# PowerCLI Enumberate VMs in Folder and Export to Text File
# ============================
<#
Written by Shawn Tooley, Seifert Technologies 
.SYNOPSIS
Enumberate VMs in Folder and Export to Text File
.DESCRIPTION
Version 1.0 - Updated 2025-11-11
#>

# Configure PowerCLI to ignore certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Prompt for vCenter credentials securely
$vcServer = "vc.ohiogratings.com"
$credential = Get-Credential -Message "Enter vCenter credentials"

# Connect to vCenter
Connect-VIServer -Server $vcServer -Credential $credential

# Specify folder name and output file
$folderName = "Vantage VM"
$outputFile = "C:\Users\seitech\Documents\VMList.txt"

# Get VMs in the folder and export names
(Get-Folder -Name $folderName | Get-VM).Name | Out-File $outputFile

Write-Host "VM list exported to $outputFile"

# Disconnect from vCenter
Disconnect-VIServer -Server $vcServer -Confirm:$false
