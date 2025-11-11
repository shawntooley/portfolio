<#
Written by Shawn Tooley, Seifert Technologies 
.SYNOPSIS
Power Off VM
Add vTPM to VMs on vCenter along with Logging 
Power On VM when Complete
.DESCRIPTION
Version 1.0 - Updated 2025-11-11
This script will add a virtual TPM to a list of VMs specified in a text file. The script requires VMware PowerCLI to be installed and connected to the vCenter server.
#>

# Configure PowerCLI to ignore certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

$cred = Get-Credential

# Connect to vCenter using the credentials
Connect-VIServer -Server "vc.ohiogratings.com" -Credential $cred

# Input file with VM names
$vmList = Get-Content "C:\Users\seitech\Documents\VMList.txt"

# Log file path
$logFile = "C:\Users\seitech\Documents\vTPM_Add_Log.txt"

# Start logging
"Date,VMName,Status,Message" | Out-File $logFile

foreach ($vmName in $vmList) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    try {
        $vm = Get-VM -Name $vmName -ErrorAction Stop                                        -
        Write-Host "Adding vTPM to $vmName..."
        New-VTpm -VM $vm -ErrorAction Stop

        # Reboot VM
        Restart-VMGuest -VM $vm -Confirm:$false -ErrorAction Stop

        # Log success
        "$timestamp,$vmName,Success,vTPM added and VM rebooted" | Out-File $logFile -Append
    }
    catch {
        # Log failure
        "$timestamp,$vmName,Failed,$($_.Exception.Message)" | Out-File $logFile -Append
        Write-Host "Failed for $vmName $($_.Exception.Message)"
    }
}

# Disconnect from vCenter
