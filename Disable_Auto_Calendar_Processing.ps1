# ============================
# PowerShell Script to Disable Auto Calendar Processing for All Mailboxes
# ============================
<#
Written by Shawn Tooley, Seifert Technologies 
Version 1.0 - Updated 2025-12-22
#>

# Define log file path
$LogFile = "C:\Logs\CalendarProcessingAudit.csv"

# Create CSV header if file doesn't exist
if (-not (Test-Path $LogFile)) {
    "PrimarySmtpAddress,Identity,Action,Timestamp" | Out-File $LogFile
}

# Process all mailboxes
Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    $Mailbox = $_
    Write-Host "Disabling auto calendar processing for:" $Mailbox.PrimarySmtpAddress

    # Disable auto calendar processing
    Set-CalendarProcessing $Mailbox.Identity -AutomateProcessing None

    # Log the action
    $LogEntry = "{0},{1},{2},{3}" -f $Mailbox.PrimarySmtpAddress, $Mailbox.Identity, "Disabled AutoProcessing", (Get-Date)
    Add-Content -Path $LogFile -Value $LogEntry
}

