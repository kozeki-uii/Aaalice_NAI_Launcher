#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Generate,
    [switch]$PackageArch
)

$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'This build entry point requires Linux.' }
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
    throw 'The Linux bundle currently supports x86_64 only.'
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    foreach ($command in @('flutter', 'dart', 'clang', 'cmake', 'ninja', 'pkg-config', 'rustc')) {
        Get-Command $command -ErrorAction Stop | Out-Null
    }
    & ./scripts/verify_flutter_sources.ps1
    & ./scripts/prepare_bundled_database.ps1
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    if ($Generate) {
        & dart run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw 'Code generation failed.' }
    }
    & flutter build linux --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Linux release build failed.' }
    & dart build cli --target bin/nai_launcher_mcp.dart --output tool/.tmp/mcp_cli_linux
    if ($LASTEXITCODE -ne 0) { throw 'MCP CLI build failed.' }
    Copy-Item -LiteralPath 'tool/.tmp/mcp_cli_linux/bundle/bin/nai_launcher_mcp' `
        -Destination 'build/linux/x64/release/bundle/nai_launcher_mcp'
    if ($PackageArch) {
        & bash ./scripts/package_linux_arch.sh
        if ($LASTEXITCODE -ne 0) { throw 'Arch package creation failed.' }
    }
} finally {
    Pop-Location
}
