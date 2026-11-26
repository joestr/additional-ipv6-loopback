[CmdletBinding()]
param(
    [switch]$Persist,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-LoopbackAdapter {
    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like '*Loopback*' } |
        Select-Object -First 1
}

$adapter = Get-LoopbackAdapter

if (-not $adapter) {
    $devcon = Get-Command devcon.exe -ErrorAction SilentlyContinue
    if ($devcon) {
        Write-Host 'Adding custom loopback adapter (based on KM-TEST) ...'
        & $devcon.Source install (Join-Path $env:SystemRoot 'INF\netloop.inf') '*MSLOOP'
        Start-Sleep -Seconds 3
        $adapter = Get-LoopbackAdapter
    }
}

if ($adapter) {
    $ifIndex = $adapter.ifIndex
    Write-Host "Using adapter '$($adapter.Name)' ($($adapter.InterfaceDescription), ifIndex $ifIndex)"
    Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
}
else {
    Write-Warning 'KM-TEST adapter not found (devcon.exe is missing). Using default loopback interface instead ...'
    $ifIndex = (Get-NetIPAddress -AddressFamily IPv6 -IPAddress '::1' -ErrorAction Stop).InterfaceIndex
    Write-Host "Using default loopback interface (ifIndex $ifIndex)"
}

Set-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv6 -DadTransmits 0 -ErrorAction SilentlyContinue

$prefixIp     = '::7f00:0'
$prefixLength = 104
$addresses    = 1..15 | ForEach-Object { '::7f00:{0:x}' -f $_ }

if (-not $Force) {
    Write-Host ("Adding IPv6 range {0}/{1} and {2} IPv6 addresses {3} - {4} ..." -f $prefixIp, $prefixLength, $addresses.Count, $addresses[0], $addresses[-1])
    if ((Read-Host 'Continue? (y/n)') -notmatch '^[yY]') { return }
}

function Add-LoopbackAddress([string]$ip) {
    $newIpArgs = @{
        InterfaceIndex = $ifIndex
        IPAddress      = $ip
        PrefixLength   = $prefixLength
    }
    if (-not $Persist) {
        $newIpArgs.PolicyStore = 'ActiveStore'
    }

    try {
        New-NetIPAddress @newIpArgs -ErrorAction Stop | Out-Null
        Write-Host "  + $ip/$prefixLength"
        return 'added'
    }
    catch {
        if ($_.Exception.Message -like '*already exists*') {
            Write-Host "  = $ip/$prefixLength (existiert bereits)"
            return 'skipped'
        }
        Write-Warning "  ! ${ip}/${prefixLength}: $($_.Exception.Message)"
        return 'failed'
    }
}

$added = 0
$skipped = 0
$failed = 0

# Prefix address
switch (Add-LoopbackAddress $prefixIp) {
    'added'   { $added++ }
    'skipped' { $skipped++ }
    'failed'  { $failed++ }
}

# Bereich ::7f00:1 - ::7f00:f
foreach ($ip in $addresses) {
    switch (Add-LoopbackAddress $ip) {
        'added'   { $added++ }
        'skipped' { $skipped++ }
        'failed'  { $failed++ }
    }
}

Write-Host "Done: Added $added, Skipped $skipped, Failed $failed"
