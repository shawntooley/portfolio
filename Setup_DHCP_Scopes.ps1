# ============================
# DHCP Scope Setup Script
# ============================
<#
Written by Shawn Tooley, Seifert Technologies 
Version 1.0 - Updated 2025-12-08
This Script will setup the DHCP Scopes on the server fro a CSV file or inline definition.
#>
<# 
.SYNOPSIS
    Create/update DHCPv4 scopes with per-scope DNS servers and router.

.DESCRIPTION
    Validates inputs, computes ScopeId, creates scopes if missing,
    and sets option values (003 Router, 006 DNS Servers).

.PARAMETER DhcpServer
    DHCP server name or IP. Defaults to local computer.

.PARAMETER Scopes
    Array of hashtables with keys:
        Name, StartRange, EndRange, SubnetMask, Router, DnsServer (array), LeaseDuration (timespan string)
    OR import via -CsvPath.

.PARAMETER CsvPath
    Path to CSV file with columns:
        Name,StartRange,EndRange,SubnetMask,Router,DnsServer,LeaseDuration
    DnsServer should be semicolon-separated list (e.g., "10.0.150.11;10.0.150.12").

.PARAMETER DryRun
    If specified, performs validation and shows planned actions without applying changes.

.EXAMPLE
    .\Manage-DhcpScopes.ps1 -DhcpServer 'DHCP01' -DryRun

.EXAMPLE
    .\Manage-DhcpScopes.ps1 -CsvPath '.\scopes.csv'

.NOTES
    Requires DHCP Server module (Add-DhcpServerv4Scope, Set-DhcpServerv4OptionValue).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DhcpServer = $env:COMPUTERNAME,
    [Parameter(ParameterSetName='Inline', Mandatory=$false)]
    [array]$Scopes,
    [Parameter(ParameterSetName='Csv', Mandatory=$true)]
    [string]$CsvPath,
    [switch]$DryRun
)

function Write-Info { param([string]$Message) Write-Host "[INFO ] $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Write-Err  { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Test-IPv4 {
    param([string]$Address)
    try { [System.Net.IPAddress]::Parse($Address) | Out-Null; return ($Address -match '^\d{1,3}(\.\d{1,3}){3}$') }
    catch { return $false }
}

function Get-NetworkAddress {
    param([string]$Ip,[string]$Mask)
    $ipBytes   = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    $maskBytes = [System.Net.IPAddress]::Parse($Mask).GetAddressBytes()
    $netBytes  = for ($i=0; $i -lt 4; $i++) { $ipBytes[$i] -band $maskBytes[$i] }
    return ([System.Net.IPAddress]::new($netBytes)).ToString()
}

function Test-InRange {
    param([string]$TestIp,[string]$Start,[string]$End)
    $toInt = {
        param([string]$ip)
        ([System.Net.IPAddress]::Parse($ip).GetAddressBytes() |
            ForEach-Object { $_ }) -as [uint32[]] | ForEach-Object { $_ } | Out-Null
        # Convert to UInt32
        $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        [Array]::Reverse($bytes)
        [BitConverter]::ToUInt32($bytes,0)
    }
    $t = & $toInt $TestIp
    $s = & $toInt $Start
    $e = & $toInt $End
    return ($t -ge $s -and $t -le $e)
}

