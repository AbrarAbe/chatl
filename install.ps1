# install.ps1 — install chatl from GitHub Releases (Windows)
#
# Usage:
#   irm https://raw.githubusercontent.com/AbrarAbe/chatl/main/install.ps1 | iex
#   irm ... | iex -Version 0.2.0
#   install.ps1 --uninstall
#   $env:CHATL_DIST_DIR="C:\path\to\dist"; install.ps1 --version 0.2.0   (offline)
param(
  [string]$Version,
  [switch]$Uninstall,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$InstallDir = Join-Path $env:LOCALAPPDATA "chatl"
$DistDir = $env:CHATL_DIST_DIR
$RepoOwner = "AbrarAbe"
$RepoName  = "chatl"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Fail([string]$Message) {
  Write-Error $Message
  exit 1
}

function Need-Cmd([string]$Command) {
  if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
    Fail "required command not found: $Command"
  }
}

function Platform-Arch() {
  $arch = [Environment]::Is64BitOperatingSystem
  if ($arch) { return "x64" }
  Fail "unsupported architecture: $([Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE'))"
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
if ($Help) {
  Write-Output @"
Usage: install.ps1 [-Version <v>] [-Uninstall] [-Help]
  -Version <v>  Install version v (default: latest)
  -Uninstall    Remove chatl from $InstallDir
  -Help         Show this help
Env:
  CHATL_DIST_DIR  Directory containing chatl-<v>-<plat>.zip + SHA256SUMS
                  (offline; skips network)
"@
  exit 0
}

if ($Uninstall) {
  $bin = Join-Path $InstallDir "chatl.exe"
  if (Test-Path $bin) {
    Remove-Item $bin -Force
    Write-Host "chatl removed from $InstallDir"
  } else {
    Write-Host "chatl not found in $InstallDir"
  }
  exit 0
}

Need-Cmd "curl.exe"   # Windows ships curl.exe since Windows 10 1803
Need-Cmd "certutil.exe"

# -----------------------------------------------------------------------------
# Resolve version
# -----------------------------------------------------------------------------
if (-not $Version) {
  Write-Host "fetching latest release from GitHub…" -NoNewline
  $Version = try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest" -ErrorAction Stop
    $r.tag_name
  } catch {
    Fail "could not determine latest release (try -Version <v>)"
  }
  Write-Host $Version
}
Write-Host "installing chatl $Version"

# -----------------------------------------------------------------------------
# Resolve platform & archive name
# -----------------------------------------------------------------------------
$Platform = "windows-x64"
$Archive  = "chatl-${Version}-${Platform}.zip"

# -----------------------------------------------------------------------------
# Download (or use local dist dir)
# -----------------------------------------------------------------------------
$Work = [System.IO.Path]::GetTempPath()
$Work = Join-Path $Work ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $Work -Force | Out-Null
trap { Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue }

if ($DistDir) {
  $archivePath = Join-Path $DistDir $Archive
  $sumsPath    = Join-Path $DistDir "SHA256SUMS"
  if (-not (Test-Path $archivePath)) { Fail "archive not found: $archivePath" }
  if (-not (Test-Path $sumsPath))    { Fail "checksums not found: $sumsPath" }
  Copy-Item $archivePath -Destination $Work -Force
  Copy-Item $sumsPath    -Destination $Work -Force
} else {
  $Url = "https://github.com/$RepoOwner/$RepoName/releases/download/${Version}/${Archive}"
  Write-Host "downloading ${Archive}…" -NoNewline
  try {
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $Work $Archive) -ErrorAction Stop
  } catch {
    Fail "download failed: $Url"
  }
  Write-Host " done"
  $UrlSums = "https://github.com/$RepoOwner/$RepoName/releases/download/${Version}/SHA256SUMS"
  Invoke-WebRequest -Uri $UrlSums -OutFile (Join-Path $Work "SHA256SUMS") -ErrorAction Stop
}

# -----------------------------------------------------------------------------
# Verify checksum
# -----------------------------------------------------------------------------
$sumsLine = Get-Content (Join-Path $Work "SHA256SUMS") | Where-Object { $_ -match " $Archive\$" }
if (-not $sumsLine) {
  Fail "checksum not found for ${Archive} in SHA256SUMS"
}
$expectedHash = $sumsLine -split ' ' | Select-Object -First 1

$archiveFile = Join-Path $Work $Archive
$certOutput = certutil -hashfile $archivePath SHA256 2>$null
# certutil output: hash line then blank line then "CertUtil: -hashfile command completed successfully."
$actualHash = ($certOutput | Where-Object { $_ -match '^[0-9a-fA-F]{64}$' }) -join ''
if ($actualHash -ne $expectedHash) {
  Fail "checksum verification failed for ${Archive}: expected $expectedHash, got $actualHash"
}

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Expand-Archive -Path $archivePath -DestinationPath (Join-Path $Work "extract") -Force
$binary = Get-ChildItem -Path (Join-Path $Work "extract") -Filter "chatl*" -File | Select-Object -First 1
if (-not $binary) {
  Fail "chatl binary not found in archive"
}
Copy-Item $binary.FullName -Destination (Join-Path $InstallDir "chatl.exe") -Force

Write-Host "installed chatl ${Version} to ${InstallDir}/chatl.exe"
Write-Host "add $InstallDir to your PATH if it is not already:"
