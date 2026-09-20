$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $PSScriptRoot 'stage'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$files = @{
    'curl' = 'installer\payload\curl'
    'cacert.pem' = 'installer\payload\cacert.pem'
    'developer.keystore' = 'research\mkk\devcerts-extracted\developer.keystore'
    'json_simple-1.1.jar' = 'research\mkk\mkk\DevCerts\src\install\json_simple-1.1.jar'
    'device-update-public.pem' = 'updater\device-update-public.pem'
    'device-update.sh' = 'updater\device-update.sh'
    'rupert-sync.sh' = 'installer\rupert-sync.sh'
    'open-current.sh' = 'launcher\open-current.sh'
    'RupertsReader.azw2' = 'launcher\out\RupertsReader.azw2'
    'launcher.properties' = 'tools\rupert-reading-missions\published\launcher.properties'
}

foreach ($entry in $files.GetEnumerator()) {
    $source = Join-Path $project $entry.Value
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing bootstrap input: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $entry.Key) -Force
}

Get-FileHash -Algorithm SHA256 -LiteralPath (Get-ChildItem -LiteralPath $stage -File).FullName |
    Sort-Object Path |
    ForEach-Object { "$($_.Hash.ToLower())  $([IO.Path]::GetFileName($_.Path))" } |
    Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS') -Encoding ascii

Get-Content -LiteralPath (Join-Path $stage 'SHA256SUMS')