function Test-Scope {
    param([hashtable]$Scope)

    $errors = @()

    foreach ($key in 'Name','StartRange','EndRange','SubnetMask','Router','DnsServer','LeaseDuration') {
        if (-not $Scope.ContainsKey($key) -or -not $Scope.$key) {
            $errors += "Missing required field: $key"
        }
    }

    if ($Scope.StartRange -and -not (Test-IPv4 $Scope.StartRange)) { $errors += "Invalid StartRange: $($Scope.StartRange)" }
    if ($Scope.EndRange   -and -not (Test-IPv4 $Scope.EndRange))   { $errors += "Invalid EndRange: $($Scope.EndRange)" }
    if ($Scope.SubnetMask -and -not (Test-IPv4 $Scope.SubnetMask)) { $errors += "Invalid SubnetMask: $($Scope.SubnetMask)" }
    if ($Scope.Router     -and -not (Test-IPv4 $Scope.Router))     { $errors += "Invalid Router: $($Scope.Router)" }

    # DNS can be string or array; normalize to array
    $dnsList = @()
    if ($Scope.DnsServer -is [string]) {
        $dnsList = $Scope.DnsServer -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } elseif ($Scope.DnsServer -is [System.Collections.IEnumerable]) {
        $dnsList = @($Scope.DnsServer) | ForEach-Object { $_ } | Where-Object { $_ }
    } else {
        $errors += "DnsServer must be a string (semicolon-separated) or an array"
    }
    foreach ($dns in $dnsList) {
        if (-not (Test-IPv4 $dns)) { $errors += "Invalid DNS server IP: $dns" }
    }
    $Scope.DnsServer = $dnsList

    # LeaseDuration should parse to TimeSpan
    try { [TimeSpan]::Parse($Scope.LeaseDuration) | Out-Null }
    catch { $errors += "LeaseDuration must be a valid TimeSpan (e.g., 8.00:00:00). Value: $($Scope.LeaseDuration)" }

    # Ensure Start/End inside subnet and Start <= End
    if (-not $errors) {
        $netAddr = Get-NetworkAddress -Ip $Scope.StartRange -Mask $Scope.SubnetMask
        $Scope.ScopeId = $netAddr

        # Check Start/End order
        if (-not (Test-InRange -TestIp $Scope.StartRange -Start $Scope.StartRange -End $Scope.EndRange)) {
            # This check always true; replace with numeric comparison
            $toInt = {
                param([string]$ip)
                $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
                [Array]::Reverse($bytes)
                [BitConverter]::ToUInt32($bytes,0)
            }
            if ((& $toInt $Scope.StartRange) -gt (& $toInt $Scope.EndRange)) {
                $errors += "StartRange is greater than EndRange"
            }
        }

        # Verify Router and ranges are in same subnet
        $routerNet = Get-NetworkAddress -Ip $Scope.Router -Mask $Scope.SubnetMask
        if ($routerNet -ne $netAddr) { $errors += "Router $($Scope.Router) is not in the scope subnet ($netAddr/$($Scope.SubnetMask))" }
        $startNet = Get-NetworkAddress -Ip $Scope.StartRange -Mask $Scope.SubnetMask
        $endNet   = Get-NetworkAddress -Ip $Scope.EndRange   -Mask $Scope.SubnetMask
        if ($startNet -ne $netAddr -or $endNet -ne $netAddr) { $errors += "StartRange/EndRange must be in subnet $netAddr/$($Scope.SubnetMask)" }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors
        Scope   = $Scope
    }
}

function Import-DhcpModule {
    if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
        throw "DhcpServer module not found. Install RSAT: DHCP Server Tools or run on a DHCP server."
    }
    Import-Module DhcpServer -ErrorAction Stop
}

function Initialize-Scope {
    param([hashtable]$Scope,[string]$Server,[switch]$DryRun)

    $lease = [TimeSpan]::Parse($Scope.LeaseDuration)

    # Check if scope exists
    $existing = $null
    try {
        $existing = Get-DhcpServerv4Scope -ComputerName $Server -ScopeId $Scope.ScopeId -ErrorAction Stop
    } catch {
        $existing = $null
    }

    if (-not $existing) {
        if ($DryRun) {
            Write-Info "DRY-RUN: Would create scope '$($Scope.Name)' ($($Scope.ScopeId)) range $($Scope.StartRange)-$($Scope.EndRange) mask $($Scope.SubnetMask) lease $lease"
        } else {
            Write-Info "Creating scope '$($Scope.Name)' ($($Scope.ScopeId))"
            Add-DhcpServerv4Scope -ComputerName $Server `
                -Name $Scope.Name `
                -StartRange $Scope.StartRange -EndRange $Scope.EndRange `
                -SubnetMask $Scope.SubnetMask -LeaseDuration $lease -ErrorAction Stop
        }
    } else {
        Write-Info "Scope '$($Scope.Name)' ($($Scope.ScopeId)) already exists"
        # Optionally update lease duration (only if changed)
        if (-not $DryRun) {
            try {
                Set-DhcpServerv4Scope -ComputerName $Server -ScopeId $Scope.ScopeId -LeaseDuration $lease -ErrorAction Stop
            } catch {
                Write-Warn "Failed to update lease duration on $($Scope.ScopeId): $($_.Exception.Message)"
            }
        } else {
            Write-Info "DRY-RUN: Would update lease duration to $lease"
        }
    }

    # Set options 003 and 006
    if ($DryRun) {
        Write-Info "DRY-RUN: Would set Router=$($Scope.Router) and DnsServer=@($($Scope.DnsServer -join ', ')) on $($Scope.ScopeId)"
    } else {
        Write-Info "Setting router and DNS servers on $($Scope.ScopeId)"
        try {
            # Set both in one call; Set-DhcpServerv4OptionValue merges/overwrites as needed
            Set-DhcpServerv4OptionValue -ComputerName $Server -ScopeId $Scope.ScopeId `
                -Router $Scope.Router -DnsServer $Scope.DnsServer -ErrorAction Stop
        } catch {
            Write-Err "Failed to set option values on $($Scope.ScopeId): $($_.Exception.Message)"
            throw
        }
    }
}

