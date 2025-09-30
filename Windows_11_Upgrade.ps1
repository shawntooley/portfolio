Write-Host "Go to: https://www.microsoft.com/en-us/software-download/windows11"
Write-Host "Select Windows 11 (multi-edition ISO for x64 devices)"
Write-Host "Click Download"
Write-Host "Select English (United States)"
Write-Host "Click Confirm"
Write-Host "Right Click '64-bit Download' and click 'Copy link'"
 
$DownloadURL = Read-Host "Enter the Windows 11 ISO download link (in quotes)"
$ComputerName = Read-Host "Enter the target Computer Name"
 
# Check if the computer is online
if ($null -ne (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {  
     
    # Start a remote PowerShell session
    Enter-PSSession -ComputerName $ComputerName 
     
    # Ensure C:\temp exists
    if (!(Test-Path C:\temp)) {New-Item -Path C:\ -Name temp -ItemType Directory -Force}  
 
    # Set download path
    $DownloadPath = "C:\temp\win11.iso"
 
    # Download Windows 11 ISO
    Invoke-WebRequest -Uri $DownloadURL -OutFile $DownloadPath 
 
    # Mount the ISO
    $DiskImage = Mount-DiskImage -ImagePath $DownloadPath -StorageType ISO -NoDriveLetter -PassThru 
    $ISOPath = (Get-Volume -DiskImage $DiskImage).UniqueId
 
    # Create a PSDrive for the mounted ISO
    New-PSDrive -Name ISOFile -PSProvider FileSystem -Root $ISOPath 
    Push-Location ISOFile:
 
    # Find and run Setup.exe with upgrade parameters
    $SetupExe = (Get-ChildItem | Where-Object {$_.Name -like "*Setup.exe*"}).FullName  
    $Arguments = "/auto upgrade /DynamicUpdate Disable /quiet /eula accept /noreboot" 
    Start-Process -Wait -FilePath $SetupExe -ArgumentList "$Arguments" -PassThru 
 
    # Clean up: Unmount ISO and remove PSDrive  
    Pop-Location 
    Remove-PSDrive ISOFile  
    Dismount-DiskImage -DevicePath $DiskImage.DevicePath  
 
    # Ask for a restart decision  
    $YN = Read-Host "Do you want to restart? (Y/N)" 
    if ($YN -like "*Y*") {Restart-Computer -Force}  
    elseif ($YN -like "*N*") {Write-Host "Ask the user to restart."}  
    else {Write-Host "Ok, whatever, ask the user to restart."}  
 
} else {  
    Write-Host "The target computer is not reachable. Check the network or hostname and try again." 
}