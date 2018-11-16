#  Copyright (c) 2014-present, Facebook, Inc.
#  All rights reserved.
#
#  This source code is licensed under both the Apache 2.0 license (found in the
#  LICENSE file in the root directory of this source tree) and the GPLv2 (found
#  in the COPYING file in the root directory of this source tree).
#  You may select, at your option, one of the above-listed licenses.

# Update-able metadata
#
# $version - The version of the software package to build
# $chocoVersion - The chocolatey package version, used for incremental bumps
#                 without changing the version of the software package
$version = '0.6.2'
$chocoVersion = '0.6.2'
$packageName = 'yaml-cpp'
$projectSource = 'https://github.com/jbeder/yaml-cpp/'
$packageSourceUrl = 'https://github.com/jbeder/yaml-cpp/'
$authors = 'jbeder'
$owners = 'jbeder'
$copyright = 'Copyright (c) 2008-2015 Jesse Beder.'
$license = 'https://raw.githubusercontent.com/jbeder/yaml-cpp/master/LICENSE'
$url = "https://github.com/jbeder/yaml-cpp/archive/$packageName-$version.zip"

# Invoke our utilities file
. "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\osquery_utils.ps1"

# Invoke the MSVC developer tools/env
Invoke-BatchFile "$env:VS140COMNTOOLS\..\..\vc\vcvarsall.bat" amd64

# Time our execution
$sw = [System.Diagnostics.StopWatch]::startnew()

# Keep the location of build script, to bring with in the chocolatey package
$buildScript = $MyInvocation.MyCommand.Definition

# Create the choco build dir if needed
$buildPath = Get-OsqueryBuildPath
if ($buildPath -eq '') {
  Write-Host '[-] Failed to find source root' -foregroundcolor red
  exit
}
$chocoBuildPath = "$buildPath\chocolatey\$packageName"
if (-not (Test-Path "$chocoBuildPath")) {
  New-Item -Force -ItemType Directory -Path "$chocoBuildPath"
}
Set-Location $chocoBuildPath

# Retreive the source
if (-not (Test-Path "$packageName-$version.zip")) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest $url -OutFile "$packageName-$version.zip"
}

# Extract the source
$sourceDir = Join-Path $(Get-Location) "$packageName-$version"
if (-not (Test-Path $sourceDir)) {
  $7z = (Get-Command '7z').Source
  $arg = "x $packageName-$version.zip -o$packageName-$version"
  Start-Process -FilePath $7z -ArgumentList $arg -NoNewWindow -Wait
}

# Hacky-hack-hack - the zip package is annoyingly structured.
$badPath = Join-Path $sourceDir "$packageName-$packageName-$version"
$badPath = Join-Path $badPath "*"
$goodPath = "$sourceDir\"
Move-Item $badPath $goodPath
Set-Location $sourceDir

# Build the libraries
$buildDir = New-Item -Force -ItemType Directory -Path 'osquery-win-build'
Set-Location $buildDir

# Generate the .sln
$envArch = [System.Environment]::GetEnvironmentVariable('OSQ32')
$arch = ''
$platform = ''
$cmakeBuildType = ''
if ($envArch -eq 1) {
  Write-Host '[*] Building 32 bit yaml-cpp libs' -ForegroundColor Cyan
  $arch = 'Win32'
  $platform = 'x86'
  $cmakeBuildType = 'Visual Studio 14 2015'
} else {
  Write-Host '[*] Building 64 bit yaml-cpp libs' -ForegroundColor Cyan
  $arch = 'x64'
  $platform = 'amd64'
  $cmakeBuildType = 'Visual Studio 14 2015 Win64'
}

# Invoke the MSVC developer tools/env
Invoke-BatchFile "$env:VS140COMNTOOLS\..\..\vc\vcvarsall.bat" $platform

$cmake = (Get-Command 'cmake').Source
$cmakeArgs = @(
  "-G `"$cmakeBuildType`"",
  '-DBUILD_SHARED_LIBS=OFF',
  '-DMSVC_SHARED_RT=OFF',
  '../'
)
Start-OsqueryProcess $cmake $cmakeArgs

# Build the libraries
$msbuild = (Get-Command 'msbuild').Source
$configurations = @(
  'Release',
  'Debug'
)
foreach($cfg in $configurations) {
  $msbuildArgs = @(
    'YAML_CPP.sln',
    "/p:Configuration=$cfg",
    "/p:Platform=$arch",
    "/p:PlatformType=$arch",
    '/m',
    '/v:m'
  )
  Start-OsqueryProcess $msbuild $msbuildArgs
}

# If the build path exists, purge it for a clean packaging
$chocoDir = Join-Path $(Get-Location) 'osquery-choco'
if (Test-Path $chocoDir) {
  Remove-Item -Force -Recurse $chocoDir
}

# Construct the Chocolatey Package
New-Item -ItemType Directory -Path $chocoDir
Set-Location $chocoDir
$includeDir = New-Item -ItemType Directory -Path '.\local\include'
$libDir = New-Item -ItemType Directory -Path '.\local\lib'
$srcDir = New-Item -ItemType Directory -Path '.\local\src'

Write-NuSpec `
  $packageName `
  $chocoVersion `
  $authors `
  $owners `
  $projectSource `
  $packageSourceUrl `
  $copyright `
  $license

Copy-Item "$buildDir\Release\libyaml-cpp*" "$libDir\libyaml-cpp.lib"
Copy-Item "$buildDir\Debug\libyaml-cpp*" "$libDir\libyaml-cpp_dbg.lib"
Copy-Item -Recurse "$buildDir\..\include\yaml-cpp" $includeDir
Copy-Item $buildScript $srcDir

choco pack

Write-Host "[*] Build took $($sw.ElapsedMilliseconds) ms" `
  -ForegroundColor DarkGreen
if (Test-Path "$packageName.$chocoVersion.nupkg") {
  Write-Host `
    "[+] Finished building $packageName v$chocoVersion." `
    -ForegroundColor Green
}
else {
  Write-Host `
    "[-] Failed to build $packageName v$chocoVersion." `
    -ForegroundColor Red
}