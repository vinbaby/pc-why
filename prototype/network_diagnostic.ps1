# PC WHY? - No Internet diagnostic + safe repair prototype
# Repairs are intentionally limited to confirmed DNS and DHCP/IP failure paths.

$ErrorActionPreference = 'SilentlyContinue'
$results = @()

function Result($check, $status, $detail) {
    [PSCustomObject]@{ Check=$check; Status=$status; Detail=$detail }
}

function Save-Report([string]$summary) {
    $reportPath = Join-Path $env:USERPROFILE 'Desktop\PC-WHY-network-report.txt'
    @('PC WHY? - Network Diagnostic Report',('Generated: '+(Get-Date)),'',($script:results|Format-Table -AutoSize|Out-String),'',('Summary: '+$summary)) | Set-Content $reportPath -Encoding UTF8
    return $reportPath
}
function Show-Results([string]$summary,[ConsoleColor]$color='Yellow') {
    Write-Host ''; Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host 'PC WHY? - NETWORK DIAGNOSTIC' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    $script:results|Format-Table -AutoSize|Out-String|Write-Host; Write-Host $summary -ForegroundColor $color
}
function Finish-Diagnostic([int]$code,[string]$summary) {
    Show-Results $summary; $p=Save-Report $summary; Write-Host ''; Write-Host ('Report saved to: '+$p) -ForegroundColor Green; Write-Host ''; Read-Host 'Press ENTER to close'; exit $code
}
function Test-DnsNow { return ($null -ne (Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly)) }
function Get-ValidIPv4([int]$interfaceIndex) {
    $ip=(Get-NetIPConfiguration -InterfaceIndex $interfaceIndex).IPv4Address|Select-Object -First 1
    if(-not $ip -or $ip.IPAddress -like '169.254.*'){return $null}; return $ip.IPAddress
}
function Test-TcpInternet {
    foreach($target in @(@('1.1.1.1',443),@('8.8.8.8',53))){
        if(Test-NetConnection -ComputerName $target[0] -Port $target[1] -InformationLevel Quiet -WarningAction SilentlyContinue){return $true}
    }
    return $false
}
function Repair-DhcpIp([string]$interfaceAlias,[int]$interfaceIndex) {
    $ipi=Get-NetIPInterface -InterfaceIndex $interfaceIndex -AddressFamily IPv4
    if(-not $ipi -or $ipi.Dhcp -ne 'Enabled'){$script:results+=Result 'DHCP repair' 'STOP' 'DHCP is not enabled; manual/static IP will not be changed.'; Finish-Diagnostic 21 'Invalid IP, but automatic repair stopped to protect a manual network configuration.'}
    Write-Host ''; Write-Host 'PC WHY? - PROPOSED DHCP/IP FIX' -ForegroundColor Cyan
    Write-Host 'Detected: DHCP is enabled, but Windows has no valid IPv4 address.'
    Write-Host 'Will: renew DHCP lease, wait, then verify a non-APIPA IPv4 address.'
    Write-Host 'Will NOT: overwrite static IP, replace drivers, or make unrelated changes.'
    Write-Host 'Risk: LOW (network may disconnect briefly)' -ForegroundColor Green
    if((Read-Host 'Apply this fix? [Y/N]') -notmatch '^[Yy]$'){Finish-Diagnostic 20 'DHCP/IP failure confirmed. User declined repair.'}
    $nic=Get-CimInstance Win32_NetworkAdapterConfiguration|Where-Object{$_.InterfaceIndex -eq $interfaceIndex}|Select-Object -First 1
    if($nic){Invoke-CimMethod -InputObject $nic -MethodName RenewDHCPLease|Out-Null}; Start-Sleep 5
    $newIp=Get-ValidIPv4 $interfaceIndex
    if($newIp){$script:results+=Result 'DHCP repair' 'FIXED' ("Valid IPv4 assigned after DHCP renewal: {0}" -f $newIp); Finish-Diagnostic 0 'FIXED: Windows received a valid IPv4 address again.'}
    $script:results+=Result 'DHCP repair' 'FAIL' 'No valid IPv4 obtained after DHCP renewal.'; Finish-Diagnostic 22 'NOT FIXED: DHCP renewal did not restore a valid IPv4 address.'
}
function Repair-Dns([string]$interfaceAlias) {
    Write-Host ''; Write-Host 'PC WHY? - PROPOSED DNS FIX' -ForegroundColor Cyan
    Write-Host 'Detected: Internet IP reachability works, but DNS lookup fails.'
    Write-Host 'Will: reset DNS to Windows/DHCP defaults, flush cache, then verify.'
    Write-Host 'Risk: LOW' -ForegroundColor Green
    if((Read-Host 'Apply this fix? [Y/N]') -notmatch '^[Yy]$'){Finish-Diagnostic 50 'DNS failure confirmed. User declined repair.'}
    Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ResetServerAddresses; Clear-DnsClientCache; Start-Sleep 2
    if(Test-DnsNow){$script:results+=Result 'DNS repair' 'FIXED' 'DNS lookup succeeded after reset + cache flush.'; Finish-Diagnostic 0 'FIXED: DNS resolution is working again.'}
    $script:results+=Result 'DNS repair' 'FAIL' 'DNS still fails after safe repair.'; Finish-Diagnostic 51 'NOT FIXED: DNS is still failing. PC WHY? stopped instead of making riskier changes.'
}

