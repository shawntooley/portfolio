
<#
.SYNOPSIS
Bulk import AD users from CSV with extended attributes, manager, groups, and home/profile settings.

.DESCRIPTION
- Creates users (or updates attributes if they already exist)
- Sets email, department, title, office, phone, manager
- Adds users to groups (optionally creates missing groups)
- Handles proxyAddresses (SMTP aliases)
- Supports auto-increment for duplicate SamAccountName
- Supports -WhatIf for safe simulation and logs all actions
- Validates Path using Get-ADObject (supports OU=... and CN=Users,...)

.PARAMETERS
- CsvPath (mandatory): Path to the CSV file.
- DefaultOU: DN to use when CSV OU is empty (supports OU=... or CN=...).
- UPNSuffix: If set and CSV UPN is empty, builds UPN as Sam@UPNSuffix.
- LogPath: Custom log path; default is alongside CSV with timestamp.
- Server: Optional DC/FQDN to target (e.g., pag.pro-gr.com).
- CreateMissingGroups: If a group isn’t found, creates a Global/Security group in DefaultOU (or user OU).
- AutoIncrementSam: If the SamAccountName exists, auto-append a number (jsmith → jsmith1, jsmith2…).
- MustChangeAtLogon: If set, forces password change at next logon (overrides CSV if blank).
- HomeShareRoot: If provided and CSV HomeDirectory is blank, builds \\server\share\<sam>.
- HomeDrive: Default drive letter for HomeDirectory mapping (default H:).
- ProfileRoot: If provided and CSV ProfilePath is blank, builds \\server\profiles\<sam>.

.REQUIREMENTS
- RSAT ActiveDirectory module and permissions to create/update users & groups.
- Run PowerShell as Administrator.

.CSV COLUMNS (headers must match):
FirstName,LastName,DisplayName,SamAccountName,UserPrincipalName,OU,Password,MustChangeAtLogon,
Department,Title,Office,TelephoneNumber,Email,ManagerSamAccountName,Groups,
HomeDirectory,HomeDrive,ProfilePath,ProxyAddresses,Company,EmployeeID

.EXAMPLE
.\Import-ADUsers.ps1 -CsvPath .\users_ready.csv -DefaultOU "CN=Users,DC=pag,DC=pro-gr,DC=com" -UPNSuffix "pag.pro-gr.com" -AutoIncrementSam -CreateMissingGroups -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    [string]$DefaultOU,

    [string]$UPNSuffix,

    [string]$LogPath,

    [string]$Server,

    [switch]$CreateMissingGroups,

    [switch]$AutoIncrementSam,

    [switch]$MustChangeAtLogon,

    [string]$HomeShareRoot,

    [string]$HomeDrive = "H:",

    [string]$ProfileRoot
)

# ----------------- Utilities -----------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] {1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Message
    $line | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
    Write-Host $line
}

function Get-UniqueSam {
    param([string]$BaseSam, [string]$Server)
    $sam = $BaseSam
    $i = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -Server $Server -ErrorAction SilentlyContinue) {
        $sam = "$BaseSam$i"
        $i++
    }
    return $sam
}

function Test-ADPathExists {
    param([Parameter(Mandatory=$true)][string]$DistinguishedName, [string]$Server)
    try {
        $params = @{ Filter = "DistinguishedName -eq '$DistinguishedName'" }
        if ($Server) { $params.Server = $Server }
        $obj = Get-ADObject @params -ErrorAction Stop
        return $null -ne $obj
    } catch { return $false }
}

# ----------------- Begin -----------------
Import-Module ActiveDirectory -ErrorAction Stop

# Resolve log path
if (-not $LogPath -or $LogPath.Trim().Length -eq 0) {
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogPath = Join-Path (Split-Path -Path $CsvPath) "Import-ADUsers-$ts.log"
}
$script:LogPath = $LogPath
Write-Log "Starting import from CSV: $CsvPath"

# Load CSV
if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV '$CsvPath' not found."
}
$rows = Import-Csv -Path $CsvPath
Write-Log "Loaded $($rows.Count) rows."

$created = 0
$updated = 0
$groupAdds = 0
$errors = 0

