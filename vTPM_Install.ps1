<#
.SYNOPSIS
Add vTPM to VMs on vCenter along with Logging and Reboot the VMs
Written by Shawn Tooley, Seifert Technologies  
.DESCRIPTION
Version 1.0 - Updated 2025-11-11
This script will add a virtual TPM to a list of VMs specified in a text file and then reboot each VM to apply the changes. The script requires VMware PowerCLI to be installed and connected to the vCenter server.
#>
# Connect to vCenter
Connect-VIServer -Server "vc.ohiogratings.com" -User "administrator@vsphere.local" -Password "PASSWORD"

# Input file with VM names
$vmList = Get-Content "C:\VMList.txt"

# Log file path
$logFile = "C:\vTPM_Add_Log.txt"

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
