# ============================
# PowerCLI vTPM Add Script (Shutdown, Add vTPM, Power On)
# ============================
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

# Prompt for vCenter credentials securely
$vcServer = "vc.ohiogratings.com"
$credential = Get-Credential -Message "Enter vCenter credentials"

# Set new VM resources
$NewCPU = 2
$NewMemoryGB = 8


# Connect to vCenter
Connect-VIServer -Server $vcServer -Credential $credential

# Path to VM list file (one VM name per line)
$vmListFile = "C:\Users\seitech\Documents\VMList.txt"
# Remove empty lines
$vmList = Get-Content $vmListFile | Where-Object { $_.Trim() -ne "" }

# Log file
$logFile = "C:\Users\seitech\Documents\vTPM_Add_Log.txt"
"Date,VMName,Status,Message" | Out-File $logFile

foreach ($vmName in $vmList) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    try {
        $vm = Get-VM -Name $vmName -ErrorAction Stop

        # Check hardware version and firmware
        if ($vm.ExtensionData.Config.Version -lt "vmx-14") {
            throw "Hardware version too low (requires 14 or higher)"
        }
        if ($vm.ExtensionData.Config.Firmware -ne "efi") {
            throw "VM firmware is not UEFI"
        }

        Write-Host "Shutting down $vmName..."
        Shutdown-VMGuest -VM $vm -Confirm:$false

        # Wait for VM to power off
        while ($vm.PowerState -ne "PoweredOff") {
            Start-Sleep -Seconds 5
            $vm = Get-VM -Name $vmName
        }

        # Resize VM resources to match 2 vCPU and 8GB RAM
        Get-VM -Name $VMName | Set-VM -NumCPU $NewCPU -MemoryGB $NewMemoryGB -Confirm:$false

        Write-Host "Adding vTPM to $vmName..."
        New-VTpm -VM $vm -ErrorAction Stop

        Write-Host "Powering on $vmName..."
        Start-VM -VM $vm -Confirm:$false

        "$timestamp,$vmName,Success,vTPM added and VM powered on" | Out-File $logFile -Append
    }
    catch {
        "$timestamp,$vmName,Failed,$($_.Exception.Message)" | Out-File $logFile -Append
        Write-Host "Failed for $vmName $($_.Exception.Message)"
    }
}

# Disconnect from vCenter
Disconnect-VIServer -Server $vcServer -Confirm:$false