# 1) Active physical adapter
$adapter=Get-NetAdapter -Physical|Where-Object{$_.Status -eq 'Up'}|Select-Object -First 1
if(-not $adapter){$results+=Result 'Network adapter' 'FAIL' 'No active physical network adapter detected.'; Finish-Diagnostic 10 'Likely fault: adapter/link is down or disconnected.'}
$results+=Result 'Network adapter' 'PASS' ("{0} is Up" -f $adapter.Name)

# 2) IPv4 / DHCP
$config=Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$ipv4=$config.IPv4Address|Select-Object -First 1
if(-not $ipv4 -or $ipv4.IPAddress -like '169.254.*'){$results+=Result 'IP configuration' 'FAIL' $(if($ipv4){"Invalid/APIPA IPv4 address: $($ipv4.IPAddress)"}else{'No IPv4 address assigned.'}); Show-Results 'Likely fault: IPv4 configuration / DHCP.'; Repair-DhcpIp $adapter.Name $adapter.ifIndex}
$results+=Result 'IP configuration' 'PASS' ("IPv4: {0}" -f $ipv4.IPAddress)

# 3) Gateway presence + reachability. A failed ping alone is not enough to blame the router.
$gateway=$config.IPv4DefaultGateway.NextHop
if(-not $gateway){$results+=Result 'Default gateway' 'FAIL' 'No IPv4 default gateway is configured.'; Finish-Diagnostic 30 'Likely fault: gateway configuration is missing. PC WHY? will not invent a gateway address.'}
$gwPing=Test-Connection -ComputerName $gateway -Count 1 -Quiet
if($gwPing){$results+=Result 'Default gateway' 'PASS' ("Gateway {0} responded" -f $gateway)}else{$results+=Result 'Default gateway' 'WARN' ("Gateway {0} did not answer ICMP; router may block ping." -f $gateway)}

# 4) Independent upstream probes: ICMP plus TCP, so ping blocking does not cause an immediate false diagnosis.
$ipPing=(Test-Connection '1.1.1.1' -Count 1 -Quiet) -or (Test-Connection '8.8.8.8' -Count 1 -Quiet)
$tcpInternet=Test-TcpInternet
if(-not $ipPing -and -not $tcpInternet){
    $results+=Result 'Internet reachability' 'FAIL' 'External IP probes failed by both ICMP and TCP.'
    if(-not $gwPing){
        $results+=Result 'Fault isolation' 'STOP' 'Gateway and upstream probes both failed. Possible router/link/upstream problem; no Windows reset attempted.'
        Finish-Diagnostic 41 'Likely fault domain: router, local link beyond the adapter, or upstream network. PC WHY? stopped because a Windows reset is not justified.'
    }
    $results+=Result 'Fault isolation' 'STOP' 'Gateway is reachable but upstream probes failed. Possible router WAN/ISP/upstream outage; no Windows reset attempted.'
    Finish-Diagnostic 42 'Likely fault domain: router WAN / ISP / upstream Internet. The PC-to-router path works, so PC WHY? will not reset Windows networking.'
}
$results+=Result 'Internet reachability' 'PASS' $(if($ipPing -and $tcpInternet){'External connectivity confirmed by ICMP and TCP.'}elseif($tcpInternet){'External TCP connectivity works; ICMP appears blocked.'}else{'External IP ping works; TCP probes did not respond.'})

# 5) DNS
if(-not (Test-DnsNow)){$results+=Result 'DNS resolution' 'FAIL' 'Internet IP reachability works, but DNS lookup failed.'; Show-Results 'Likely fault: DNS resolution.'; Repair-Dns $adapter.Name}
$results+=Result 'DNS resolution' 'PASS' 'DNS lookup succeeded.'
Finish-Diagnostic 0 'No fault was detected in this network path.'