# --------- Main ---------
try {
    Ensure-DhcpModule
    Write-Info "Target DHCP Server: $DhcpServer"

    if ($PSCmdlet.ParameterSetName -eq 'Csv') {
        if (-not (Test-Path -Path $CsvPath)) { throw "CSV not found: $CsvPath" }
        Write-Info "Loading scopes from CSV: $CsvPath"
        $csv = Import-Csv -Path $CsvPath
        $Scopes = @()
        foreach ($row in $csv) {
            $Scopes += @{
                Name         = $row.Name
                StartRange   = $row.StartRange
                EndRange     = $row.EndRange
                SubnetMask   = $row.SubnetMask
                Router       = $row.Router
                DnsServer    = $row.DnsServer  # semicolon-separated; validator normalizes
                LeaseDuration= $row.LeaseDuration
            }
        }
    } elseif (-not $Scopes) {
        # Example inline scopes (edit/remove as needed)
        Write-Warn "No scopes provided; using example inline definition. Replace with your data."
        $Scopes = @(
            @{
                Name = "Default_Scope"
                StartRange = "192.168.1.110"
                EndRange = "192.168.1.210"
                SubnetMask = "255.255.255.0"
                Router = "192.168.1.99"
                DnsServer = @('10.0.150.11','10.0.150.12')
                LeaseDuration = "8.00:00:00"
            },
            @{
                Name = "Secondary_Scope"
                StartRange = "192.168.2.50"
                EndRange = "192.168.2.150"
                SubnetMask = "255.255.255.0"
                Router = "192.168.2.1"
                DnsServer = @('8.8.8.8','8.8.4.4')
                LeaseDuration = "8.00:00:00"
            }
        )
    }

    $results = @()
    foreach ($s in $Scopes) {
        Write-Host "`n--- Processing: $($s.Name) ---" -ForegroundColor Gray
        $val = Validate-Scope -Scope $s
        if (-not $val.IsValid) {
            Write-Err "Validation failed for '$($s.Name)':"
            $val.Errors | ForEach-Object { Write-Err " - $_" }
            $results += [pscustomobject]@{ Name=$s.Name; ScopeId=$s.ScopeId; Status='Invalid'; Details=($val.Errors -join '; ') }
            continue
        }

        try {
            Apply-Scope -Scope $val.Scope -Server $DhcpServer -DryRun:$DryRun
            $results += [pscustomobject]@{ Name=$val.Scope.Name; ScopeId=$val.Scope.ScopeId; Status=($DryRun ? 'DryRun' : 'Applied'); Details='OK' }
        } catch {
            $results += [pscustomobject]@{ Name=$val.Scope.Name; ScopeId=$val.Scope.ScopeId; Status='Error'; Details=$_.Exception.Message }
        }
    }

    Write-Host "`nSummary:" -ForegroundColor Green
    $results | Format-Table -AutoSize

} catch {
    Write-Err "Fatal error: $($_.Exception.Message)"
    exit 1
}
