param(
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherDir = Join-Path $projectRoot "launcher"
$exeName = "TheMinecraftServer.net Mods Installer.exe"
$publishDir = Join-Path $launcherDir "bin\Release\net8.0-windows\$Runtime\publish"
$srcExe = Join-Path $publishDir $exeName
$destExe1 = Join-Path $projectRoot "publish\$exeName"
$destExe2 = Join-Path $projectRoot $exeName

Push-Location $launcherDir
try {
    dotnet publish -c Release -r $Runtime --self-contained true `
        /p:PublishSingleFile=true `
        /p:IncludeNativeLibrariesForSelfExtract=true `
        /p:EnableCompressionInSingleFile=true `
        /p:InvariantGlobalization=true `
        /p:PublishReadyToRun=false `
        /p:DebugType=none `
        /p:DebugSymbols=false `
        /p:IncludeSymbolsInSingleFile=false `
        /p:NuGetAudit=false
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $srcExe)) {
    throw "Publish output missing: $srcExe"
}

Copy-Item -LiteralPath $srcExe -Destination $destExe1 -Force
Copy-Item -LiteralPath $srcExe -Destination $destExe2 -Force
