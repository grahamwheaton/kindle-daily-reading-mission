param(
    [Parameter(Mandatory = $true)]
    [string]$MissionPath,

    [string]$DeviceFileName = "RupertsMission.mobi"
)

$ErrorActionPreference = 'Stop'

$source = Get-Item -LiteralPath $MissionPath
if ($source.Extension -ne '.mobi') {
    throw "The mission must be a .mobi file: $($source.FullName)"
}

$kindleRoot = $null
foreach ($letter in [char[]]([char]'D'..[char]'Z')) {
    $candidate = "${letter}:\"
    if ((Test-Path -LiteralPath (Join-Path $candidate 'documents')) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'usbnet'))) {
        $kindleRoot = $candidate
        break
    }
}

if (-not $kindleRoot) {
    throw 'Kindle storage was not found. Connect and unlock the Kindle, then try again.'
}

$documents = Join-Path $kindleRoot 'documents'
$destination = Join-Path $documents $DeviceFileName
$temporary = "$destination.uploading"

Copy-Item -LiteralPath $source.FullName -Destination $temporary -Force
$sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
$copiedHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
if ($sourceHash -ne $copiedHash) {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    throw 'The copied mission failed verification; the existing mission was left unchanged.'
}

Move-Item -LiteralPath $temporary -Destination $destination -Force

[pscustomobject]@{
    Status      = 'Delivered and verified'
    KindleDrive = $kindleRoot
    Destination = $destination
    Bytes       = $source.Length
    SHA256      = $sourceHash
}
