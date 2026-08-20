# PC WHY? - No Internet diagnostic + safe repair prototype
# Repairs are intentionally limited to confirmed DNS and DHCP/IP failure paths.

$ErrorActionPreference = 'SilentlyContinue'
$results = @()

function Result($check, $status, $detail) {
    [PSCustomObject]@{
        Check  = $check
        Status = $status
        Detail = $detail
    }
}

function Save-Report([string]$summary) {
    $reportPath = Join-Path $env:USERPROFILE 'Desktop\PC-WHY-network-report.txt'
    $report = @()
    $report += 'PC WHY? - Network Diagnostic Report'
    $report += ('Generated: ' + (Get-Date))
    $report += ''
    $report += ($script:results | Format-Table -AutoSize | Out-String)
    $report += ''
    $report += ('Summary: ' + $summary)
    $report | Set-Content -Path $reportPath -Encoding UTF8
    return $reportPath
}

function Show-Results([string]$summary, [ConsoleColor]$color = 'Yellow') {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host 'PC WHY? - NETWORK DIAGNOSTIC' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    $script:results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host $summary -ForegroundColor $color
}

function Finish-Diagnostic([int]$code, [string]$summary) {
    Show-Results $summary
    $reportPath = Save-Report $summary
    Write-Host ''
    Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
    Write-Host ''
    Read-Host 'Press ENTER to close'
    exit $code
}

function Test-DnsNow {
    $dns = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly
    return ($null -ne $dns)
}

function Get-ValidIPv4([int]$interfaceIndex) {
    $cfg = Get-NetIPConfiguration -InterfaceIndex $interfaceIndex
    $ip = $cfg.IPv4Address | Select-Object -First 1
    if (-not $ip) { return $null }
    if ($ip.IPAddress -like '169.254.*') { return $null }
    return $ip.IPAddress
}

function Repair-DhcpIp([string]$interfaceAlias, [int]$interfaceIndex) {
    $ipInterface = Get-NetIPInterface -InterfaceIndex $interfaceIndex -AddressFamily IPv4

    # Never overwrite a static-IP configuration automatically.
    if (-not $ipInterface -or $ipInterface.Dhcp -ne 'Enabled') {
        $script:results += Result 'DHCP repair' 'STOP' 'IPv4 DHCP is not enabled. PC WHY? will not overwrite a static/manual IP configuration.'
        Finish-Diagnostic 21 'IP configuration is invalid, but this adapter is not using DHCP. Automatic repair was stopped to avoid changing a manual network setup.'
    }

    Write-Host ''
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host 'PC WHY? - PROPOSED DHCP/IP FIX' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host 'Detected: This adapter is using DHCP, but it has no valid IPv4 address.'
    Write-Host ''
    Write-Host 'PC WHY? will:' -ForegroundColor White
    Write-Host '  1. Ask Windows DHCP to renew the IPv4 lease for this adapter.'
    Write-Host '  2. Wait briefly for a new address.'
    Write-Host '  3. Verify that a non-APIPA IPv4 address was assigned.'
    Write-Host ''
    Write-Host 'PC WHY? will NOT:' -ForegroundColor White
    Write-Host '  - Change a static/manual IP configuration'
    Write-Host '  - Replace network drivers'
    Write-Host '  - Modify unrelated Registry settings'
    Write-Host '  - Delete personal files'
    Write-Host ''
    Write-Host 'Risk: LOW (network may disconnect briefly)' -ForegroundColor Green
    Write-Host ''

    $choice = Read-Host 'Apply this fix? [Y/N]'
    if ($choice -notmatch '^[Yy]$') {
        Finish-Diagnostic 20 'DHCP/IP failure confirmed. User declined repair.'
    }

    Write-Host ''
    Write-Host 'Requesting a fresh DHCP lease...' -ForegroundColor Cyan

    # Use Windows' DHCP lease renewal method on the matching interface.
    $nicConfig = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $interfaceIndex } | Select-Object -First 1
    if ($nicConfig) {
        Invoke-CimMethod -InputObject $nicConfig -MethodName RenewDHCPLease | Out-Null
    }

    Start-Sleep -Seconds 5
    Write-Host 'Verifying...' -ForegroundColor Cyan

    $newIp = Get-ValidIPv4 $interfaceIndex
    if ($newIp) {
        $script:results += Result 'DHCP repair' 'FIXED' ("Valid IPv4 assigned after DHCP renewal: {0}" -f $newIp)
        Show-Results 'FIXED: Windows received a valid IPv4 address again.' 'Green'
        $reportPath = Save-Report 'FIXED: DHCP renewal restored a valid IPv4 address.'
        Write-Host ''
        Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
        Write-Host ''
        Read-Host 'Press ENTER to close'
        exit 0
    }

    $script:results += Result 'DHCP repair' 'FAIL' 'No valid IPv4 address was obtained after the safe DHCP renewal attempt.'
    Show-Results 'NOT FIXED: Windows still has no valid IPv4 address. PC WHY? stopped instead of making broader network changes.' 'Red'
    $reportPath = Save-Report 'NOT FIXED: DHCP renewal did not restore a valid IPv4 address.'
    Write-Host ''
    Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
    Write-Host ''
    Read-Host 'Press ENTER to close'
    exit 22
}

