param(
    [string]$Keystore = "..\research\launcher\shairkindle\kindlet\developer.keystore"
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$project = Split-Path $here -Parent
$jdk = Get-ChildItem -LiteralPath (Join-Path $project 'tools\jdk8\runtime') -Directory | Select-Object -First 1
if (-not $jdk) { throw 'Portable JDK 8 is missing from tools/jdk8/runtime.' }

$java = Join-Path $jdk.FullName 'bin\java.exe'
$jar = Join-Path $jdk.FullName 'bin\jar.exe'
$jarsigner = Join-Path $jdk.FullName 'bin\jarsigner.exe'
$ecj = Join-Path $project 'tools\ecj\ecj-4.6.1.jar'
$keystorePath = [System.IO.Path]::GetFullPath((Join-Path $here $Keystore))
$out = Join-Path $here 'out'
$stubsOut = Join-Path $out 'stubs'
$classesOut = Join-Path $out 'classes'
$app = Join-Path $out 'RupertsReader.azw2'

if (-not (Test-Path -LiteralPath $ecj)) { throw 'ECJ compiler is missing.' }
if (-not (Test-Path -LiteralPath $keystorePath)) { throw "Developer keystore is missing: $keystorePath" }

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stubsOut,$classesOut | Out-Null

$stubSources = @(Get-ChildItem -LiteralPath (Join-Path $here 'stubs') -Recurse -Filter '*.java' | ForEach-Object FullName)
$appSources = @(Get-ChildItem -LiteralPath (Join-Path $here 'src') -Recurse -Filter '*.java' | ForEach-Object FullName)
$vendor = Join-Path $project 'vendor\shairkindle\kindlet'
$gatewayStub = Join-Path $vendor 'stubs\org\json\simple\parser\ParseException.java'
$gatewaySources = @(
    (Join-Path $vendor 'src\ixtab\jailbreak\JailbreakConstants.java'),
    (Join-Path $vendor 'src\ixtab\jailbreak\Jailbreak.java'),
    (Join-Path $vendor 'src\com\besteffortlabs\kindletshell\RuntimePermissions.java')
)

& $java -cp $ecj org.eclipse.jdt.internal.compiler.batch.Main -source 1.4 -target 1.4 -nowarn -d $stubsOut @stubSources $gatewayStub
if ($LASTEXITCODE -ne 0) { throw 'Stub compilation failed.' }
& $java -cp $ecj org.eclipse.jdt.internal.compiler.batch.Main -source 1.4 -target 1.4 -nowarn -classpath $stubsOut -d $classesOut @gatewaySources @appSources
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }

& $jar cfm $app (Join-Path $here 'META-INF\MANIFEST.MF') -C $classesOut .
if ($LASTEXITCODE -ne 0) { throw 'Kindlet packaging failed.' }

foreach ($alias in @('ditest','dktest','dntest')) {
    & $jarsigner -keystore $keystorePath -storepass password -keypass password -digestalg SHA-256 -sigalg SHA256withRSA $app $alias
    if ($LASTEXITCODE -ne 0) { throw "Signing failed for $alias." }
}

& $jarsigner -verify $app
if ($LASTEXITCODE -ne 0) { throw 'Kindlet signature verification failed.' }

$class = Join-Path $classesOut 'uk\co\beaverland\rupertreader\RupertReader.class'
$bytes = [System.IO.File]::ReadAllBytes($class)
$major = ($bytes[6] -shl 8) -bor $bytes[7]
if ($major -ne 48) { throw "Unexpected class major version $major; Kindle requires 48." }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $app).Hash
Write-Output "Built $app"
Write-Output "Class major: $major"
Write-Output "SHA256: $hash"
