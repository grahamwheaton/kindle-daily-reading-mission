param(
    [string]$ContentRepository = "..\tools\rupert-reading-missions",
    [string]$PrivateKey = "..\private\device-update-private.pem",
    [string]$Version = "1"
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$project = Split-Path $here -Parent
$content = [IO.Path]::GetFullPath((Join-Path $here $ContentRepository))
$key = [IO.Path]::GetFullPath((Join-Path $here $PrivateKey))
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
$device = Join-Path $content 'published\device'

if (-not (Test-Path -LiteralPath $key)) { throw 'The offline device-update private key is missing.' }
if (-not (Test-Path -LiteralPath $openssl)) { throw 'Git for Windows OpenSSL is missing.' }

New-Item -ItemType Directory -Force -Path $device | Out-Null
$assets = @{
    'RupertsReader.azw2' = Join-Path $project 'launcher\out\RupertsReader.azw2'
    'rupert-sync.sh' = Join-Path $project 'installer\rupert-sync.sh'
    'open-current.sh' = Join-Path $project 'launcher\open-current.sh'
}
foreach ($name in $assets.Keys) {
    if (-not (Test-Path -LiteralPath $assets[$name])) { throw "Missing update asset: $($assets[$name])" }
    Copy-Item -LiteralPath $assets[$name] -Destination (Join-Path $device $name) -Force
}

$manifest = @(
    "version=$Version"
    "launcher_sha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $device 'RupertsReader.azw2')).Hash.ToLower())"
    "sync_sha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $device 'rupert-sync.sh')).Hash.ToLower())"
    "open_current_sha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $device 'open-current.sh')).Hash.ToLower())"
) -join "`n"
[IO.File]::WriteAllText((Join-Path $device 'manifest.txt'), $manifest + "`n", [Text.UTF8Encoding]::new($false))

& $openssl dgst -sha256 -sign $key -out (Join-Path $device 'manifest.sig') (Join-Path $device 'manifest.txt')
if ($LASTEXITCODE -ne 0) { throw 'Manifest signing failed.' }
& $openssl dgst -sha256 -verify (Join-Path $project 'updater\device-update-public.pem') -signature (Join-Path $device 'manifest.sig') (Join-Path $device 'manifest.txt')
if ($LASTEXITCODE -ne 0) { throw 'Manifest verification failed.' }

Write-Output "Signed device update $Version in $device"