function Repair-Dns([string]$interfaceAlias) {
    Write-Host ''
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host 'PC WHY? - PROPOSED DNS FIX' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host 'Detected: Internet IP reachability works, but DNS lookup fails.'
    Write-Host ''
    Write-Host 'PC WHY? will:' -ForegroundColor White
    Write-Host '  1. Reset DNS servers for this adapter to Windows/DHCP defaults.'
    Write-Host '  2. Flush the local DNS cache.'
    Write-Host '  3. Run the DNS test again.'
    Write-Host ''
    Write-Host 'PC WHY? will NOT:' -ForegroundColor White
    Write-Host '  - Replace network drivers'
    Write-Host '  - Modify unrelated Registry settings'
    Write-Host '  - Delete personal files'
    Write-Host ''
    Write-Host 'Risk: LOW' -ForegroundColor Green
    Write-Host ''

    $choice = Read-Host 'Apply this fix? [Y/N]'
    if ($choice -notmatch '^[Yy]$') {
        Finish-Diagnostic 50 'DNS failure confirmed. User declined repair.'
    }

    Write-Host ''
    Write-Host 'Applying DNS repair...' -ForegroundColor Cyan
    Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ResetServerAddresses
    Clear-DnsClientCache
    Start-Sleep -Seconds 2

    Write-Host 'Verifying...' -ForegroundColor Cyan
    if (Test-DnsNow) {
        $script:results += Result 'DNS repair' 'FIXED' 'DNS lookup succeeded after reset + cache flush.'
        Show-Results 'FIXED: DNS resolution is working again.' 'Green'
        $reportPath = Save-Report 'FIXED: DNS resolution is working again.'
        Write-Host ''
        Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
        Write-Host ''
        Read-Host 'Press ENTER to close'
        exit 0
    }

    $script:results += Result 'DNS repair' 'FAIL' 'DNS still fails after the safe repair attempt.'
    Show-Results 'NOT FIXED: DNS is still failing. PC WHY? stopped instead of making riskier changes.' 'Red'
    $reportPath = Save-Report 'NOT FIXED: DNS is still failing after the safe repair attempt.'
    Write-Host ''
    Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
    Write-Host ''
    Read-Host 'Press ENTER to close'
    exit 51
}

# 1) Find an active physical network adapter.
$adapter = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
if (-not $adapter) {
    $results += Result 'Network adapter' 'FAIL' 'No active physical network adapter was detected.'
    Finish-Diagnostic 10 'Likely fault: no active physical network adapter.'
}
$results += Result 'Network adapter' 'PASS' ("{0} is Up" -f $adapter.Name)

# 2) Inspect IPv4 configuration on that adapter.
$config = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$ipv4 = $config.IPv4Address | Select-Object -First 1
if (-not $ipv4 -or $ipv4.IPAddress -like '169.254.*') {
    $detail = if ($ipv4) { "Invalid/APIPA IPv4 address: $($ipv4.IPAddress)" } else { 'No IPv4 address assigned.' }
    $results += Result 'IP configuration' 'FAIL' $detail
    Show-Results 'Likely fault: IPv4 configuration / DHCP.'
    Repair-DhcpIp $adapter.Name $adapter.ifIndex
}
$results += Result 'IP configuration' 'PASS' ("IPv4: {0}" -f $ipv4.IPAddress)

# 3) Verify the default gateway.
$gateway = $config.IPv4DefaultGateway.NextHop
if (-not $gateway) {
    $results += Result 'Default gateway' 'FAIL' 'No IPv4 default gateway is configured.'
    Finish-Diagnostic 30 'Likely fault: no default gateway is configured.'
}

$gatewayReachable = Test-Connection -ComputerName $gateway -Count 1 -Quiet
if (-not $gatewayReachable) {
    $results += Result 'Default gateway' 'WARN' ("Gateway {0} did not answer ICMP. Some routers block ping, so this is not treated as conclusive failure." -f $gateway)
} else {
    $results += Result 'Default gateway' 'PASS' ("Gateway {0} responded" -f $gateway)
}

# 4) Test Internet reachability without depending on DNS.
$internetReachable = (Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet) -or (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet)
if (-not $internetReachable) {
    $results += Result 'Internet reachability' 'FAIL' 'Could not reach either external IP probe. ICMP filtering can cause false negatives; no repair is attempted yet.'
    Finish-Diagnostic 40 'Likely fault: upstream Internet connectivity, or ICMP is blocked. More probes are needed before a repair is attempted.'
}
$results += Result 'Internet reachability' 'PASS' 'An external IP probe responded.'

# 5) Test DNS independently.
if (-not (Test-DnsNow)) {
    $results += Result 'DNS resolution' 'FAIL' 'Internet IP reachability works, but DNS lookup failed. DNS is the likely fault domain.'
    Show-Results 'Likely fault: DNS resolution.'
    Repair-Dns $adapter.Name
}
$results += Result 'DNS resolution' 'PASS' 'DNS lookup succeeded.'

Finish-Diagnostic 0 'No fault was detected in this basic network path.'
