# ============================================================
#  CONFIGURACION Y FUNCIONES COMPARTIDAS
#  (la usan backup_mensual.ps1, bandeja.ps1 y medir_tamanos.ps1)
# ============================================================

# ---------- AJUSTES ----------
$Titulo                  = "Backup"
$DiasEntreCopias         = 30    # cada cuantos dias toca copiar cada disco
$HorasEntreRecordatorios = 24    # si toca copia y no la haces, cada cuanto te lo recuerda
$MesesSinUso             = 12    # carpetas sin cambios en estos meses se proponen para liberar espacio
$TamMinimoMB             = 100   # no proponer carpetas mas pequenas que esto
$CarpetaBackup           = "BACKUP"          # carpeta que se crea en cada disco de backup
$MargenDisco             = 0.05  # parte de cada disco que se deja libre (5 %)
$RepoGitHub              = "davidcaptart-glitch/BackupApp"   # de aqui salen las actualizaciones (GitHub Releases)
# Carpetas de codigo que se regeneran solas (npm install, pip install...). No se copian.
$Excluir = @(
    "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".next", ".nuxt", ".turbo", ".parcel-cache", ".expo", ".gradle", ".cache"
    # Opcionales (descomenta si solo las usas para compilados):
    # , "dist", "build", "target", "obj"
)
# -----------------------------

# El codigo vive en la carpeta de instalacion; los datos del usuario, en %LOCALAPPDATA%\BackupApp.
# Asi una actualizacion puede sustituir el codigo sin tocar los datos.
$Codigo          = $PSScriptRoot
$Datos           = Join-Path $env:LOCALAPPDATA "BackupApp"
$CarpetaLogs     = Join-Path $Datos "logs"
$FicheroCarpetas = Join-Path $Datos "carpetas.txt"        # carpetas a copiar (una por linea)
$FicheroDiscos   = Join-Path $Datos "discos.csv"          # discos de backup registrados
$FicheroReparto  = Join-Path $Datos "reparto.csv"         # que carpeta va a que disco
$FicheroUnidades = Join-Path $Datos "tamanos_unidades.csv"
$Historial       = Join-Path $Datos "historial_tamanos.csv"
$FicheroPend     = Join-Path $Datos "pendientes.txt"      # cambios vistos y aun sin copiar
$FicheroSalir    = Join-Path $Datos "salir.senal"         # si aparece, el icono guarda y se cierra (instalador, actualizaciones)
$MarcaDisco      = ".disco_backup"                        # fichero que identifica cada disco
$FicheroAjustes  = Join-Path $Datos "ajustes.json"        # preferencias del usuario (tema...)
$FicheroNubes    = Join-Path $Datos "nubes.csv"           # carpetas en la nube (OneDrive, Dropbox...) usadas como copia extra
$CarpetaNube     = "BackupApp"                            # subcarpeta que se crea dentro de cada carpeta sincronizada
$CarpetaRclone   = Join-Path $Datos "rclone"              # nube directa: rclone.exe y sus conexiones (nube_directa.ps1)
$RcloneExe       = Join-Path $CarpetaRclone "rclone.exe"
$RcloneConf      = Join-Path $CarpetaRclone "rclone.conf"

$Version = "0.0.0"
foreach ($v in @((Join-Path $Codigo "VERSION"), (Join-Path (Split-Path $Codigo -Parent) "VERSION"))) {
    if (Test-Path -LiteralPath $v) { $Version = (Get-Content -LiteralPath $v -TotalCount 1).Trim(); break }
}

# ---------- Ajustes del usuario ----------
function LeerAjuste($clave, $defecto = $null) {
    if (Test-Path -LiteralPath $FicheroAjustes) {
        try { $j = [IO.File]::ReadAllText($FicheroAjustes) | ConvertFrom-Json; if ($null -ne $j.$clave) { return $j.$clave } } catch {}
    }
    return $defecto
}
function GuardarAjuste($clave, $valor) {
    $h = [ordered]@{}
    if (Test-Path -LiteralPath $FicheroAjustes) { try { ([IO.File]::ReadAllText($FicheroAjustes) | ConvertFrom-Json).psobject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } } catch {} }
    $h[$clave] = $valor
    [IO.File]::WriteAllText($FicheroAjustes, ($h | ConvertTo-Json))
}

# ---------- Migracion de datos de versiones anteriores ----------
# Hasta la 0.1.0 los datos se guardaban junto al codigo (C:\BackupMensual). Se copian (no se mueven)
# una sola vez; la carpeta antigua se queda como estaba por si hiciera falta volver atras.
function MigrarDatosAntiguos {
    $hecho = Join-Path $Datos ".migrado"
    if (Test-Path -LiteralPath $hecho) { return }
    $ficheros = "carpetas.txt", "discos.csv", "reparto.csv", "tamanos_unidades.csv", "historial_tamanos.csv", "pendientes.txt"
    $origenes = @($Codigo, "C:\BackupMensual") | Select-Object -Unique |
        Where-Object { $_ -ne $Datos -and (Test-Path -LiteralPath (Join-Path $_ "carpetas.txt")) }
    $de = $origenes | Select-Object -First 1
    if ($de) {
        foreach ($f in $ficheros) {
            $o = Join-Path $de $f; $d = Join-Path $Datos $f
            if ((Test-Path -LiteralPath $o) -and -not (Test-Path -LiteralPath $d)) { Copy-Item -LiteralPath $o -Destination $d }
        }
        $logs = Join-Path $de "logs"
        if ((Test-Path -LiteralPath $logs) -and -not (Test-Path -LiteralPath $CarpetaLogs)) { Copy-Item -LiteralPath $logs -Destination $CarpetaLogs -Recurse }
    }
    Set-Content -LiteralPath $hecho -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm') desde: $(if ($de) { $de } else { '(nada que migrar)' })"
}
New-Item -ItemType Directory -Path $Datos -Force | Out-Null
MigrarDatosAntiguos

