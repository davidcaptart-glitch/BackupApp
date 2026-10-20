# ============================================================
#  Prepara el programa en dist\BackupApp: compila BackupApp.exe (con su icono) y copia los scripts.
#  Usa el compilador de C# que trae Windows (.NET Framework 4), no hace falta instalar nada.
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File herramientas\compilar.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$ico  = Join-Path $raiz "recursos\BackupApp.ico"
$sal  = Join-Path $raiz "dist\BackupApp"
if (-not (Test-Path $ico)) { & (Join-Path $PSScriptRoot "generar_icono.ps1") }

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "No se encuentra csc.exe (.NET Framework 4)." }

if (Test-Path $sal) { Remove-Item $sal -Recurse -Force }
New-Item -ItemType Directory -Path $sal -Force | Out-Null

$version = (Get-Content (Join-Path $raiz "VERSION") -TotalCount 1).Trim()
$cs  = Join-Path $raiz "src\lanzador\BackupApp.cs"
$tmp = Join-Path $env:TEMP "BackupApp_version.cs"
Set-Content $tmp "[assembly: System.Reflection.AssemblyVersion(`"$version.0`")][assembly: System.Reflection.AssemblyFileVersion(`"$version.0`")]"
& $csc /nologo /target:winexe /optimize+ /win32icon:"$ico" /out:"$(Join-Path $sal 'BackupApp.exe')" /r:System.Windows.Forms.dll "$cs" "$tmp"
if ($LASTEXITCODE -ne 0) { throw "Error al compilar BackupApp.exe" }
Remove-Item $tmp

Get-ChildItem (Join-Path $raiz "src") -File | Where-Object { $_.Extension -in '.ps1' } | Copy-Item -Destination $sal
Copy-Item $ico, (Join-Path $raiz "recursos\logo.png"), (Join-Path $raiz "VERSION"), (Join-Path $raiz "CHANGELOG.md") -Destination $sal
Write-Host "Listo: $sal (version $version)"
