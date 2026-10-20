# ============================================================
#  NUBE DIRECTA con rclone (https://rclone.org): sube a Google Drive, Dropbox, OneDrive, pCloud, Box o
#  Backblaze B2 sin necesitar el programa del servicio ni una carpeta en el PC, y puede cifrar los archivos
#  antes de subirlos (en la nube se ven con nombres y contenido ilegibles).
#  - rclone se descarga la primera vez que se usa, de la web oficial, comprobando su SHA-256.
#  - Sus conexiones se guardan en %LOCALAPPDATA%\BackupApp\rclone\rclone.conf (no en la configuracion de rclone del usuario).
#  - En nubes.csv: Tipo = rclone, Remoto = donde se guarda la copia ("bk1_c:" si va cifrada, "bk1:BackupApp" si no),
#    RemotoBase = la cuenta ("bk1:") para preguntar el espacio.
#  Lo carga config.ps1, asi que esta disponible en todos los scripts.
# ============================================================
$ServiciosRclone = @(
    [pscustomobject]@{ Tipo = 'drive';    Nombre = 'Google Drive'; Opciones = @('scope=drive.file'); Claves = $null }
    [pscustomobject]@{ Tipo = 'dropbox';  Nombre = 'Dropbox';      Opciones = @();                   Claves = $null }
    [pscustomobject]@{ Tipo = 'onedrive'; Nombre = 'OneDrive';     Opciones = @();                   Claves = $null }
    [pscustomobject]@{ Tipo = 'pcloud';   Nombre = 'pCloud';       Opciones = @();                   Claves = $null }
    [pscustomobject]@{ Tipo = 'box';      Nombre = 'Box';          Opciones = @();                   Claves = $null }
    [pscustomobject]@{ Tipo = 'b2';       Nombre = 'Backblaze B2'; Opciones = @('hard_delete=true'); Claves = @(@('account', 'Identificador de la clave (keyID)'), @('key', 'Clave de aplicación (applicationKey)')) }
)
function RcloneInstalado { Test-Path -LiteralPath $RcloneExe }

function InstalarRclone {
    # Descarga la ultima version oficial y comprueba su SHA-256 con la lista que publica rclone.org.
    # Devuelve $null si todo fue bien o el motivo del error.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path $env:TEMP ("BackupApp-rclone-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'BackupApp'
        $wc.DownloadFile('https://downloads.rclone.org/version.txt', "$tmp\version.txt")
        $v = (([IO.File]::ReadAllText("$tmp\version.txt")).Trim() -split '\s+')[1]
        if ($v -notmatch '^v\d+\.\d+\.\d+$') { return "No se pudo saber cuál es la última versión de rclone." }
        $zip = "rclone-$v-windows-amd64.zip"
        $wc.DownloadFile("https://downloads.rclone.org/$v/SHA256SUMS", "$tmp\SHA256SUMS")
        $wc.DownloadFile("https://downloads.rclone.org/$v/$zip", "$tmp\$zip")
        $esperado = ([IO.File]::ReadAllLines("$tmp\SHA256SUMS") | Where-Object { $_ -match "\s$([regex]::Escape($zip))$" } | ForEach-Object { ($_ -split '\s+')[0] }) | Select-Object -First 1
        $real = (Get-FileHash -LiteralPath "$tmp\$zip" -Algorithm SHA256).Hash.ToLower()
        if (-not $esperado -or $esperado.ToLower() -ne $real) { return "La descarga de rclone no coincide con la oficial (SHA-256). No se ha instalado." }
        Expand-Archive -LiteralPath "$tmp\$zip" -DestinationPath "$tmp\x" -Force
        $exe = Get-ChildItem "$tmp\x" -Recurse -Filter 'rclone.exe' | Select-Object -First 1
        if (-not $exe) { return "El paquete de rclone no trae rclone.exe." }
        New-Item -ItemType Directory -Path $CarpetaRclone -Force | Out-Null
        Copy-Item -LiteralPath $exe.FullName -Destination $RcloneExe -Force
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    } catch { return "No se pudo descargar rclone: $($_.Exception.Message)" }
}

