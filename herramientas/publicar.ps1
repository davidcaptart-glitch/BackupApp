# ============================================================
#  Publica una version nueva
#  1. Cambia VERSION y anade una seccion "## X.Y.Z" al principio de CHANGELOG.md (son las novedades que vera el usuario).
#  2. Haz commit y ejecuta:  powershell -NoProfile -ExecutionPolicy Bypass -File herramientas\publicar.ps1
#     Sube la etiqueta vX.Y.Z y GitHub Actions (.github\workflows\publicar.yml) compila el instalador a partir del
#     codigo, lo firma con SignPath si esta configurado y crea la release. Asi la compilacion es verificable.
#  Otras formas:
#     -Local         compila y publica desde este PC (sin compilacion verificable; necesita Inno Setup 6 y gh).
#     -SoloPreparar  crea el instalador y las notas en dist\ sin publicar nada (lo usa GitHub Actions).
#     -SinCompilar   con -SoloPreparar: usa el programa que ya hay en dist\BackupApp (por ejemplo, recien firmado).
#  Firma local (opcional, con -Local o -SoloPreparar): si existe BACKUPAPP_CERTIFICADO con la huella de un certificado
#  de firma de codigo en Cert:\CurrentUser\My, se firman BackupApp.exe, los .ps1 y el instalador.
# ============================================================
param([switch]$SoloPreparar, [switch]$SinCompilar, [switch]$Local)
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

# Nada personal en lo que se publica: patrones en personal\no_publicar.txt (fuera de git, una expresion por linea)
$patrones = Join-Path $raiz "personal\no_publicar.txt"
if (Test-Path $patrones) {
    $p = @([IO.File]::ReadAllLines($patrones) | Where-Object { $_.Trim() })
    $hallados = @(git -C $raiz ls-files | ForEach-Object { Select-String -LiteralPath (Join-Path $raiz $_) -Pattern $p -ErrorAction SilentlyContinue } | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
    if ($hallados) { throw "Hay datos personales en archivos del repositorio; no se publica:`n$($hallados -join "`n")" }
}

# Lo normal: publicar desde GitHub Actions
if (-not $SoloPreparar -and -not $Local) {
    if (git -C $raiz status --porcelain) { throw "Hay cambios sin guardar en git. Haz commit antes de publicar." }
    git -C $raiz tag -a "v$v" -m "BackupApp $v"
    git -C $raiz push origin HEAD "v$v"
    Write-Host "Etiqueta v$v subida. GitHub compila y publica la version: https://github.com/$repo/actions"
    return
}

# Firma de codigo local (si hay certificado)
$cert = $null
if ($env:BACKUPAPP_CERTIFICADO) {
    $cert = Get-Item "Cert:\CurrentUser\My\$($env:BACKUPAPP_CERTIFICADO)" -ErrorAction SilentlyContinue
    if (-not $cert) { throw "No se encuentra el certificado $($env:BACKUPAPP_CERTIFICADO) en Cert:\CurrentUser\My." }
    if (-not $cert.HasPrivateKey) { throw "El certificado no tiene la clave privada en este PC." }
}
function Firmar($rutas) {
    if (-not $cert) { return }
    foreach ($r in $rutas) {
        $s = Set-AuthenticodeSignature -FilePath $r -Certificate $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.digicert.com"
        if ($s.Status -ne 'Valid') { throw "No se pudo firmar $r : $($s.StatusMessage)" }
    }
    Write-Host "Firmados $(@($rutas).Count) archivos con $($cert.Subject)"
}

# Programa e instalador
if (-not $SinCompilar) { & (Join-Path $PSScriptRoot "compilar.ps1") }
Firmar @(Get-ChildItem (Join-Path $raiz "dist\BackupApp") -Include *.exe, *.ps1 -Recurse | ForEach-Object { $_.FullName })
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "No se encuentra Inno Setup 6 (ISCC.exe)." }
& $iscc /Q (Join-Path $raiz "instalador\BackupApp.iss")
if ($LASTEXITCODE -ne 0) { throw "Error al crear el instalador." }
$setup = Join-Path $raiz "dist\BackupApp-setup-$v.exe"
Firmar @($setup)
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$setup.sha256", "$hash  BackupApp-setup-$v.exe`n")
$ficheroNotas = Join-Path $raiz "dist\notas-$v.md"
[IO.File]::WriteAllText($ficheroNotas, $notas, (New-Object Text.UTF8Encoding $false))
Write-Host "Preparado: $setup`nSHA-256:   $hash"
if ($SoloPreparar) { return }

# -Local: publicar desde este PC
if (git -C $raiz status --porcelain) { throw "Hay cambios sin guardar en git. Haz commit antes de publicar." }
git -C $raiz tag -a "v$v" -m "BackupApp $v"
git -C $raiz push origin HEAD "v$v"
gh release create "v$v" $setup "$setup.sha256" --repo $repo --title "BackupApp $v" --notes-file $ficheroNotas
if ($LASTEXITCODE -ne 0) { throw "gh no pudo crear la release." }
Write-Host "Publicada: https://github.com/$repo/releases/tag/v$v"
