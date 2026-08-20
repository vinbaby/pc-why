# PC WHY? - Controlled DHCP/IP failure test helper
# Purpose: temporarily release the IPv4 DHCP lease on an active physical adapter
# so network_diagnostic.ps1 can test the DHCP/IP failure path.
#
# This script intentionally does NOT make registry edits or change static IP settings.
# It only proceeds when DHCP is enabled on the selected adapter.

$ErrorActionPreference = 'Stop'

function Pause-And-Exit([string]$message, [int]$code = 0) {
    Write-Host ''
    Write-Host $message
    Write-Host ''
    Read-Host 'Press ENTER to close'
    exit $code
}

# Require Administrator privileges.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Pause-And-Exit 'Run this test helper as Administrator.' 10
}

$adapter = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
if (-not $adapter) {
    Pause-And-Exit 'No active physical network adapter was found.' 20
}

$ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
if (-not $ipInterface -or $ipInterface.Dhcp -ne 'Enabled') {
    Pause-And-Exit ("STOPPED: {0} is not using DHCP. PC WHY? will not alter a static/manual IP configuration." -f $adapter.Name) 30
}

$config = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$currentIPv4 = $config.IPv4Address | Select-Object -First 1

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host 'PC WHY? - CONTROLLED DHCP TEST' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ("Adapter: {0}" -f $adapter.Name)
Write-Host ("Current IPv4: {0}" -f $(if ($currentIPv4) { $currentIPv4.IPAddress } else { 'none' }))
Write-Host 'DHCP: Enabled' -ForegroundColor Green
Write-Host ''
Write-Host 'This test will TEMPORARILY release the DHCP lease.' -ForegroundColor Yellow
Write-Host 'Internet access on this adapter should stop until the lease is renewed.'
Write-Host ''
Write-Host 'Recovery options:' -ForegroundColor White
Write-Host '  1. Run network_diagnostic.ps1 and let PC WHY? repair DHCP/IP.'
Write-Host '  2. Or manually run: ipconfig /renew'
Write-Host ''

$choice = Read-Host 'Release the DHCP lease now? [Y/N]'
if ($choice -notmatch '^[Yy]$') {
    Pause-And-Exit 'Test cancelled. No changes were made.' 0
}

Write-Host ''
Write-Host 'Releasing DHCP lease...' -ForegroundColor Cyan
& ipconfig.exe /release $adapter.Name | Out-Host
Start-Sleep -Seconds 2

$after = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$afterIPv4 = $after.IPv4Address | Select-Object -First 1

Write-Host ''
if (-not $afterIPv4 -or $afterIPv4.IPAddress -like '169.254.*') {
    Write-Host 'TEST CONDITION CREATED.' -ForegroundColor Yellow
    Write-Host 'The adapter no longer has a normal DHCP IPv4 address.'
    Write-Host ''
    Write-Host 'Now run: network_diagnostic.ps1' -ForegroundColor Cyan
    Write-Host 'Expected diagnosis: IPv4 configuration / DHCP failure.'
    Write-Host 'Expected repair: DHCP renew, then verification.'
} else {
    Write-Host ("The adapter still has IPv4: {0}" -f $afterIPv4.IPAddress) -ForegroundColor Yellow
    Write-Host 'The lease may have been reacquired immediately. Run the main diagnostic anyway.'
}

Write-Host ''
Write-Host 'Emergency manual recovery: ipconfig /renew' -ForegroundColor Green
Write-Host ''
Read-Host 'Press ENTER to close'
