# ============================================================
#  Publica una version nueva en GitHub Releases
#  1. Cambia VERSION y anade una seccion "## X.Y.Z" al principio de CHANGELOG.md (son las novedades que vera el usuario).
#  2. Ejecuta:  powershell -NoProfile -ExecutionPolicy Bypass -File herramientas\publicar.ps1
#     Con -SoloPreparar crea el instalador, el .sha256 y las notas en dist\ sin publicar nada.
#  Necesita Inno Setup 6 y gh (GitHub CLI) con la sesion iniciada.
# ============================================================
param([switch]$SoloPreparar)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$repo = "davidcaptart-glitch/BackupApp"
$v = (Get-Content (Join-Path $raiz "VERSION") -TotalCount 1).Trim()

# Novedades de esta version: la seccion "## $v" de CHANGELOG.md
$lineas = [IO.File]::ReadAllLines((Join-Path $raiz "CHANGELOG.md"))
$notas = @(); $dentro = $false
foreach ($l in $lineas) {
    if ($l -match '^##\s+(\S+)') { if ($dentro) { break }; $dentro = ($Matches[1] -eq $v); continue }
    if ($dentro) { $notas += $l }
}
$notas = ($notas -join "`n").Trim()
if (-not $notas) { throw "Falta la seccion '## $v' en CHANGELOG.md (son las novedades que vera el usuario)." }

# Programa e instalador
& (Join-Path $PSScriptRoot "compilar.ps1")
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "No se encuentra Inno Setup 6 (ISCC.exe)." }
& $iscc /Q (Join-Path $raiz "instalador\BackupApp.iss")
if ($LASTEXITCODE -ne 0) { throw "Error al crear el instalador." }
$setup = Join-Path $raiz "dist\BackupApp-setup-$v.exe"
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$setup.sha256", "$hash  BackupApp-setup-$v.exe`n")
$ficheroNotas = Join-Path $raiz "dist\notas-$v.md"
[IO.File]::WriteAllText($ficheroNotas, $notas, (New-Object Text.UTF8Encoding $false))
Write-Host "Preparado: $setup`nSHA-256:   $hash"
if ($SoloPreparar) { return }

# Publicar: el codigo tiene que estar en un commit y subido; la etiqueta vX marca esa version
if (git -C $raiz status --porcelain) { throw "Hay cambios sin guardar en git. Haz commit antes de publicar." }
git -C $raiz tag -a "v$v" -m "BackupApp $v"
git -C $raiz push origin HEAD "v$v"
gh release create "v$v" $setup "$setup.sha256" --repo $repo --title "BackupApp $v" --notes-file $ficheroNotas
if ($LASTEXITCODE -ne 0) { throw "gh no pudo crear la release." }
Write-Host "Publicada: https://github.com/$repo/releases/tag/v$v"
