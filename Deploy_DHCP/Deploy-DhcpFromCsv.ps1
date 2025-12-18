# ============================
# PowerShell Script to Deploy DHCP Scopes from CSV
# ============================
<#
Written by Shawn Tooley, Seifert Technologies 
.SYNOPSIS
Deploy DHCP scopes, exclusions, reservations, and options from CSV files.
.DESCRIPTION
Version 1.0 - Updated 12/18/2025
This script reads DHCP scope configurations from CSV files and applies them to a DHCP server using the DhcpServer module. It supports creating scopes, adding exclusions, reservations, and setting server and scope options.
#>
# Configure PowerCLI to ignore certificate warnings
param(
    [string]$ScopesCsv         = ".\scopes.csv",
    [string]$ExclusionsCsv     = ".\exclusions.csv",
    [string]$ReservationsCsv   = ".\reservations.csv",
    [string]$ServerOptionsCsv  = ".\server-options.csv",
    [string]$ScopeOptionsCsv   = ".\scope-options.csv",
    [switch]$WhatIf             # dry-run mode
)

Import-Module DhcpServer

function Split-List($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return @() }
    return ($s -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ }
}

function Ensure-Scope {
    param(
        [string]$Name,
        [string]$ScopeId,
        [string]$StartRange,
        [string]$EndRange,
        [string]$SubnetMask,
        [string]$State,
        [Nullable[int]]$LeaseDays
    )

    $existing = Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-Host "Creating scope $Name ($ScopeId)..." -ForegroundColor Cyan
        $lease = if ($LeaseDays) { New-TimeSpan -Days $LeaseDays } else { New-TimeSpan -Days 8 } # default 8 days
        if ($WhatIf) {
            Write-Host "WhatIf: Add-DhcpServerv4Scope -Name $Name -ScopeId $ScopeId -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -LeaseDuration $lease -State $State"
        } else {
            Add-DhcpServerv4Scope -Name $Name -ScopeId $ScopeId -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -LeaseDuration $lease -State $State
        }
    } else {
        Write-Host "Scope $ScopeId already exists. Skipping create." -ForegroundColor Yellow
        # You can update properties here if needed
    }
}

function Set-ServerOptions {
    param(
        [string]$DnsServers,
        [string]$DnsDomain,
        [string]$Router
    )
    $dns = Split-List $DnsServers
    if ($dns.Count -gt 0) {
        Write-Host "Setting SERVER DNS: $($dns -join ', ')" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -DnsServer $dns"
        } else {
            Set-DhcpServerv4OptionValue -DnsServer $dns
        }
    }
    if ($DnsDomain) {
        Write-Host "Setting SERVER DNS domain: $DnsDomain" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -DnsDomain $DnsDomain"
        } else {
            Set-DhcpServerv4OptionValue -DnsDomain $DnsDomain
        }
    }
    if ($Router) {
        Write-Host "Setting SERVER Router (Option 3): $Router" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -Router $Router"
        } else {
            Set-DhcpServerv4OptionValue -Router $Router
        }
    }
}

function Set-ScopeOptions {
    param(
        [string]$ScopeId,
        [string]$DnsServers,
        [string]$DnsDomain,
        [string]$Router
    )
    $dns = Split-List $DnsServers
    if ($dns.Count -gt 0) {
        Write-Host "Setting SCOPE $ScopeId DNS: $($dns -join ', ')" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsServer $dns"
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsServer $dns
        }
    }
    if ($DnsDomain) {
        Write-Host "Setting SCOPE $ScopeId DNS domain: $DnsDomain" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsDomain $DnsDomain"
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $ScopeId -DnsDomain $DnsDomain
        }
    }
    if ($Router) {
        Write-Host "Setting SCOPE $ScopeId Router (Option 3): $Router" -ForegroundColor Green
        if ($WhatIf) {
            Write-Host "WhatIf: Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router"
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router
        }
    }
}