# ---------- Carpetas ----------
function DestinoDe($ruta) {
    # D:\Fotos -> Fotos ; otras unidades llevan su letra delante (C:\X -> C\X)
    # (se mantiene asi para que las copias que ya existen en los discos sigan en su sitio)
    $ruta = $ruta.TrimEnd('\')
    if ($ruta -match '^[Dd]:\\(.+)$') { return $Matches[1] }
    return ($ruta -replace '^([A-Za-z]):\\?', '$1\')
}
# carpetas.txt: una carpeta por linea, "ruta" o "ruta|prioridad" (1 = imprescindible, 2 = normal, 3 = si sobra sitio).
# Si no caben todas en los discos, se copian antes las de mas prioridad.
function PrioridadSugerida($ruta) {
    $n = Split-Path $ruta.TrimEnd('\') -Leaf
    if ($n -match '^(Documentos|Documents|Mis documentos|Escritorio|Desktop|Imagenes|Im.genes|Pictures|Fotos|Photos)$') { return 1 }
    return 2
}
function LeerCarpetas {
    if (-not (Test-Path -LiteralPath $FicheroCarpetas)) { return @() }
    @([IO.File]::ReadAllLines($FicheroCarpetas) | Where-Object { $_.Trim() } | ForEach-Object {
        $p = $_.Split('|'); $o = $p[0].Trim().TrimEnd('\')
        $pri = 0; if ($p.Count -lt 2 -or -not [int]::TryParse($p[1].Trim(), [ref]$pri) -or $pri -lt 1 -or $pri -gt 3) { $pri = PrioridadSugerida $o }
        [pscustomobject]@{ Origen = $o; Destino = (DestinoDe $o); Prioridad = $pri } })
}
function EscribirCarpetas($lista) {
    # $lista: objetos con Origen y Prioridad
    [IO.File]::WriteAllLines($FicheroCarpetas, [string[]]@($lista | ForEach-Object { "$($_.Origen)|$($_.Prioridad)" }))
}
$Carpetas = LeerCarpetas

function DentroDe($hija, $padre) {
    $h = $hija.TrimEnd('\') + '\'; $p = $padre.TrimEnd('\') + '\'
    return $h.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
}

# ---------- Unidades de reparto ----------
# Cada subcarpeta directa de una carpeta incluida (ej. FOTOS\Boda X) es una "unidad" que vive entera en un disco.
# Los archivos sueltos de una carpeta son otra unidad ("<carpeta>\*").
# El usuario puede afinar el plan (ventana "Editar el plan"):
#  - divididas.txt: subcarpetas que se "abren" para elegir dentro; sus subcarpetas pasan a ser unidades (a cualquier profundidad)
#  - excluidas.txt: unidades que no se copian (su copia en el disco no se borra, solo deja de actualizarse)
# Cada unidad lleva Rel (su ruta relativa a la carpeta incluida) y Dir (la carpeta real; para los sueltos, la que los contiene).
$FicheroDivididas = Join-Path $Datos "divididas.txt"
$FicheroExcluidas = Join-Path $Datos "excluidas.txt"
function LeerLista($fichero) {
    $h = @{}
    if (Test-Path -LiteralPath $fichero) { foreach ($l in [IO.File]::ReadAllLines($fichero)) { if ($l.Trim()) { $h[$l.Trim().TrimEnd('\')] = $true } } }
    return $h
}
function GuardarLista($fichero, $h) { [IO.File]::WriteAllLines($fichero, [string[]]@($h.Keys | Sort-Object)) }
function RelDe($c, $ruta) {
    $o = $c.Origen.TrimEnd('\'); $r = $ruta.TrimEnd('\')
    if ($r.Length -le $o.Length) { return '' }
    return $r.Substring($o.Length + 1)
}
function DestinoUnidad($u) {
    # Ruta relativa dentro de BACKUP: la de la carpeta incluida mas la de la unidad (los sueltos van a su carpeta)
    if ($u.Rel) { return (Join-Path $u.Carpeta.Destino $u.Rel) } else { return $u.Carpeta.Destino }
}
function ConjuntosEspejo($unidades) {
    # Para quitar de una copia lo que ya no toca: rutas relativas (dentro de BACKUP) de las unidades elegidas, de las
    # carpetas cuyos archivos sueltos se copian y de todas las carpetas intermedias que hay que conservar
    $cj = @{ Unidades = @{}; Sueltos = @{}; Ancestros = @{} }
    foreach ($u in $unidades) {
        $r = (DestinoUnidad $u).ToLower()
        if ($u.Tipo -eq 'carpeta') { $cj.Unidades[$r] = $true } else { $cj.Sueltos[$r] = $true }
        $partes = $r.Split('\'); $acc = ''
        for ($i = 0; $i -lt $partes.Count - $(if ($u.Tipo -eq 'carpeta') { 1 } else { 0 }); $i++) { $acc = if ($acc) { "$acc\$($partes[$i])" } else { $partes[$i] }; $cj.Ancestros[$acc] = $true }
    }
    return $cj
}
function UnidadesActuales { UnidadesDe $Carpetas }
function UnidadesDe($carpetas, $divididas = $null, $excluidas = $null, [switch]$ConExcluidas) {
    # Con -ConExcluidas tambien devuelve las excluidas (marcadas con Excluida = $true), para la ventana de edicion
    if ($null -eq $divididas) { $divididas = LeerLista $FicheroDivididas }
    if ($null -eq $excluidas) { $excluidas = LeerLista $FicheroExcluidas }
    foreach ($c in $carpetas) {
        if (-not (Test-Path -LiteralPath $c.Origen)) { continue }
        UnidadesDeDir $c $c.Origen.TrimEnd('\') $divididas $excluidas $ConExcluidas
    }
}
function UnidadesDeDir($c, $dir, $divididas, $excluidas, $conExcluidas) {
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { ($Excluir -notcontains $_.Name) -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
        $p = $d.FullName
        if ($divididas.ContainsKey($p)) { UnidadesDeDir $c $p $divididas $excluidas $conExcluidas; continue }
        $ex = $excluidas.ContainsKey($p)
        if ($ex -and -not $conExcluidas) { continue }
        [pscustomobject]@{ Clave = $p; Carpeta = $c; Tipo = 'carpeta'; Nombre = $d.Name; Rel = (RelDe $c $p); Dir = $p; Excluida = $ex }
    }
    if (Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) {
        $k = "$dir\*"; $ex = $excluidas.ContainsKey($k)
        if (-not $ex -or $conExcluidas) { [pscustomobject]@{ Clave = $k; Carpeta = $c; Tipo = 'sueltos'; Nombre = '(archivos sueltos)'; Rel = (RelDe $c $dir); Dir = $dir; Excluida = $ex } }
    }
}
$script:listasPlan = @{ Marca = $null }
function ListasPlan {
    # divididas/excluidas en memoria; se releen solo si alguno de los dos archivos ha cambiado
    $m = "$(if (Test-Path $FicheroDivididas) { (Get-Item $FicheroDivididas).LastWriteTimeUtc.Ticks })|$(if (Test-Path $FicheroExcluidas) { (Get-Item $FicheroExcluidas).LastWriteTimeUtc.Ticks })"
    if ($script:listasPlan.Marca -ne $m) { $script:listasPlan = @{ Marca = $m; Div = (LeerLista $FicheroDivididas); Exc = (LeerLista $FicheroExcluidas) } }
    return $script:listasPlan
}
function UnidadDeRuta($ruta) {
    # A que unidad pertenece un archivo o carpeta que ha cambiado ($null si no esta en el plan)
    $lp = ListasPlan; $divididas = $lp.Div; $excluidas = $lp.Exc
    foreach ($c in $Carpetas) {
        $o = $c.Origen.TrimEnd('\') + '\'
        if (-not $ruta.StartsWith($o, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $seg = $ruta.Substring($o.Length).Split('\'); $dir = $c.Origen.TrimEnd('\')
        for ($i = 0; $i -lt $seg.Count; $i++) {
            $p = Join-Path $dir $seg[$i]
            $ultimo = ($i -eq $seg.Count - 1)
            if ($ultimo -and -not (Test-Path -LiteralPath $p -PathType Container)) { $u = "$dir\*" }   # archivo suelto
            elseif ($divididas.ContainsKey($p) -and -not $ultimo) { $dir = $p; continue }
            else { $u = $p }
            if ($excluidas.ContainsKey($u)) { return $null }
            return $u
        }
    }
    return $null
}
# Recorre una carpeta: bytes totales, bytes que se copian (sin $Excluir), archivos y ultima modificacion.
# El recorrido va en C# (mucho mas rapido que un bucle de PowerShell). $Contador, si se da (un [long[]] de 1),
# recibe en [0] los bytes contados hasta el momento: asi otra ventana puede mostrar el progreso sin que el
# medidor tenga que llamar a codigo de PowerShell (eso, desde otro hilo, puede quedarse bloqueado). Con -Rapido no entra en las carpetas excluidas
# (node_modules...): Bytes = BytesBackup, pero es muchisimo mas rapido. Basta para planificar el reparto.
if (-not ("BackupApp.Medidor3" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Collections.Generic;
namespace BackupApp {
    public static class Medidor3 {
        public static long[] Medir(string raiz, bool soloRaiz, bool entrarExcluidas, string[] excluir, long[] contador) {
            HashSet<string> ex = new HashSet<string>(excluir ?? new string[0], StringComparer.OrdinalIgnoreCase);
            long bytes = 0, backup = 0, archivos = 0, ultimo = DateTime.MinValue.Ticks;
            Stack<KeyValuePair<DirectoryInfo, bool>> pila = new Stack<KeyValuePair<DirectoryInfo, bool>>();
            pila.Push(new KeyValuePair<DirectoryInfo, bool>(new DirectoryInfo(raiz), false));
            while (pila.Count > 0) {
                KeyValuePair<DirectoryInfo, bool> e = pila.Pop();
                try {
                    foreach (FileSystemInfo i in e.Key.EnumerateFileSystemInfos()) {
                        if ((i.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                        DirectoryInfo d = i as DirectoryInfo;
                        if (d != null) {
                            if (soloRaiz) continue;
                            bool excluida = e.Value || ex.Contains(d.Name);
                            if (excluida && !entrarExcluidas) continue;
                            pila.Push(new KeyValuePair<DirectoryInfo, bool>(d, excluida)); continue;
                        }
                        FileInfo f = (FileInfo)i; long l = f.Length;
                        bytes += l; archivos++;
                        if (!e.Value) backup += l;
                        long w = f.LastWriteTime.Ticks; if (w > ultimo) ultimo = w;
                    }
                } catch { }
                if (contador != null) System.Threading.Interlocked.Exchange(ref contador[0], backup);
            }
            return new long[] { bytes, backup, archivos, ultimo };
        }
    }
}
"@
}
function Analizar($raiz, [switch]$SoloRaiz, [switch]$Rapido, [long[]]$Contador = $null) {
    $r = [BackupApp.Medidor3]::Medir($raiz, [bool]$SoloRaiz, -not $Rapido, [string[]]$Excluir, $Contador)
    [pscustomobject]@{ Bytes = $r[0]; BytesBackup = $r[1]; Archivos = $r[2]
                       Ultimo = $(if ($r[3] -gt [datetime]::MinValue.Ticks) { New-Object DateTime ([int64]$r[3]) } else { [datetime]::MinValue }) }
}
# ---------- Discos de backup ----------
function LeerDiscos {
    if (-not (Test-Path $FicheroDiscos)) { return @() }
    @(Import-Csv $FicheroDiscos -Delimiter ';')
}
function GuardarDiscos($lista) {
    # Ajeno = bytes que ocupan en el disco otras cosas que no son el backup (se mide al registrarlo)
    # Dias = cada cuantos dias toca copiar este disco (vacio = $DiasEntreCopias)
    @($lista) | Select-Object Id, Nombre, Capacidad, UltimaCopia, Ajeno, Dias |
        Export-Csv $FicheroDiscos -Delimiter ';' -NoTypeInformation -Encoding UTF8
}
function UnidadesDeDisco {
    # Letras de unidad utiles (sin CD ni red, que pueden bloquearse). Se descarta la unidad virtual de Google Drive,
    # que es una nube y no un disco.
    [IO.DriveInfo]::GetDrives() | Where-Object { ($_.DriveType -eq 'Removable' -or $_.DriveType -eq 'Fixed') -and $_.IsReady -and -not (EsUnidadGoogle $_) }
}
function EsUnidadGoogle($dr) {
    if ($dr.VolumeLabel -eq 'Google Drive') { return $true }
    foreach ($n in 'Mi unidad', 'My Drive') { if (Test-Path -LiteralPath (Join-Path $dr.RootDirectory.FullName $n)) { return $true } }
    return $false
}
function InfoDiscos {
    # Todas las unidades utiles del PC con lo que el asistente necesita saber de cada una
    $sistema = $env:SystemDrive.Substring(0, 1).ToUpper()
    $reg = LeerDiscos
    foreach ($dr in (UnidadesDeDisco)) {
        $l = $dr.Name.Substring(0, 1).ToUpper()
        $externo = $dr.DriveType -eq 'Removable'
        try { $bus = (Get-Partition -DriveLetter $l -ErrorAction Stop | Get-Disk -ErrorAction Stop).BusType; if ("$bus" -match 'USB|1394|SD|MMC') { $externo = $true } } catch {}
        $id = IdDeUnidad $dr
        $r = if ($id) { $reg | Where-Object { $_.Id -eq $id } | Select-Object -First 1 } else { $null }
        $marca = if ($id) { LeerMarca $dr } else { $null }
        [pscustomobject]@{ Letra = "$($l):"; Etiqueta = $dr.VolumeLabel; Externo = $externo; Sistema = ($l -eq $sistema); NombreMarca = $(if ($marca) { $marca.Nombre })
                           Capacidad = [int64]$dr.TotalSize; Libre = [int64]$dr.AvailableFreeSpace; Formato = $dr.DriveFormat
                           IdMarca = $id; Registrado = $r; Drive = $dr }
    }
}
# La marca X:\BACKUP\.disco_backup tiene el Id en la primera linea y el nombre del disco en la segunda
# (asi otro PC lo reconoce por su nombre). Las marcas antiguas solo tienen el Id.
function LeerMarca($drive) {
    $m = Join-Path $drive.RootDirectory.FullName "$CarpetaBackup\$MarcaDisco"
    if (-not (Test-Path -LiteralPath $m)) { return $null }
    try { $l = @([IO.File]::ReadAllLines($m)) } catch { return $null }
    [pscustomobject]@{ Id = "$($l[0])".Trim(); Nombre = $(if ($l.Count -gt 1) { $l[1].Trim() } else { $null }) }
}
function EscribirMarca($raiz, $id, $nombre) {
    $m = Join-Path $raiz $MarcaDisco
    if (Test-Path -LiteralPath $m) { (Get-Item -LiteralPath $m -Force).Attributes = 'Normal' }
    [IO.File]::WriteAllLines($m, [string[]]@($id, $nombre))
    (Get-Item -LiteralPath $m -Force).Attributes = 'Hidden'
}
function RenombrarDiscoRegistrado($id, $nombre) {
    # Cambia el nombre en discos.csv y, si el disco esta conectado, en su marca
    $lista = @(LeerDiscos); foreach ($d in $lista) { if ($d.Id -eq $id) { $d.Nombre = $nombre } }; GuardarDiscos $lista
    $c = DiscosConectados | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if ($c) { try { EscribirMarca $c.Raiz $id $nombre } catch {} }
}
function CambiarEtiquetaWindows($letra, $nombre) {
    # Etiqueta del volumen (la que se ve en el Explorador). Windows pide permiso de administrador.
    $n = ($nombre -replace '["]', '').Replace("'", "''"); if ($n.Length -gt 32) { $n = $n.Substring(0, 32) }
    try {
        $p = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -PassThru -Wait -ArgumentList "-NoProfile -Command `"Set-Volume -DriveLetter $($letra.Substring(0, 1)) -NewFileSystemLabel '$n'`""
        return ($p.ExitCode -eq 0)
    } catch { return $false }   # el usuario no dio permiso
}
function IdDeUnidad($drive) {
    $m = Join-Path $drive.RootDirectory.FullName "$CarpetaBackup\$MarcaDisco"
    if (Test-Path -LiteralPath $m) { return (Get-Content -LiteralPath $m -TotalCount 1).Trim() }
    return $null
}
function DiscosConectados {
    $reg = LeerDiscos
    foreach ($dr in (UnidadesDeDisco)) {
        $id = IdDeUnidad $dr
        if (-not $id) { continue }
        $r = $reg | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $r) { continue }
        [pscustomobject]@{ Id = $id; Nombre = $r.Nombre; Letra = $dr.Name.Substring(0, 2)
                           Raiz = (Join-Path $dr.RootDirectory.FullName $CarpetaBackup)
                           Capacidad = $dr.TotalSize; Libre = $dr.AvailableFreeSpace; Formato = $dr.DriveFormat }
    }
}
function DiscosCandidatos {
    # Discos conectados que podrian registrarse: no son el del sistema, no tienen carpetas de origen y no estan registrados
    $sistema = $env:SystemDrive.Substring(0, 1).ToUpper()
    foreach ($dr in (UnidadesDeDisco)) {
        $l = $dr.Name.Substring(0, 1).ToUpper()
        if ($l -eq $sistema) { continue }
        if ($Carpetas | Where-Object { $_.Origen.Substring(0, 1).ToUpper() -eq $l }) { continue }
        if (IdDeUnidad $dr) { continue }
        $dr
    }
}
function EspacioAjeno($drive) {
    # Lo ocupado en el disco sin contar una carpeta BACKUP que ya existiera
    $usado = [int64]$drive.TotalSize - [int64]$drive.AvailableFreeSpace
    $bk = Join-Path $drive.RootDirectory.FullName $CarpetaBackup
    if (Test-Path -LiteralPath $bk) { $usado -= (Analizar $bk).Bytes }
    return [math]::Max([int64]0, $usado)
}
function EspacioUtil($d) {
    # Cuanto puede guardar el backup en un disco: capacidad menos margen y menos lo que ocupan otras cosas
    return [int64]([int64]$d.Capacidad * (1 - $MargenDisco)) - [int64]$d.Ajeno
}
function RegistrarDisco($letra, $nombre, $dias = '') {
    # Si el disco ya tiene marca (se uso como backup en otro PC o en una instalacion anterior) se conserva su Id
    $raiz = Join-Path "$letra\" $CarpetaBackup
    New-Item -ItemType Directory -Path $raiz -Force | Out-Null
    $dr = New-Object IO.DriveInfo $letra
    $id = IdDeUnidad $dr
    if (-not $id) { $id = [guid]::NewGuid().ToString() }
    EscribirMarca $raiz $id $nombre
    $lista = @(LeerDiscos | Where-Object { $_.Id -ne $id }) +
             [pscustomobject]@{ Id = $id; Nombre = $nombre; Capacidad = $dr.TotalSize; UltimaCopia = ''; Ajeno = (EspacioAjeno $dr); Dias = $dias }
    GuardarDiscos $lista
    return $id
}
function DiscoToca($d) {
    if (-not $d.UltimaCopia) { return $true }
    $u = [datetime]::ParseExact($d.UltimaCopia, 'yyyy-MM-dd HH:mm', $null)
    $dias = if ([int]$d.Dias -gt 0) { [int]$d.Dias } else { $DiasEntreCopias }
    return ((Get-Date) - $u).TotalDays -ge $dias
}

# ---------- Reparto de unidades entre discos ----------
function LeerReparto {
    $h = @{}
    if (Test-Path $FicheroReparto) { Import-Csv $FicheroReparto -Delimiter ';' | ForEach-Object { $h[$_.Unidad] = $_.Disco } }
    return $h
}
function GuardarReparto($h) {
    $h.GetEnumerator() | Sort-Object Key | ForEach-Object { [pscustomobject]@{ Unidad = $_.Key; Disco = $_.Value } } |
        Export-Csv $FicheroReparto -Delimiter ';' -NoTypeInformation -Encoding UTF8
}
function LeerTamUnidades {
    $h = @{}
    if (Test-Path $FicheroUnidades) { Import-Csv $FicheroUnidades -Delimiter ';' | ForEach-Object { $h[$_.Unidad] = [int64]$_.Bytes } }
    return $h
}
function OcupacionPorDisco($rep, $tam) {
    $oc = @{}
    foreach ($d in (LeerDiscos)) { $oc[$d.Id] = [int64]0 }
    foreach ($k in @($rep.Keys)) { if ($oc.ContainsKey($rep[$k]) -and $tam.ContainsKey($k)) { $oc[$rep[$k]] += $tam[$k] } }
    return $oc
}
$EnEspera = "ESPERA"   # en reparto.csv: unidad que no cabe en ningun disco; espera a que registres otro

function Repartir($unidades, $tam, $discos, $rep) {
    # Plan de copias. Las unidades sin disco (o en espera) van al disco con mas espacio util libre,
    # empezando por las carpetas de mas prioridad y, dentro de cada prioridad, por las unidades pequenas: si no
    # cabe todo, asi se protegen el mayor numero de carpetas y lo que queda en espera son las pocas gigantes.
    # Si una unidad no cabe en ningun disco se queda en espera ($EnEspera).
    # Una vez asignada, una unidad se queda siempre en su disco (no se mueven datos).
    # No guarda nada: sirve tambien para simular planes con discos aun no registrados.
    $ids = @($discos | ForEach-Object { $_.Id })
    $oc = @{}; foreach ($d in $discos) { $oc[$d.Id] = [int64]0 }
    foreach ($k in @($rep.Keys)) { if ($oc.ContainsKey($rep[$k]) -and $tam.ContainsKey($k)) { $oc[$rep[$k]] += $tam[$k] } }
    $nuevas = @($unidades | Where-Object { -not $rep.ContainsKey($_.Clave) -or $ids -notcontains $rep[$_.Clave] })
    foreach ($u in ($nuevas | Sort-Object { $_.Carpeta.Prioridad }, { [int64]$tam[$_.Clave] })) {
        $t = [int64]$tam[$u.Clave]
        $mejor = $discos | Where-Object { (EspacioUtil $_) - $oc[$_.Id] -ge $t } |
                 Sort-Object { (EspacioUtil $_) - $oc[$_.Id] } -Descending | Select-Object -First 1
        if ($mejor) { $rep[$u.Clave] = $mejor.Id; $oc[$mejor.Id] += $t } else { $rep[$u.Clave] = $EnEspera }
    }
    return $rep
}
function TamanosDe($unidades) {
    # Tamanos medidos (tamanos_unidades.csv) y, para las unidades que aun no se han medido, se miden ahora y se guardan
    $tam = LeerTamUnidades; $nuevos = $false
    foreach ($u in $unidades) {
        if (-not $tam.ContainsKey($u.Clave)) {
            $a = if ($u.Tipo -eq 'sueltos') { Analizar $u.Dir -SoloRaiz } else { Analizar $u.Clave -Rapido }
            $tam[$u.Clave] = $a.BytesBackup; $nuevos = $true
        }
    }
    if ($nuevos) { GuardarTamUnidades $tam }
    return $tam
}
function GuardarTamUnidades($tam) {
    $hoy = Get-Date -Format 'yyyy-MM-dd'
    try { $tam.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Unidad = $_.Key; Bytes = $_.Value; Fecha = $hoy } } | Export-Csv $FicheroUnidades -Delimiter ';' -NoTypeInformation -Encoding UTF8 } catch {}
}
function AsignarNuevas {
    $discos = @(LeerDiscos)
    $rep = LeerReparto
    if (-not $discos) { return $rep }
    $unidades = @(UnidadesActuales)
    $antes = ($rep.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    $rep = Repartir $unidades (TamanosDe $unidades) $discos $rep
    $despues = ($rep.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    if ($antes -ne $despues) { GuardarReparto $rep }
    return $rep
}

# ---------- Resumen del plan (lo que se muestra al usuario) ----------
# Tamanos en que se venden los discos (en TB decimales, como los anuncian los fabricantes)
$TamanosComerciales = @(0.5, 1, 2, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24) | ForEach-Object { [int64]($_ * 1e12) }
function DiscoRecomendado([int64]$bytes) {
    # El disco comercial mas pequeno en el que caben $bytes con el margen
    foreach ($t in $TamanosComerciales) { if ($t * (1 - $MargenDisco) -ge $bytes) { return $t } }
    return $TamanosComerciales[-1]
}
function TamComercial([int64]$b) { if ($b -lt 1e12) { "$([math]::Round($b / 1e9)) GB" } else { "$($b / 1e12) TB" } }
function CrecimientoAnual($carpeta) {
    # Bytes que crece la carpeta al ano segun historial_tamanos.csv ($null si hay menos de 30 dias de historial)
    if (-not (Test-Path $Historial)) { return $null }
    $f = @(Import-Csv $Historial -Delimiter ';' | Where-Object { $_.Carpeta -eq $carpeta } | Sort-Object Fecha)
    if ($f.Count -lt 2) { return $null }
    $d1 = [datetime]::ParseExact($f[0].Fecha, 'yyyy-MM-dd', $null); $d2 = [datetime]::ParseExact($f[-1].Fecha, 'yyyy-MM-dd', $null)
    $dias = ($d2 - $d1).TotalDays
    if ($dias -lt 30) { return $null }
    return [int64](([int64]$f[-1].Bytes - [int64]$f[0].Bytes) * 365 / $dias)
}
function FrecuenciaSugerida($carpeta, [int64]$bytes) {
    # Semanal si la carpeta cambia mucho (mas de un 2 % al mes) o es de documentos; mensual si es un archivo que crece despacio
    $c = CrecimientoAnual $carpeta
    if ($null -ne $c -and $bytes -gt 0) { if ([math]::Abs($c) / 12 -gt 0.02 * $bytes) { return 'semanal' } else { return 'mensual' } }
    if ((Split-Path $carpeta -Leaf) -match '^(Documentos|Documents|Mis documentos|Escritorio|Desktop)$') { return 'semanal' }
    return 'mensual'
}
function PlanDeCopias($discos, $rep, $tam, $carpetas = $Carpetas) {
    # Devuelve el plan ya calculado en forma de objetos: que va a cada disco, que queda en espera
    # y, si hace falta, que disco comprar. $carpetas permite simular (asistente) sin guardar nada.
    $unidades = @(UnidadesDe $carpetas)
    $porCarpeta = foreach ($c in $carpetas) {
        $us = @($unidades | Where-Object { $_.Carpeta.Origen -eq $c.Origen })
        $bytes = [int64](($us | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum)
        $esp = @($us | Where-Object { $rep[$_.Clave] -eq $EnEspera })
        [pscustomobject]@{
            Carpeta = $c.Origen; Prioridad = $c.Prioridad; Bytes = $bytes; Unidades = $us.Count
            EnEspera = $esp.Count; BytesEspera = [int64](($esp | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum)
            Discos = @($us | ForEach-Object { $rep[$_.Clave] } | Where-Object { $_ -and $_ -ne $EnEspera } | Select-Object -Unique)
            Frecuencia = (FrecuenciaSugerida $c.Origen $bytes)
            Crecimiento = (CrecimientoAnual $c.Origen)
        }
    }
    $porDisco = foreach ($d in $discos) {
        $mias = @($unidades | Where-Object { $rep[$_.Clave] -eq $d.Id })
        $usado = [int64](($mias | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum)
        $carps = @($porCarpeta | Where-Object { $_.Discos -contains $d.Id })
        $frec = if ($carps | Where-Object { $_.Frecuencia -eq 'semanal' }) { 'semanal' } else { 'mensual' }
        [pscustomobject]@{ Id = $d.Id; Nombre = $d.Nombre; Util = (EspacioUtil $d); Asignado = $usado; Carpetas = $carps
                           Frecuencia = $frec; Dias = $(if ($frec -eq 'semanal') { 7 } else { 30 }) }
    }
    $espera = [int64](($porCarpeta | Measure-Object BytesEspera -Sum).Sum)
    $crec = [int64](($porCarpeta | Where-Object { $_.Crecimiento -gt 0 } | Measure-Object Crecimiento -Sum).Sum)
    $sinHist = @($porCarpeta | Where-Object { $null -eq $_.Crecimiento }).Count -gt 0
    # Margen de crecimiento para 2 anos: el medido o, sin historial, un 20 % de lo que hay
    $total = [int64](($porCarpeta | Measure-Object Bytes -Sum).Sum)
    $margen = if ($sinHist) { [int64]($total * 0.2) } else { 2 * $crec }
    $libre = [int64](($porDisco | ForEach-Object { $_.Util - $_.Asignado } | Measure-Object -Sum).Sum)
    $comprar = $null
    if ($espera -gt 0 -or $margen -gt $libre) { $comprar = DiscoRecomendado ([math]::Max($espera, 0) + [math]::Max([int64]0, $margen - [math]::Max([int64]0, $libre))) }
    [pscustomobject]@{ Carpetas = $porCarpeta; Discos = $porDisco; Total = $total; EnEspera = $espera
                       CrecimientoAnual = $crec; SinHistorial = $sinHist; Comprar = $comprar }
}
function TextoPlan($plan) {
    function T($b) { if ([math]::Abs([double]$b) -ge 1TB) { "{0:N2} TB" -f ($b / 1TB) } else { "{0:N1} GB" -f ($b / 1GB) } }
    $pri = @{ 1 = 'imprescindible'; 2 = 'normal'; 3 = 'si sobra sitio' }
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add("Datos a copiar: $(T $plan.Total) en $(@($plan.Carpetas).Count) carpetas.")
    $l.Add("")
    if (-not $plan.Discos) { $l.Add("Todavia no hay discos de backup. Conecta uno externo para registrarlo.") }
    foreach ($d in $plan.Discos) {
        $l.Add("DISCO '$($d.Nombre)': $(T $d.Asignado) de $(T $d.Util) utiles. Copia $($d.Frecuencia) recomendada.")
        foreach ($c in $d.Carpetas) {
            $parte = if ($c.EnEspera -gt 0 -or @($c.Discos).Count -gt 1) { " (una parte)" } else { "" }
            $l.Add("   - $($c.Carpeta)$parte  [$($pri[$c.Prioridad])]")
        }
        $l.Add("")
    }
    $esp = @($plan.Carpetas | Where-Object { $_.EnEspera -gt 0 })
    if ($esp) {
        $l.Add("EN ESPERA (no caben ahora; se copiaran al registrar otro disco): $(T $plan.EnEspera)")
        foreach ($c in $esp) { $l.Add("   - $($c.Carpeta): $($c.EnEspera) de $($c.Unidades) subcarpetas, $(T $c.BytesEspera)  [$($pri[$c.Prioridad])]") }
        $l.Add("")
    }
    if ($plan.SinHistorial) { $l.Add("Crecimiento: aun no hay historial suficiente; se reserva un 20 % para los proximos 2 anos.") }
    else { $l.Add("Crecimiento medido: $(T $plan.CrecimientoAnual) al ano.") }
    if ($plan.Comprar) { $l.Add("RECOMENDACION: compra un disco externo de $(TamComercial $plan.Comprar) (NTFS) y registralo.") }
    else { $l.Add("Tus discos tienen sitio suficiente por ahora.") }
    return ($l -join "`r`n")
}

# ---------- Copia extra en la nube ----------
# Una "nube" es la carpeta que sincroniza un programa (OneDrive, Dropbox, Google Drive...). BackupApp copia en
# <carpeta>\BackupApp lo mas importante que quepa en el espacio contratado y el programa de cada servicio lo sube.
# Es una copia ADICIONAL a la de los discos: no cambia el reparto. Nunca se copia a una nube lo que ya esta en ella.
function LeerNubes {
    if (-not (Test-Path $FicheroNubes)) { return @() }
    @(Import-Csv $FicheroNubes -Delimiter ';')
}
function GuardarNubes($lista) {
    # Prioridad = hasta que prioridad se copia (1 = solo imprescindible, 2 = tambien lo normal)
    # Tipo = carpeta (carpeta sincronizada) o rclone (nube directa, con Remoto y RemotoBase; Cifrado = si/no)
    @($lista) | Select-Object Id, Nombre, Proveedor, RaizSync, Capacidad, Prioridad, UltimaCopia, Dias, Ajeno, Tipo, Remoto, RemotoBase, Cifrado |
        Export-Csv $FicheroNubes -Delimiter ';' -NoTypeInformation -Encoding UTF8
}
function RutaNube($n) { Join-Path $n.RaizSync $CarpetaNube }
function NubeDisponible($n) {
    if ($n.Tipo -eq 'rclone') { return ((Test-Path -LiteralPath $RcloneExe) -and (RemotoExiste $n.Remoto.Split(':')[0])) }
    return ($n.RaizSync -and (Test-Path -LiteralPath $n.RaizSync))
}
# Servicios conocidos: espacio gratis aproximado (para proponer la cuota) y descarga oficial de su programa de escritorio
$ServiciosNube = @(
    [pscustomobject]@{ Proveedor = 'Google Drive'; Gratis = 15GB; Url = 'https://www.google.com/drive/download/' }
    [pscustomobject]@{ Proveedor = 'OneDrive';     Gratis = 5GB;  Url = 'https://www.microsoft.com/microsoft-365/onedrive/download' }
    [pscustomobject]@{ Proveedor = 'Dropbox';      Gratis = 2GB;  Url = 'https://www.dropbox.com/install' }
    [pscustomobject]@{ Proveedor = 'iCloud';       Gratis = 5GB;  Url = 'https://apps.microsoft.com/detail/9pktq5699m62' }
    [pscustomobject]@{ Proveedor = 'MEGA';         Gratis = 20GB; Url = 'https://mega.io/desktop' }
    [pscustomobject]@{ Proveedor = 'pCloud';       Gratis = 10GB; Url = 'https://www.pcloud.com/download-free-online-cloud-file-storage.html' }
    [pscustomobject]@{ Proveedor = 'Proton Drive'; Gratis = 5GB;  Url = 'https://proton.me/drive/download' }
    [pscustomobject]@{ Proveedor = 'Box';          Gratis = 10GB; Url = 'https://www.box.com/resources/downloads' }
)
# Amazon Photos no sincroniza una carpeta: su programa sube el mismo las carpetas que le indiques ("copia directa").
# Con Prime guarda fotos sin limite a resolucion completa, tambien RAW (ARW, CR2, NEF...); los videos, 5 GB.
$AmazonPhotos = [pscustomobject]@{ Proveedor = 'Amazon Photos'; Url = 'https://www.amazon.es/photos'; Nota = 'Fotos sin límite con Prime, también RAW' }
function RutaAmazonPhotos {
    foreach ($p in "$env:LOCALAPPDATA\Amazon Drive\AmazonPhotos.exe", "$env:LOCALAPPDATA\Amazon Photos\AmazonPhotos.exe", "$env:ProgramFiles\Amazon Photos\AmazonPhotos.exe") {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}
function DetectarNubes {
    # Carpetas sincronizadas de los servicios instalados en este PC. Cada servicio guarda su carpeta en un sitio
    # distinto; si no se encuentra, el usuario puede elegirla a mano ("Otra carpeta en la nube o NAS").
    $vistos = @{}
    function Nube($prov, $nombre, $raiz, $cuota = $null, $libre = $null) {
        if (-not $raiz) { return }
        $raiz = [Environment]::ExpandEnvironmentVariables("$raiz").TrimEnd('\')
        if (-not (Test-Path -LiteralPath $raiz -PathType Container)) { return }
        $k = $raiz.ToLower(); if ($vistos.ContainsKey($k)) { return }; $vistos[$k] = $true
        $marca = Join-Path (Join-Path $raiz $CarpetaNube) $MarcaDisco
        $id = if (Test-Path -LiteralPath $marca) { "$(@([IO.File]::ReadAllLines($marca))[0])".Trim() } else { $null }
        [pscustomobject]@{ Proveedor = $prov; Nombre = $nombre; RaizSync = $raiz; Cuota = $cuota; Libre = $libre; IdMarca = $id; Activa = (NubeActiva $prov) }
    }
    # OneDrive: una clave por cuenta (Personal, Business1, Business2...) con su carpeta en UserFolder
    foreach ($k in @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        # El nombre de la carpeta ya dice si es la personal ("OneDrive") o una de empresa ("OneDrive - Empresa")
        if ($p.UserFolder) { Nube 'OneDrive' (Split-Path $p.UserFolder -Leaf) $p.UserFolder }
    }
    foreach ($p in $env:OneDriveCommercial, $env:OneDriveConsumer, $env:OneDrive) { if ($p) { Nube 'OneDrive' (Split-Path $p -Leaf) $p } }
    # Google Drive para escritorio: unidad virtual (G: por defecto) con "Mi unidad"; la cuota la da la propia unidad.
    # La letra o ruta puede estar en DefaultMountPoint. En modo "replicar" la carpeta esta en el perfil del usuario.
    $montajes = @(foreach ($r in 'HKCU:\Software\Google\DriveFS', 'HKLM:\Software\Google\DriveFS', 'HKLM:\Software\Policies\Google\DriveFS') { (Get-ItemProperty $r -ErrorAction SilentlyContinue).DefaultMountPoint })
    foreach ($dr in [IO.DriveInfo]::GetDrives()) {
        if ($dr.DriveType -ne 'Fixed' -or -not $dr.IsReady) { continue }
        if ((EsUnidadGoogle $dr) -or $montajes -contains $dr.Name.Substring(0, 1) -or $montajes -contains $dr.Name.Substring(0, 2)) {
            foreach ($n in 'Mi unidad', 'My Drive') { Nube 'Google Drive' 'Google Drive' (Join-Path $dr.RootDirectory.FullName $n) ([int64]$dr.TotalSize) ([int64]$dr.AvailableFreeSpace) }
        }
    }
    foreach ($m in $montajes) { if ($m -and $m.Length -gt 3) { foreach ($n in 'Mi unidad', 'My Drive') { Nube 'Google Drive' 'Google Drive' (Join-Path ([Environment]::ExpandEnvironmentVariables($m)) $n) } } }
    foreach ($n in 'Mi unidad', 'My Drive', 'Google Drive') { Nube 'Google Drive' 'Google Drive' "$env:USERPROFILE\$n" }
    # Dropbox: %LOCALAPPDATA%\Dropbox\info.json (o en %APPDATA%) con las rutas de las cuentas personal y de empresa
    foreach ($j in "$env:LOCALAPPDATA\Dropbox\info.json", "$env:APPDATA\Dropbox\info.json") {
        if (-not (Test-Path -LiteralPath $j)) { continue }
        try { $i = [IO.File]::ReadAllText($j) | ConvertFrom-Json } catch { continue }
        Nube 'Dropbox' 'Dropbox' $i.personal.path
        Nube 'Dropbox' 'Dropbox (empresa)' $i.business.path
    }
    Nube 'Dropbox' 'Dropbox' "$env:USERPROFILE\Dropbox"
    # iCloud para Windows: "iCloud Drive" en el perfil (versiones antiguas: iCloudDrive)
    Nube 'iCloud' 'iCloud Drive' "$env:USERPROFILE\iCloud Drive"
    Nube 'iCloud' 'iCloud Drive' "$env:USERPROFILE\iCloudDrive"
    # pCloud Drive: unidad virtual (P: por defecto) que tambien da su cuota
    foreach ($dr in [IO.DriveInfo]::GetDrives()) {
        if ($dr.IsReady -and $dr.VolumeLabel -like 'pCloud*') { Nube 'pCloud' 'pCloud Drive' $dr.RootDirectory.FullName ([int64]$dr.TotalSize) ([int64]$dr.AvailableFreeSpace) }
    }
    # Box Drive, MEGA, Proton Drive y Sync.com: carpeta en el perfil del usuario
    Nube 'Box' 'Box' "$env:USERPROFILE\Box"
    Nube 'MEGA' 'MEGA' "$env:USERPROFILE\MEGA"
    Nube 'MEGA' 'MEGA' "$env:USERPROFILE\Documents\MEGA"
    foreach ($p in @(Get-ChildItem "$env:USERPROFILE" -Directory -Filter 'Proton Drive*' -ErrorAction SilentlyContinue)) { Nube 'Proton Drive' 'Proton Drive' $p.FullName }
    Nube 'Sync.com' 'Sync.com' "$env:USERPROFILE\Sync"
    # Nextcloud: carpetas en %APPDATA%\Nextcloud\nextcloud.cfg (lineas ...\localPath=)
    $cfg = "$env:APPDATA\Nextcloud\nextcloud.cfg"
    if (Test-Path -LiteralPath $cfg) { foreach ($l in [IO.File]::ReadAllLines($cfg)) { if ($l -match '\\localPath=(.+)$') { Nube 'Nextcloud' 'Nextcloud' ($Matches[1].Trim() -replace '/', '\') } } }
    Nube 'Nextcloud' 'Nextcloud' "$env:USERPROFILE\Nextcloud"
}
function NubeElegida($ruta) {
    # Carpeta sincronizada elegida a mano (otro servicio, un NAS...). Se intenta adivinar el servicio por la ruta.
    $prov = 'Otra nube'
    foreach ($s in $ServiciosNube) { if ($ruta -match [regex]::Escape($s.Proveedor)) { $prov = $s.Proveedor } }
    $marca = Join-Path (Join-Path $ruta $CarpetaNube) $MarcaDisco
    $id = if (Test-Path -LiteralPath $marca) { "$(@([IO.File]::ReadAllLines($marca))[0])".Trim() } else { $null }
    [pscustomobject]@{ Proveedor = $prov; Nombre = (Split-Path $ruta -Leaf); RaizSync = $ruta.TrimEnd('\'); Cuota = $null; Libre = $null; IdMarca = $id; Activa = (NubeActiva $prov) }
}
# Programa de cada servicio: si no esta abierto, lo que se copie en su carpeta no se sube
$ProcesosNube = @{ 'OneDrive' = @('OneDrive'); 'Google Drive' = @('GoogleDriveFS'); 'Dropbox' = @('Dropbox'); 'iCloud' = @('iCloudDrive', 'iCloudServices', 'iCloudHome')
                   'MEGA' = @('MEGAsync'); 'pCloud' = @('pCloud'); 'Proton Drive' = @('ProtonDrive', 'Proton Drive'); 'Box' = @('Box')
                   'Sync.com' = @('Sync', 'SyncTaskbar'); 'Nextcloud' = @('nextcloud') }
function NubeActiva($prov) {
    # $null si no se sabe (servicio desconocido o NAS), $true/$false segun este abierto su programa
    if (-not $ProcesosNube.ContainsKey($prov)) { return $null }
    return [bool](Get-Process -Name $ProcesosNube[$prov] -ErrorAction SilentlyContinue | Select-Object -First 1)
}
function CuotaSugerida($prov) { $s = $ServiciosNube | Where-Object { $_.Proveedor -eq $prov } | Select-Object -First 1; if ($s) { $s.Gratis } else { 0 } }function AjenoNube($raizSync, $cuota = $null, $libre = $null) {
    # Lo que ya ocupa la cuenta sin contar la copia de BackupApp. Si la nube da su cuota (Google Drive) se usa;
    # si no, se mide la carpeta sincronizada (solo lee nombres y tamanos, no descarga nada).
    $nuestro = $(if (Test-Path -LiteralPath (Join-Path $raizSync $CarpetaNube)) { (Analizar (Join-Path $raizSync $CarpetaNube)).Bytes } else { 0 })
    $usado = if ($cuota -and $null -ne $libre) { [int64]$cuota - [int64]$libre } else { (Analizar $raizSync).Bytes }
    return [math]::Max([int64]0, [int64]$usado - [int64]$nuestro)
}
function MedirNube($n) {
    # Actualiza Ajeno (y Capacidad, si la nube la da como unidad virtual: Google Drive, pCloud, o por rclone)
    if ($n.Tipo -eq 'rclone') { MedirNubeRclone $n; return }
    $q = try { Split-Path -Qualifier $n.RaizSync } catch { $null }
    $dr = if ($q) { New-Object IO.DriveInfo $q } else { $null }
    if ($dr -and $dr.IsReady -and ((EsUnidadGoogle $dr) -or $dr.VolumeLabel -like 'pCloud*')) {
        $n.Capacidad = [int64]$dr.TotalSize; $n.Ajeno = AjenoNube $n.RaizSync $dr.TotalSize $dr.AvailableFreeSpace
    } else { $n.Ajeno = AjenoNube $n.RaizSync }
}
function UnidadesParaNube($n, $unidades, $tam) {
    # Que se copia a una nube: las unidades de prioridad <= $n.Prioridad que quepan, de mas a menos prioridad y,
    # dentro de cada una, de pequenas a grandes (para que quepan enteras el mayor numero de carpetas).
    $util = [int64]([int64]$n.Capacidad * (1 - $MargenDisco)) - [int64]$n.Ajeno
    $max = if ([int]$n.Prioridad -gt 0) { [int]$n.Prioridad } else { 1 }
    $sel = @(); $fuera = @(); $ya = @(); $bytes = [int64]0
    $cands = @($unidades | Where-Object { $_.Carpeta.Prioridad -le $max })
    foreach ($u in ($cands | Sort-Object { $_.Carpeta.Prioridad }, { [int64]$tam[$_.Clave] })) {
        $c = $u.Carpeta.Origen
        # Ya esta en esta nube, o la carpeta de origen contiene la propia nube (se copiaria dentro de si misma)
        if ($n.RaizSync -and ((DentroDe $c $n.RaizSync) -or (DentroDe $n.RaizSync $c))) { $ya += $u; continue }
        $t = [int64]$tam[$u.Clave]
        if ($bytes + $t -le $util) { $sel += $u; $bytes += $t } else { $fuera += $u }
    }
    [pscustomobject]@{ Seleccion = $sel; Fuera = $fuera; YaEnNube = $ya; Bytes = $bytes; Util = [math]::Max([int64]0, $util)
                       BytesFuera = [int64](($fuera | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum) }
}

# Nube directa (rclone)
. (Join-Path $PSScriptRoot "nube_directa.ps1")
