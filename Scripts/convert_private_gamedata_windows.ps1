param(
  [Parameter(Mandatory=$true)][string]$Source,
  [string]$Output = "$PSScriptRoot\..\PrivateConversion",
  [switch]$Clean
)
$ErrorActionPreference="Stop"
$Root=(Resolve-Path "$PSScriptRoot\..").Path
$State=Join-Path $Output "conversion_state.json"
New-Item -ItemType Directory -Force -Path $Output | Out-Null
function Save-State($stage,$status) {
  @{schema="bo2ioscs-conversion-state-v1";stage=$stage;status=$status;updated=(Get-Date).ToString("o");source=(Split-Path $Source -Leaf)} |
    ConvertTo-Json | Set-Content -Encoding UTF8 $State
}
if (-not (Test-Path $Source -PathType Container)) { throw "Source directory not found: $Source" }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "Python 3 is required." }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw "ffmpeg is required and must be on PATH." }
if ($Clean -and (Test-Path $Output)) { Remove-Item -Recurse -Force $Output; New-Item -ItemType Directory -Force -Path $Output | Out-Null }
try {
  Save-State "private-import" "running"
  & python "$Root\Tools\PS3AssetConverter\private_asset_import.py" --source $Source --output $Output --extract-ipak
  if ($LASTEXITCODE -ne 0) { throw "private asset import failed ($LASTEXITCODE)" }
  Save-State "media-convert" "running"
  & python "$Root\Tools\PS3AssetConverter\media_convert.py" --source $Source --output $Output
  if ($LASTEXITCODE -ne 0) { throw "media conversion failed ($LASTEXITCODE)" }
  Save-State "complete" "success"
  Write-Host "SUCCESS: $Output\GeneratedGameData"
} catch {
  Save-State "failed" "error"
  throw
}