function Add-ExclusionsFromCsv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $rows = Import-Csv $Path
    foreach ($r in $rows) {
        $exists = Get-DhcpServerv4ExclusionRange -ScopeId $r.ScopeId -ErrorAction SilentlyContinue |
                  Where-Object { $_.StartRange -eq $r.StartRange -and $_.EndRange -eq $r.EndRange }
        if ($exists) {
            Write-Host "Exclusion $($r.ScopeId): $($r.StartRange)-$($r.EndRange) already exists." -ForegroundColor Yellow
            continue
        }
        Write-Host "Adding exclusion on $($r.ScopeId): $($r.StartRange) - $($r.EndRange)" -ForegroundColor Cyan
        if ($WhatIf) {
            Write-Host "WhatIf: Add-DhcpServerv4ExclusionRange -ScopeId $($r.ScopeId) -StartRange $($r.StartRange) -EndRange $($r.EndRange)"
        } else {
            Add-DhcpServerv4ExclusionRange -ScopeId $r.ScopeId -StartRange $r.StartRange -EndRange $r.EndRange
        }
    }
}

function Add-ReservationsFromCsv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $rows = Import-Csv $Path
    foreach ($r in $rows) {
        $exists = Get-DhcpServerv4Reservation -ScopeId $r.ScopeId -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -eq $r.IPAddress -and $_.ClientId -eq $r.MAC }
        if ($exists) {
            Write-Host "Reservation $($r.ScopeId): $($r.IPAddress) for $($r.MAC) already exists." -ForegroundColor Yellow
            continue
        }
        Write-Host "Adding reservation on $($r.ScopeId): $($r.IPAddress) for $($r.MAC) ($($r.Name))" -ForegroundColor Cyan
        if ($WhatIf) {
            Write-Host "WhatIf: Add-DhcpServerv4Reservation -ScopeId $($r.ScopeId) -IPAddress $($r.IPAddress) -ClientId $($r.MAC) -Name $($r.Name) -Description $($r.Description)"
        } else {
            Add-DhcpServerv4Reservation -ScopeId $r.ScopeId -IPAddress $r.IPAddress -ClientId $r.MAC -Name $r.Name -Description $r.Description
        }
    }
}

# 1) Create/ensure scopes
if (Test-Path $ScopesCsv) {
    $scopes = Import-Csv $ScopesCsv
    foreach ($s in $scopes) {
        Ensure-Scope -Name $s.ScopeName -ScopeId $s.ScopeId -StartRange $s.StartRange -EndRange $s.EndRange `
                     -SubnetMask $s.SubnetMask -State $s.State -LeaseDays ([int]$s.LeaseDays)

        # Per-scope options from scopes.csv itself
        Set-ScopeOptions -ScopeId $s.ScopeId -DnsServers $s.DnsServers -DnsDomain $s.DnsDomain -Router $s.Router
    }
} else {
    Write-Warning "Scopes CSV not found at $ScopesCsv"
}

# 2) Server-wide options (optional)
if (Test-Path $ServerOptionsCsv) {
    $srv = Import-Csv $ServerOptionsCsv | Select-Object -First 1
    Set-ServerOptions -DnsServers $srv.DnsServers -DnsDomain $srv.DnsDomain -Router $srv.Router
}

# 3) Additional per-scope options (optional)
if (Test-Path $ScopeOptionsCsv) {
    $so = Import-Csv $ScopeOptionsCsv
    foreach ($row in $so) {
        Set-ScopeOptions -ScopeId $row.ScopeId -DnsServers $row.DnsServers -DnsDomain $row.DnsDomain -Router $row.Router
    }
}

# 4) Exclusions (optional)
Add-ExclusionsFromCsv -Path $ExclusionsCsv

# 5) Reservations (optional)
Add-ReservationsFromCsv -Path $ReservationsCsv

Write-Host "`nDone." -ForegroundColor Green

# Verification suggestions
Write-Host "Verify scopes: Get-DhcpServerv4Scope"
Write-Host "Verify options: Get-DhcpServerv4OptionValue"