foreach ($u in $rows) {
    try {
        # Normalize key fields
        $first = ($u.FirstName   | ForEach-Object { $_ }).ToString().Trim()
        $last  = ($u.LastName    | ForEach-Object { $_ }).ToString().Trim()
        $disp  = ($u.DisplayName | ForEach-Object { $_ }).ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($disp)) { $disp = "$first $last" }

        $sam   = ($u.SamAccountName | ForEach-Object { $_ }).ToString().Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($sam)) {
            # Build a base SAM from first initial + last name
            if ($first -and $last) { $sam = ("{0}{1}" -f ($first.Substring(0,1)), $last).ToLower() }
        }

        if ($AutoIncrementSam -and $sam) { $sam = Get-UniqueSam -BaseSam $sam -Server $Server }
        elseif ($sam) {
            if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -Server $Server -ErrorAction SilentlyContinue) {
                Write-Log "User with SamAccountName '$sam' already exists; will update attributes." "WARN"
            }
        }

        $upn = ($u.UserPrincipalName | ForEach-Object { $_ }).ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($upn) -and $UPNSuffix -and $sam) {
            $upn = "$sam@$UPNSuffix"
        }

        $ou = ($u.OU | ForEach-Object { $_ }).ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($ou)) { $ou = $DefaultOU }
        if ([string]::IsNullOrWhiteSpace($ou)) { throw "Path is required (either in CSV or via -DefaultOU)." }

        # Validate path exists (supports OU=... or CN=...)
        if (-not (Test-ADPathExists -DistinguishedName $ou -Server $Server)) {
            throw "Path '$ou' not found. Ensure DN is correct (supports OU=... and CN=...)."
        }

        # Prepare New-ADUser params
        $newParams = @{
            Name                  = $disp
            DisplayName           = $disp
            GivenName             = $first
            Surname               = $last
            SamAccountName        = $sam
            UserPrincipalName     = $upn
            Path                  = $ou
            Enabled               = $true
            ChangePasswordAtLogon = $false
        }
        if ($Server) { $newParams['Server'] = $Server }

        $mustChange = $false
        if ($MustChangeAtLogon) { $mustChange = $true }
        elseif ($u.MustChangeAtLogon -and $u.MustChangeAtLogon.ToString().ToUpper() -eq "TRUE") { $mustChange = $true }
        $newParams.ChangePasswordAtLogon = $mustChange

        # Password: if provided, set; else create disabled account
        if ($u.Password -and $u.Password.ToString().Trim().Length -gt 0) {
            $newParams.AccountPassword = (ConvertTo-SecureString $u.Password -AsPlainText -Force)
        } else {
            $newParams.Enabled = $false
            Write-Log "[$sam] No password provided; creating disabled user. Set a password later and enable." "WARN"
        }

        # Create or fetch user
        $existing = if ($sam) { Get-ADUser -Filter "SamAccountName -eq '$sam'" -Server $Server -ErrorAction SilentlyContinue } else { $null }
        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess("User '$sam' in $ou", "Create")) {
                New-ADUser @newParams
                $created++
                Write-Log "[$sam] Created in path: $ou"
            }
        } else {
            Write-Log "[$sam] Already exists; will update attributes."
        }

        # Fetch the user object with properties
        $getParams = @{ Identity = $sam; Properties = '*' }
        if ($Server) { $getParams['Server'] = $Server }
        $adUser = Get-ADUser @getParams -ErrorAction Stop

        # Build attribute updates
        $setMap = @{
            Department    = $u.Department
            Title         = $u.Title
            Office        = $u.Office
            OfficePhone   = $u.TelephoneNumber
            EmailAddress  = $u.Email
            Company       = $u.Company
            EmployeeID    = $u.EmployeeID
        }
        # If Email blank but UPN exists, set mail to UPN
        if ((-not $setMap.EmailAddress) -and $upn) { $setMap.EmailAddress = $upn }

        $nonEmpty = @{}
        foreach ($kv in $setMap.GetEnumerator()) {
            if ($kv.Value -and $kv.Value.ToString().Trim().Length -gt 0) {
                $nonEmpty[$kv.Key] = $kv.Value
            }
        }

        if ($nonEmpty.Count -gt 0) {
            $setParams = @{ Identity = $adUser.DistinguishedName }
            if ($Server) { $setParams['Server'] = $Server }
            foreach ($k in $nonEmpty.Keys) { $setParams[$k] = $nonEmpty[$k] }
            if ($PSCmdlet.ShouldProcess("User '$sam'", "Set attributes: $($nonEmpty.Keys -join ', ')")) {
                Set-ADUser @setParams
                $updated++
                Write-Log "[$sam] Updated: $($nonEmpty.Keys -join ', ')"
            }
        }

        # HomeDirectory / HomeDrive / ProfilePath
        $homeDir  = $u.HomeDirectory
        $homeDrv  = $u.HomeDrive
        $profPath = $u.ProfilePath

        if ([string]::IsNullOrWhiteSpace($homeDir) -and $HomeShareRoot -and $sam) { $homeDir  = (Join-Path $HomeShareRoot $sam) }
        if ([string]::IsNullOrWhiteSpace($homeDrv)) { $homeDrv = $HomeDrive }
        if ([string]::IsNullOrWhiteSpace($profPath) -and $ProfileRoot -and $sam) { $profPath = (Join-Path $ProfileRoot $sam) }

        if ($homeDir) {
            $params = @{ Identity = $adUser }
            if ($Server) { $params['Server'] = $Server }
            if ($PSCmdlet.ShouldProcess("User '$sam'", "Set HomeDirectory=$homeDir")) {
                Set-ADUser @params -HomeDirectory $homeDir
                Write-Log "[$sam] HomeDirectory set: $homeDir"
            }
        }
        if ($homeDrv) {
            $params = @{ Identity = $adUser }
            if ($Server) { $params['Server'] = $Server }
            if ($PSCmdlet.ShouldProcess("User '$sam'", "Set HomeDrive=$homeDrv")) {
                Set-ADUser @params -HomeDrive $homeDrv
                Write-Log "[$sam] HomeDrive set: $homeDrv"
            }
        }
        if ($profPath) {
            $params = @{ Identity = $adUser }
            if ($Server) { $params['Server'] = $Server }
            if ($PSCmdlet.ShouldProcess("User '$sam'", "Set ProfilePath=$profPath")) {
                Set-ADUser @params -ProfilePath $profPath
                Write-Log "[$sam] ProfilePath set: $profPath"
            }
        }

        # Manager via SamAccountName
        if ($u.ManagerSamAccountName -and $u.ManagerSamAccountName.ToString().Trim().Length -gt 0) {
            $mgrSam = $u.ManagerSamAccountName.ToString().Trim()
            $mgrParams = @{ Filter = "SamAccountName -eq '$mgrSam'" }
            if ($Server) { $mgrParams['Server'] = $Server }
            $mgr = Get-ADUser @mgrParams -ErrorAction SilentlyContinue
            if ($mgr) {
                $params = @{ Identity = $adUser.DistinguishedName; Manager = $mgr.DistinguishedName }
                if ($Server) { $params['Server'] = $Server }
                if ($PSCmdlet.ShouldProcess("User '$sam'", "Set Manager=$mgrSam")) {
                    Set-ADUser @params
                    Write-Log "[$sam] Manager set: $mgrSam"
                }
            } else {
                Write-Log "[$sam] WARNING: Manager '$mgrSam' not found." "WARN"
            }
        }

        # ProxyAddresses (multi-valued)
        if ($u.ProxyAddresses -and $u.ProxyAddresses.ToString().Trim().Length -gt 0) {
            $addresses = $u.ProxyAddresses.ToString().Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
            $current = @($adUser.ProxyAddresses)
            $toAdd = @($addresses | Where-Object { $current -notcontains $_ })
            if ($toAdd.Count -gt 0) {
                $params = @{ Identity = $adUser }
                if ($Server) { $params['Server'] = $Server }
                if ($PSCmdlet.ShouldProcess("User '$sam'", "Add proxyAddresses: $($toAdd -join ', ')")) {
                    Set-ADUser @params -Add @{ proxyAddresses = $toAdd }
                    Write-Log "[$sam] ProxyAddresses added: $($toAdd -join ', ')"
                }
            } else {
                Write-Log "[$sam] ProxyAddresses already present; no changes."
            }
        }

        # Groups
        if ($u.Groups -and $u.Groups.ToString().Trim().Length -gt 0) {
            $groupList = $u.Groups.ToString().Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
            foreach ($g in $groupList) {
                $grpParams = @{ Filter = "Name -eq '$g'" }
                if ($Server) { $grpParams['Server'] = $Server }
                $grp = Get-ADGroup @grpParams -ErrorAction SilentlyContinue

                if (-not $grp) {
                    if ($CreateMissingGroups) {
                        $grpOU = if ($DefaultOU) { $DefaultOU } else { $ou }
                        $newGrpParams = @{
                            Name           = $g
                            GroupScope     = 'Global'
                            GroupCategory  = 'Security'
                            Path           = $grpOU
                            SamAccountName = $g
                        }
                        if ($Server) { $newGrpParams['Server'] = $Server }
                                                if ($PSCmdlet.ShouldProcess("Group '$g'", "Create in $grpOU")) {
                                                    New-ADGroup @newGrpParams
                                                    $grp = Get-ADGroup @grpParams -ErrorAction Stop
                                                    Write-Log "[$sam] Created group '$g' in $grpOU"
                                                }
                                            } else {
                                                Write-Log "[$sam] Group '$g' not found and -CreateMissingGroups not set." "WARN"
                                            }
                                        }
                        
                                        # Add user to group
                                        if ($grp) {
                                            $params = @{ Identity = $grp.DistinguishedName; Members = @($adUser.DistinguishedName) }
                                            if ($Server) { $params['Server'] = $Server }
                                            if ($PSCmdlet.ShouldProcess("Group '$g'", "Add member '$sam'")) {
                                                Add-ADGroupMember @params -ErrorAction SilentlyContinue
                                                $groupAdds++
                                                Write-Log "[$sam] Added to group: $g"
                                            }
                                        }
                                    }
                                }
                        
                            } catch {
                                $errors++
                                Write-Log "[$sam] ERROR: $_" "ERROR"
                            }
                        }
                        
                        # Summary
                        Write-Log ""
                        Write-Log "============== IMPORT SUMMARY =============="
                        Write-Log "Created users: $created"
                        Write-Log "Updated users: $updated"
                        Write-Log "Group additions: $groupAdds"
                        Write-Log "Errors: $errors"
                        Write-Log "Log saved to: $LogPath"
