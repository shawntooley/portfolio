#   Relocate Outlook PSTs to %USERPROFILE%\EMAIL
# - Moves the default POP delivery PST and triggers Outlook to prompt for the new path on next start
# - Rehomes non-default PSTs automatically (remove + re-add) so no user action is needed for them

# Target path (use USERPROFILE, not USERNAME, because %USERNAME% is just the name, not a path)
$TargetRoot = Join-Path $env:USERPROFILE 'EMAIL'
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

# Helper: release COM objects
function Release-ComObject {
    param([Parameter(Mandatory=$true)]$ComObject)
    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) | Out-Null } catch {}
}

Write-Host "Ensuring Outlook is not running..."
Get-Process OUTLOOK -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null; Start-Sleep 2; if (-not $_.HasExited) { $_.Kill() } }
Start-Sleep 1

# Discover highest Office version key to set ForcePSTPath
$officeVersions = @('19.0','18.0','16.0','15.0','14.0') # include future/newer if present
$officeRoot = 'HKCU:\Software\Microsoft\Office'
$foundVersion = $null
foreach ($v in $officeVersions) {
    if (Test-Path (Join-Path $officeRoot "$v\Outlook")) { $foundVersion = $v; break }
}
if (-not $foundVersion) { $foundVersion = '16.0' } # default to 16 for M365/2016+

$OutlookKey = Join-Path $officeRoot "$foundVersion\Outlook"
Write-Host "Setting ForcePSTPath under $OutlookKey to $TargetRoot"
New-Item -Path $OutlookKey -Force | Out-Null
New-ItemProperty -Path $OutlookKey -Name 'ForcePSTPath' -Value $TargetRoot -PropertyType ExpandString -Force | Out-Null
# (Note: ForcePSTPath affects newly created PST/IMAP data files, not existing ones)  # ref: Slipstick + MS Q&A

# Start Outlook object model to enumerate stores
Write-Host "Starting Outlook via COM to enumerate stores..."
$ol = New-Object -ComObject Outlook.Application
$session = $ol.Session

$stores = @()
foreach ($store in $session.Stores) {
    $path = $store.FilePath
    $isDefault = $store.IsDataFileStore -and $store.StoreID -eq $session.DefaultStore.StoreID
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ([IO.Path]::GetExtension($path).ToLower() -ne '.pst') { continue }  # ignore OST/Exchange stores
    $stores += [pscustomobject]@{
        DisplayName  = $store.DisplayName
        FilePath     = $path
        IsDefaultPST = $isDefault
        StoreObject  = $store
    }
}

if ($stores.Count -eq 0) {
    Write-Warning "No PST stores found in the current Outlook profile."
}

# Process non-default PSTs first: remove from profile, move file, re-add from new path
foreach ($s in $stores | Where-Object { -not $_.IsDefaultPST }) {
    $old = $s.FilePath
    $new = Join-Path $TargetRoot (Split-Path -Leaf $old)
    if ($old -ieq $new) {
        Write-Host "Archive PST '$($s.DisplayName)' already under $TargetRoot, skipping."
        continue
    }
    Write-Host "Rehoming (non-default) PST: '$($s.DisplayName)'"
    try {
        # RemoveStore requires Folder object for root
        $rootFolder = $s.StoreObject.GetRootFolder()
        $session.RemoveStore($rootFolder)                               # detach  (supported OOM call)
        Move-Item -LiteralPath $old -Destination $new -Force            # move file on disk
        $session.AddStoreEx($new, 2)                                    # reattach (2 = olStoreUnicode)
        Write-Host " - Moved to: $new and reattached."
    } catch {
        Write-Warning " - Failed to move '$($s.DisplayName)': $($_.Exception.Message)"
    } finally {
        if ($rootFolder) { Release-ComObject $rootFolder }
    }
}

# Now handle the default POP delivery PST:
$defaultPst = $stores | Where-Object { $_.IsDefaultPST } | Select-Object -First 1
if ($defaultPst) {
    $old = $defaultPst.FilePath
    $new = Join-Path $TargetRoot (Split-Path -Leaf $old)
    if ($old -ieq $new) {
        Write-Host "Default delivery PST already under $TargetRoot, nothing to do."
    } else {
        Write-Host "Moving default delivery PST to: $new"
        try {
            # Close Outlook completely so the default store is not locked
            Release-ComObject $session
            Release-ComObject $ol
            Start-Sleep 1
            Get-Process OUTLOOK -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }

            Move-Item -LiteralPath $old -Destination $new -Force

            Write-Host ""
            Write-Host "Launching Outlook… It will likely prompt: “Outlook Data File (.pst) cannot be found”."
            Write-Host "Browse to: $new"
            Write-Host ""

            # Start Outlook so the user can browse to the moved PST
            Start-Process "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE" -ErrorAction SilentlyContinue
            Start-Process "$env:ProgramFiles(x86)\Microsoft Office\root\Office16\OUTLOOK.EXE" -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to move default PST: $($_.Exception.Message)"
        }
    }
} else {
    Write-Host "No default PST identified (this profile might not be POP)."
}

# Clean up
if ($session) { Release-ComObject $session }
if ($ol) { Release-ComObject $ol }
[GC]::Collect(); [GC]::WaitForPendingFinalizers()