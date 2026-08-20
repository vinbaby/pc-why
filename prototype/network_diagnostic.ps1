# PC WHY? - No Internet diagnostic prototype
# Phase 1 is intentionally READ-ONLY: this script does not change Windows settings.

$ErrorActionPreference = 'SilentlyContinue'
$results = @()
$exitCode = 0

function Result($check, $status, $detail) {
    [PSCustomObject]@{
        Check  = $check
        Status = $status
        Detail = $detail
    }
}

function Finish-Diagnostic([int]$code, [string]$summary) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host 'PC WHY? - NETWORK DIAGNOSTIC' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    $script:results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host $summary -ForegroundColor Yellow

    $reportPath = Join-Path $env:USERPROFILE 'Desktop\PC-WHY-network-report.txt'
    $report = @()
    $report += 'PC WHY? - Network Diagnostic Report'
    $report += ('Generated: ' + (Get-Date))
    $report += ''
    $report += ($script:results | Format-Table -AutoSize | Out-String)
    $report += ''
    $report += ('Summary: ' + $summary)
    $report | Set-Content -Path $reportPath -Encoding UTF8

    Write-Host ''
    Write-Host ('Report saved to: ' + $reportPath) -ForegroundColor Green
    Write-Host ''
    Read-Host 'Press ENTER to close'
    exit $code
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
    Finish-Diagnostic 20 'Likely fault: IPv4 configuration / DHCP.'
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
    $results += Result 'Internet reachability' 'FAIL' 'Could not reach either external IP probe. ICMP filtering can cause false negatives; a later prototype will add TCP/HTTP probes.'
    Finish-Diagnostic 40 'Likely fault: upstream Internet connectivity, or ICMP is blocked. More probes are needed before a repair is attempted.'
}
$results += Result 'Internet reachability' 'PASS' 'An external IP probe responded.'

# 5) Test DNS independently.
$dns = Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly
if (-not $dns) {
    $results += Result 'DNS resolution' 'FAIL' 'Internet IP reachability works, but DNS lookup failed. DNS is the likely fault domain.'
    Finish-Diagnostic 50 'Likely fault: DNS resolution.'
}
$results += Result 'DNS resolution' 'PASS' 'DNS lookup succeeded.'

Finish-Diagnostic 0 'No fault was detected in this basic network path.'
