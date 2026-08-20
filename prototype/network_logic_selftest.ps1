# PC WHY? - Network decision logic self-test
# SAFE: this script does not change network settings.

$ErrorActionPreference = 'Stop'

function Classify-NetworkState {
    param(
        [bool]$AdapterUp,
        [bool]$HasValidIPv4,
        [bool]$HasGateway,
        [bool]$GatewayPing,
        [bool]$InternetPing,
        [bool]$InternetTcp,
        [bool]$DnsWorks
    )

    if (-not $AdapterUp) { return 'ADAPTER_DOWN' }
    if (-not $HasValidIPv4) { return 'DHCP_OR_IP' }
    if (-not $HasGateway) { return 'GATEWAY_MISSING' }

    $internetWorks = $InternetPing -or $InternetTcp

    if (-not $internetWorks) {
        if (-not $GatewayPing) { return 'ROUTER_LINK_OR_UPSTREAM' }
        return 'ROUTER_WAN_OR_ISP'
    }

    if (-not $DnsWorks) { return 'DNS' }
    if (-not $GatewayPing -and $internetWorks) { return 'HEALTHY_ICMP_BLOCKED' }
    return 'HEALTHY'
}

$tests = @(
    @{Name='Healthy';                  Expected='HEALTHY';                 Args=@($true,$true,$true,$true,$true,$true,$true)},
    @{Name='Router blocks ping';       Expected='HEALTHY_ICMP_BLOCKED';    Args=@($true,$true,$true,$false,$false,$true,$true)},
    @{Name='DNS failure';              Expected='DNS';                     Args=@($true,$true,$true,$true,$true,$true,$false)},
    @{Name='DHCP/IP failure';          Expected='DHCP_OR_IP';              Args=@($true,$false,$true,$false,$false,$false,$false)},
    @{Name='Gateway missing';          Expected='GATEWAY_MISSING';         Args=@($true,$true,$false,$false,$false,$false,$false)},
    @{Name='Gateway reachable, WAN down'; Expected='ROUTER_WAN_OR_ISP';    Args=@($true,$true,$true,$true,$false,$false,$false)},
    @{Name='Gateway and Internet down';   Expected='ROUTER_LINK_OR_UPSTREAM'; Args=@($true,$true,$true,$false,$false,$false,$false)},
    @{Name='Adapter down';             Expected='ADAPTER_DOWN';            Args=@($false,$false,$false,$false,$false,$false,$false)}
)

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host 'PC WHY? - NETWORK LOGIC SELF-TEST' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host 'SAFE MODE: no Windows network settings will be changed.' -ForegroundColor Green
Write-Host ''

$passed = 0
foreach ($t in $tests) {
    $actual = Classify-NetworkState @t.Args
    $ok = ($actual -eq $t.Expected)
    if ($ok) { $passed++ }
    [PSCustomObject]@{
        Scenario = $t.Name
        Expected = $t.Expected
        Actual   = $actual
        Result   = $(if ($ok) {'PASS'} else {'FAIL'})
    }
}

Write-Host ''
Write-Host ("Self-test result: {0}/{1} scenarios PASS" -f $passed,$tests.Count) -ForegroundColor $(if($passed -eq $tests.Count){'Green'}else{'Red'})
if ($passed -eq $tests.Count) {
    Write-Host 'Gateway/upstream decision logic passed all simulated cases.' -ForegroundColor Green
} else {
    Write-Host 'One or more decision paths failed. Do not trust the classifier yet.' -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press ENTER to close'