function Rclone([string[]]$argumentos, [switch]$SinEsperar) {
    # Ejecuta rclone con nuestra configuracion. Sin -SinEsperar devuelve Codigo, Salida y Error; mientras espera
    # mantiene viva la ventana (Bombear) y para si se pide detener la copia.
    $todos = @($argumentos) + @('--config', $RcloneConf)
    $linea = ($todos | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $pi = New-Object Diagnostics.ProcessStartInfo $RcloneExe, $linea
    $pi.UseShellExecute = $false; $pi.CreateNoWindow = $true
    $pi.RedirectStandardOutput = $true; $pi.RedirectStandardError = $true
    $pi.StandardOutputEncoding = [Text.Encoding]::UTF8; $pi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($pi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($SinEsperar) { return [pscustomobject]@{ Proceso = $p; Salida = $o; Error = $e } }
    while (-not $p.WaitForExit(150)) {
        if (Get-Command Bombear -ErrorAction SilentlyContinue) { Bombear }
        if ($script:detener) { try { $p.Kill() } catch {}; break }
    }
    $p.WaitForExit()
    [pscustomobject]@{ Codigo = $p.ExitCode; Salida = $o.Result; Error = $e.Result }
}
function RemotoExiste($nombre) {
    if (-not (Test-Path -LiteralPath $RcloneConf)) { return $false }
    return [bool](Select-String -LiteralPath $RcloneConf -Pattern ("^\[" + [regex]::Escape($nombre.TrimEnd(':')) + "\]") -Quiet)
}
function NuevoNombreRemoto {
    $i = 1; while (RemotoExiste "bk$i") { $i++ }; return "bk$i"
}
function ConectarCuentaRclone($servicio, $nombre, $claves = @{}) {
    # Crea la conexion. Si el servicio usa inicio de sesion por navegador, rclone lo abre y espera:
    # devuelve el proceso para que la ventana lo vigile (-SinEsperar).
    $a = @('config', 'create', $nombre, $servicio.Tipo) + $servicio.Opciones
    foreach ($k in $claves.Keys) { $a += "$k=$($claves[$k])" }
    return (Rclone $a -SinEsperar)
}
function CrearCifrado($base, $clave) {
    # Capa de cifrado encima de la cuenta: todo va a <cuenta>:BackupApp con nombres y contenido cifrados
    $obs = (Rclone @('obscure', $clave)).Salida.Trim()
    $r = Rclone @('config', 'create', "$($base)_c", 'crypt', "remote=$($base):BackupApp", "password=$obs", 'filename_encryption=standard', 'directory_name_encryption=true')
    return ($r.Codigo -eq 0)
}
function CuotaRclone($remotoBase) {
    # Espacio de la cuenta (no todos los servicios lo dan: Backblaze B2 no tiene limite)
    $r = Rclone @('about', $remotoBase, '--json')
    if ($r.Codigo -ne 0) { return $null }
    try { $j = $r.Salida | ConvertFrom-Json } catch { return $null }
    if (-not $j.total) { return $null }
    return [pscustomobject]@{ Total = [int64]$j.total; Usado = [int64]$j.used; Libre = [int64]$j.free }
}
function TamanoRclone($remoto) {
    $r = Rclone @('size', $remoto, '--json')
    if ($r.Codigo -ne 0) { return [int64]0 }
    try { return [int64](($r.Salida | ConvertFrom-Json).bytes) } catch { return [int64]0 }
}
function RutaRemota($n, $relativa) {
    $rel = ($relativa -replace '\\', '/').Trim('/')
    if ($n.Remoto.EndsWith(':')) { return "$($n.Remoto)$rel" } else { return "$($n.Remoto)/$rel" }
}
function ExcluirRclone { foreach ($x in $Excluir) { '--exclude'; "$x/**" } }

function MedirNubeRclone($n) {
    $q = CuotaRclone $n.RemotoBase
    if ($q) {
        $n.Capacidad = $q.Total
        $n.Ajeno = [math]::Max([int64]0, $q.Usado - (TamanoRclone $n.Remoto))
    }
}
function SubirUnidadRclone($u, $n, $log) {
    # Igual que robocopy /MIR: deja la carpeta de la nube igual que la del PC
    if ($u.Tipo -eq 'carpeta') {
        $dst = RutaRemota $n (Join-Path $u.Carpeta.Destino $u.Nombre)
        $a = @('sync', $u.Clave, $dst) + @(ExcluirRclone) + @('--log-file', $log, '--log-level', 'NOTICE', '--transfers', '4')
    } else {
        # Archivos sueltos de la raiz: solo el primer nivel
        $dst = RutaRemota $n $u.Carpeta.Destino
        $a = @('sync', $u.Carpeta.Origen, $dst, '--max-depth', '1', '--exclude', '*/**', '--log-file', $log, '--log-level', 'NOTICE')
    }
    return (Rclone $a).Codigo
}
function EspejoRclone($n, $validos, $sueltos) {
    # Quita de la nube las carpetas que ya no tocan (no caben, se borraron o cambio la prioridad)
    foreach ($c in $Carpetas) {
        $base = RutaRemota $n $c.Destino
        $r = Rclone @('lsf', '--dirs-only', $base)
        if ($r.Codigo -ne 0) { continue }
        foreach ($d in ($r.Salida -split "`r?`n" | Where-Object { $_ })) {
            $ruta = "$base/$($d.TrimEnd('/'))"
            if (-not $validos.ContainsKey($ruta.ToLower())) { [void](Rclone @('purge', $ruta)) }
        }
        if (-not $sueltos.ContainsKey($c.Origen.ToLower())) { [void](Rclone @('delete', $base, '--max-depth', '1')) }
    }
}
