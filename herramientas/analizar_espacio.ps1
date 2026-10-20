# ============================================================
#  ANALIZADOR DE ESPACIO (solo lectura: no borra nada)
#  Recorre C: y D: y genera un informe en ..\informes\espacio_FECHA\
#   - resumen.txt        : discos, papelera, basura conocida, programas
#   - carpetas.csv       : carpetas de mas de 1 GB (hasta 3 niveles)
#   - grandes.csv        : archivos de mas de 1 GB
#   - duplicados.csv     : archivos repetidos (mismo tamano y contenido)
#   - especiales.csv     : node_modules, entornos Python, previas de Lightroom, cache de DaVinci...
#   - basura.csv         : ubicaciones de temporales y caches conocidas
#   - programas.csv      : programas instalados por tamano
#   - descargas.csv      : todo lo de Descargas con tamano, antiguedad, duplicados y sugerencia
# ============================================================
param([string[]]$Unidades = @("C:", "D:"))
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = "Analizando espacio (no se borra nada)"

$salida = Join-Path (Split-Path $PSScriptRoot -Parent) ("informes\espacio_" + (Get-Date -Format "yyyy-MM-dd_HHmm"))
New-Item -ItemType Directory -Path $salida -Force | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;

public class Especial { public string Ruta; public string Tipo; public long Bytes; public DateTime Fecha; }
public class Fichero  { public string Ruta; public long Bytes; public DateTime Fecha; }

public class Resultado {
    public Dictionary<string, long> Carpetas = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, Especial> Especiales = new Dictionary<string, Especial>(StringComparer.OrdinalIgnoreCase);
    public List<Fichero> Grandes = new List<Fichero>();
    public List<Fichero> CandDup = new List<Fichero>();
    public long Archivos; public long Bytes; public long Carpetas_; public long SinPermiso;
}

public static class Escaner {
    static string TipoEspecial(string nombre) {
        string n = nombre.ToLowerInvariant();
        if (n == "node_modules") return "node_modules (se regenera con npm install)";
        if (n == ".venv" || n == "venv") return "entorno Python (se regenera con pip)";
        if (n.EndsWith("previews.lrdata")) return "previas de Lightroom (se regeneran)";
        if (n == "cacheclip" || n == ".gallery") return "cache de DaVinci Resolve (se regenera)";
        if (n == "media cache files" || n == "media cache" || n == "peak files") return "cache de Adobe (se regenera)";
        if (n == "__pycache__") return null;
        return null;
    }

    public static Resultado Escanear(string raiz, int prof, long umbralGrande, long umbralDup, string[] saltar, Action<string> progreso) {
        Resultado r = new Resultado();
        HashSet<string> salta = new HashSet<string>(saltar, StringComparer.OrdinalIgnoreCase);
        Stack<object[]> pila = new Stack<object[]>();
        pila.Push(new object[] { new DirectoryInfo(raiz), 0, new string[0], null });
        DateTime ultimo = DateTime.Now;
        while (pila.Count > 0) {
            object[] e = pila.Pop();
            DirectoryInfo d = (DirectoryInfo)e[0]; int nivel = (int)e[1]; string[] claves = (string[])e[2]; Especial esp = (Especial)e[3];
            r.Carpetas_++;
            if ((DateTime.Now - ultimo).TotalSeconds > 2) { ultimo = DateTime.Now; progreso(d.FullName); }
            try {
                foreach (FileSystemInfo i in d.EnumerateFileSystemInfos()) {
                    if ((i.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    DirectoryInfo sd = i as DirectoryInfo;
                    if (sd != null) {
                        if (salta.Contains(sd.FullName)) continue;
                        string[] nc = claves;
                        if (nivel < prof) { nc = new string[claves.Length + 1]; claves.CopyTo(nc, 0); nc[claves.Length] = sd.FullName; }
                        Especial ne = esp;
                        if (ne == null) {
                            string t = TipoEspecial(sd.Name);
                            if (t != null) { ne = new Especial(); ne.Ruta = sd.FullName; ne.Tipo = t; ne.Fecha = sd.LastWriteTime; r.Especiales[sd.FullName] = ne; }
                        }
                        pila.Push(new object[] { sd, nivel + 1, nc, ne });
                    } else {
                        FileInfo f = (FileInfo)i; long len = f.Length;
                        r.Archivos++; r.Bytes += len;
                        foreach (string k in claves) { long v; r.Carpetas.TryGetValue(k, out v); r.Carpetas[k] = v + len; }
                        if (esp != null) { esp.Bytes += len; if (f.LastWriteTime > esp.Fecha) esp.Fecha = f.LastWriteTime; }
                        if (len >= umbralGrande || len >= umbralDup) {
                            Fichero x = new Fichero(); x.Ruta = f.FullName; x.Bytes = len; x.Fecha = f.LastWriteTime;
                            if (len >= umbralGrande) r.Grandes.Add(x);
                            if (len >= umbralDup && esp == null) r.CandDup.Add(x);
                        }
                    }
                }
            } catch { r.SinPermiso++; }
        }
        return r;
    }

    // Huella rapida: tamano + MD5 de los primeros y ultimos 4 MB
    public static string Huella(string ruta, long len) {
        try {
            using (FileStream fs = new FileStream(ruta, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (MD5 md5 = MD5.Create()) {
                int bloque = 4 * 1024 * 1024;
                byte[] buf = new byte[bloque];
                int n = fs.Read(buf, 0, bloque);
                md5.TransformBlock(buf, 0, n, null, 0);
                if (len > 2L * bloque) { fs.Seek(-bloque, SeekOrigin.End); n = fs.Read(buf, 0, bloque); }
                else { n = 0; }
                md5.TransformFinalBlock(buf, 0, n);
                return BitConverter.ToString(md5.Hash);
            }
        } catch { return null; }
    }
}
"@

function GB($b) { "{0:N2}" -f ($b / 1GB) }
function Tam($b) { if ($b -ge 1TB) { "{0:N2} TB" -f ($b / 1TB) } elseif ($b -ge 1GB) { "{0:N1} GB" -f ($b / 1GB) } else { "{0:N0} MB" -f ($b / 1MB) } }
function TamCarpeta($ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return $null }
    $r = [Escaner]::Escanear($ruta, 0, [long]::MaxValue, [long]::MaxValue, @(), [Action[string]] { param($x) })
    return $r.Bytes
}
$informe = New-Object System.Collections.Generic.List[string]
function L($t) { $informe.Add($t); Write-Host $t }

L "INFORME DE ESPACIO - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
L "(Solo lectura: no se ha borrado nada)"
L ""

# ---------- 1) Discos ----------
L "== DISCOS =="
foreach ($u in $Unidades) {
    $dr = New-Object IO.DriveInfo $u
    if ($dr.IsReady) { L ("{0}  total {1}  |  libre {2} ({3:N0} %)" -f $u, (Tam $dr.TotalSize), (Tam $dr.AvailableFreeSpace), (100 * $dr.AvailableFreeSpace / $dr.TotalSize)) }
}
L ""

# ---------- 2) Papelera ----------
L "== PAPELERA DE RECICLAJE =="
$sh = New-Object -ComObject Shell.Application
$pap = $sh.NameSpace(10)
$papBytes = [int64]0; $papN = 0; $papPorUnidad = @{}
foreach ($it in $pap.Items()) {
    $b = [int64]$it.ExtendedProperty("Size"); $papBytes += $b; $papN++
    $orig = [string]$it.ExtendedProperty("System.Recycle.DeletedFrom")
    $k = if ($orig.Length -ge 2) { $orig.Substring(0, 2).ToUpper() } else { "?" }
    $papPorUnidad[$k] = [int64]$papPorUnidad[$k] + $b
}
L ("{0:N0} elementos, {1} en total" -f $papN, (Tam $papBytes))
foreach ($k in $papPorUnidad.Keys) { L ("   borrados desde {0}: {1}" -f $k, (Tam $papPorUnidad[$k])) }
L ""

# ---------- 3) Basura y caches conocidas ----------
Write-Host "Midiendo temporales y caches conocidas..." -ForegroundColor Cyan
$H = $env:USERPROFILE; $LA = $env:LOCALAPPDATA; $RA = $env:APPDATA
$conocidas = @(
    @("Temporales de usuario (%TEMP%)", $env:TEMP, "Seguro: Configuracion > Sistema > Almacenamiento > Archivos temporales"),
    @("Temporales de Windows", "C:\Windows\Temp", "Seguro (requiere administrador)"),
    @("Cache de Windows Update", "C:\Windows\SoftwareDistribution\Download", "Seguro: Liberador de espacio > Limpieza de Windows Update"),
    @("Windows anterior (Windows.old)", "C:\Windows.old", "Seguro si no vas a volver a la version anterior: Liberador de espacio"),
    @("Restos de actualizacion de Windows", "C:\`$WINDOWS.~BT", "Seguro: Liberador de espacio"),
    @("Restos de agente de recuperacion", "C:\`$WinREAgent", "Seguro: Liberador de espacio"),
    @("Instaladores de drivers AMD", "C:\AMD", "Seguro: son copias de instalacion de drivers ya instalados"),
    @("Instaladores de drivers Intel", "C:\Intel", "Normalmente seguro (logs/instaladores)"),
    @("Carpeta C:\Temp", "C:\Temp", "Revisar y borrar lo que no reconozcas como tuyo"),
    @("Carpeta C:\tmp", "C:\tmp", "Revisar"),
    @("Temporales de Adobe", "C:\adobeTemp", "Seguro con los programas de Adobe cerrados"),
    @("Volcados de errores", "$LA\CrashDumps", "Seguro"),
    @("Cache de sombreadores DirectX", "$LA\D3DSCache", "Seguro (se regenera)"),
    @("Cache de Chrome", "$LA\Google\Chrome\User Data\Default\Cache", "Seguro: Chrome > Borrar datos de navegacion > Imagenes y archivos en cache"),
    @("Cache de codigo de Chrome", "$LA\Google\Chrome\User Data\Default\Code Cache", "Seguro"),
    @("Cache de Edge", "$LA\Microsoft\Edge\User Data\Default\Cache", "Seguro"),
    @("Cache de npm", "$LA\npm-cache", "Seguro: npm cache clean --force"),
    @("Cache de pip", "$LA\pip\Cache", "Seguro: pip cache purge"),
    @("Cache de Bun", "$H\.bun\install\cache", "Seguro: bun pm cache rm"),
    @("Cache de Gradle", "$H\.gradle\caches", "Seguro (se vuelve a descargar al compilar)"),
    @("Carpeta .cache del usuario", "$H\.cache", "Normalmente seguro (caches de herramientas)"),
    @("Emuladores Android (AVD)", "$H\.android\avd", "Borra los emuladores que no uses desde Android Studio > Device Manager"),
    @("Modelos de Ollama", "$H\.ollama\models", "Borra modelos que no uses: ollama list / ollama rm <modelo>"),
    @("Modelos PaddleX", "$H\.paddlex", "Si ya no usas PaddleOCR/PaddleX"),
    @("Modelos InsightFace", "$H\.insightface", "Si ya no usas InsightFace"),
    @("Cache de medios de Adobe", "$RA\Adobe\Common\Media Cache Files", "Seguro: Premiere > Preferencias > Cache de medios > Eliminar"),
    @("Cache de medios de Adobe (2)", "$RA\Adobe\Common\Media Cache", "Seguro"),
    @("Medios de DaVinci Resolve", "$H\DaVinci Resolve Media", "Revisar: cache y proxies se regeneran"),
    @("Proyectos de Aftershoot", "$H\Aftershoot Projects", "Revisar: proyectos de culling ya entregados"),
    @("Docker (discos WSL)", "$LA\Docker\wsl", "Si no usas Docker: docker system prune o desinstalar"),
    @("Entornos Python en C:\venvs", "C:\venvs", "Borra los entornos de proyectos que ya no uses")
)
$basura = @()
foreach ($c in $conocidas) {
    $b = TamCarpeta $c[1]
    if ($b -and $b -ge 50MB) { $basura += [pscustomobject]@{ Que = $c[0]; Ruta = $c[1]; GB = (GB $b); Bytes = $b; Como = $c[2] } }
}
# Carpetas temporales de CapCut en la raiz de C:
Get-ChildItem "C:\" -Directory -Force | Where-Object { $_.Name -like ".__capcut_export_temp_folder*" } | ForEach-Object {
    $b = TamCarpeta $_.FullName
    $basura += [pscustomobject]@{ Que = "Temporal de exportacion de CapCut"; Ruta = $_.FullName; GB = (GB $b); Bytes = $b; Como = "Seguro si CapCut no esta exportando" }
}
# Archivos de sistema grandes
foreach ($f in @("C:\hiberfil.sys", "C:\pagefile.sys", "C:\swapfile.sys")) {
    $i = Get-Item -LiteralPath $f -Force
    if ($i) {
        $como = if ($f -like "*hiberfil*") { "Si no usas la hibernacion: 'powercfg /h off' en una consola de administrador" } else { "No borrar (lo gestiona Windows)" }
        $basura += [pscustomobject]@{ Que = "Archivo de sistema $($i.Name)"; Ruta = $f; GB = (GB $i.Length); Bytes = $i.Length; Como = $como }
    }
}
$basura = $basura | Sort-Object Bytes -Descending
$basura | Select-Object Que, Ruta, GB, Como | Export-Csv (Join-Path $salida "basura.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
L "== TEMPORALES Y CACHES CONOCIDAS =="
foreach ($x in $basura) { L ("{0,10}  {1}  [{2}]" -f (Tam $x.Bytes), $x.Que, $x.Ruta) }
L ("Total: {0}" -f (Tam (($basura | Measure-Object Bytes -Sum).Sum)))
L ""

# ---------- 4) Carpeta Descargas: todo lo que hay, con tamano, antiguedad y duplicados ----------
Write-Host "Analizando la carpeta Descargas..." -ForegroundColor Cyan
$desc = Join-Path $H "Downloads"
$archDesc = @(Get-ChildItem -LiteralPath $desc -File -Recurse -Force)
function Tipo($ext) {
    switch -regex ($ext.ToLower()) {
        '^\.(exe|msi|msix|appx|dmg|pkg)$'      { 'Instalador' }
        '^\.(zip|rar|7z|tar|gz|iso)$'          { 'Comprimido / imagen de disco' }
        '^\.(mp4|mov|avi|mkv|mts|m4v|webm)$'   { 'Video' }
        '^\.(jpg|jpeg|png|heic|raw|cr2|cr3|arw|nef|dng|tif|tiff|psd|gif|webp)$' { 'Imagen' }
        '^\.(mp3|wav|m4a|flac|aac)$'           { 'Audio' }
        '^\.(pdf|docx?|xlsx?|pptx?|txt|csv)$'  { 'Documento' }
        default                                 { 'Otros' }
    }
}
# Duplicados dentro de Descargas y respecto a archivos grandes del resto de discos (se completa tras el recorrido)
$huellaDesc = @{}
foreach ($g in ($archDesc | Group-Object Length | Where-Object { $_.Count -gt 1 })) {
    foreach ($f in $g.Group) { $huellaDesc[$f.FullName] = [Escaner]::Huella($f.FullName, $f.Length) }
}
$repDesc = @{}
$huellaDesc.GetEnumerator() | Where-Object { $_.Value } | Group-Object Value | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    $rutas = @($_.Group | ForEach-Object { $_.Key } | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime })
    for ($i = 1; $i -lt $rutas.Count; $i++) { $repDesc[$rutas[$i]] = $rutas[0] }   # se marca la copia mas nueva como repetida
}
$filasDesc = foreach ($f in ($archDesc | Sort-Object Length -Descending)) {
    $dias = [int]((Get-Date) - $f.LastWriteTime).TotalDays
    $sug = @()
    if ($repDesc.ContainsKey($f.FullName)) { $sug += "Duplicado de: $($repDesc[$f.FullName])" }
    $t = Tipo $f.Extension
    if ($t -eq 'Instalador' -and $dias -gt 30) { $sug += "Instalador antiguo: si el programa ya esta instalado, se puede borrar" }
    if ($t -like 'Comprimido*' -and $dias -gt 30) {
        $base = Join-Path $f.DirectoryName ([IO.Path]::GetFileNameWithoutExtension($f.Name))
        if (Test-Path -LiteralPath $base) { $sug += "Ya esta descomprimido en '$base'" } else { $sug += "Comprimido antiguo" }
    }
    if ($dias -gt 180 -and -not $sug) { $sug += "Sin tocar hace mas de 6 meses" }
    [pscustomobject]@{ Archivo = $f.Name; Tipo = $t; MB = "{0:N1}" -f ($f.Length / 1MB); Dias = $dias
                       Sugerencia = ($sug -join " / "); Ruta = $f.FullName; Bytes = $f.Length }
}
$filasDesc | Select-Object Archivo, Tipo, MB, Dias, Sugerencia, Ruta | Export-Csv (Join-Path $salida "descargas.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
$tDesc = ($archDesc | Measure-Object Length -Sum).Sum
L "== DESCARGAS =="
L ("Total: {0} en {1:N0} archivos (lista completa en descargas.csv)" -f (Tam $tDesc), $archDesc.Count)
foreach ($g in ($filasDesc | Group-Object Tipo | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending)) {
    L ("   {0,10}  {1} ({2})" -f (Tam (($g.Group | Measure-Object Bytes -Sum).Sum)), $g.Name, $g.Count)
}
$dDup = @($filasDesc | Where-Object { $_.Sugerencia -like 'Duplicado*' })
$dIns = @($filasDesc | Where-Object { $_.Sugerencia -like 'Instalador antiguo*' })
$dZip = @($filasDesc | Where-Object { $_.Sugerencia -like 'Ya esta descomprimido*' -or $_.Sugerencia -like 'Comprimido antiguo*' })
$dOld = @($filasDesc | Where-Object { $_.Dias -gt 180 })
L ("   Duplicados: {0} archivos, {1}" -f $dDup.Count, (Tam (($dDup | Measure-Object Bytes -Sum).Sum)))
L ("   Instaladores de mas de 30 dias: {0}, {1}" -f $dIns.Count, (Tam (($dIns | Measure-Object Bytes -Sum).Sum)))
L ("   Comprimidos de mas de 30 dias: {0}, {1}" -f $dZip.Count, (Tam (($dZip | Measure-Object Bytes -Sum).Sum)))
L ("   Todo lo que lleva mas de 6 meses sin tocar: {0}, {1}" -f $dOld.Count, (Tam (($dOld | Measure-Object Bytes -Sum).Sum)))
L "   Los 10 mas grandes:"
$filasDesc | Select-Object -First 10 | ForEach-Object { L ("   {0,10}  {1}  ({2} dias){3}" -f (Tam $_.Bytes), $_.Archivo, $_.Dias, $(if ($_.Sugerencia) { "  -> " + $_.Sugerencia } else { "" })) }
L ""

# ---------- 5) Programas instalados ----------
$progs = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName -and $_.EstimatedSize } |
    Sort-Object EstimatedSize -Descending |
    Select-Object @{n = 'Programa'; e = { $_.DisplayName } }, @{n = 'GB'; e = { "{0:N2}" -f ($_.EstimatedSize / 1MB) } },
                  @{n = 'Instalado'; e = { $_.InstallDate } }, @{n = 'Editor'; e = { $_.Publisher } }
$progs | Export-Csv (Join-Path $salida "programas.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
L "== PROGRAMAS MAS GRANDES (segun Windows) =="
$progs | Select-Object -First 15 | ForEach-Object { L ("{0,8} GB  {1}" -f $_.GB, $_.Programa) }
L ""

# ---------- 6) Recorrido completo de los discos ----------
$todasCarpetas = @(); $grandes = @(); $especiales = @(); $cand = New-Object System.Collections.Generic.List[object]
foreach ($u in $Unidades) {
    if (-not (Test-Path "$u\")) { continue }
    Write-Host "`nRecorriendo $u (puede tardar varios minutos)..." -ForegroundColor Cyan
    $saltar = @("$u\Windows", "$u\`$Recycle.Bin", "$u\System Volume Information", "$u\`$WinREAgent", "$u\Recovery")
    $prog = [Action[string]] { param($x) $t = if ($x.Length -gt 100) { "..." + $x.Substring($x.Length - 97) } else { $x }; Write-Host ("`r  " + $t.PadRight(100)) -NoNewline }
    $r = [Escaner]::Escanear("$u\", 3, 1GB, 20MB, $saltar, $prog)
    Write-Host ("`r  {0:N0} archivos, {1}, {2:N0} carpetas sin permiso".PadRight(100) -f $r.Archivos, (Tam $r.Bytes), $r.SinPermiso)
    foreach ($k in $r.Carpetas.Keys) {
        if ($r.Carpetas[$k] -ge 1GB) {
            $niv = ($k.TrimEnd('\').Split('\').Count - 1)
            $todasCarpetas += [pscustomobject]@{ Ruta = $k; Nivel = $niv; GB = (GB $r.Carpetas[$k]); Bytes = $r.Carpetas[$k] }
        }
    }
    $grandes += $r.Grandes
    $especiales += $r.Especiales.Values
    $cand.AddRange([object[]]$r.CandDup)
}
$todasCarpetas | Sort-Object Bytes -Descending | Select-Object Ruta, Nivel, GB | Export-Csv (Join-Path $salida "carpetas.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
$grandes | Sort-Object Bytes -Descending | Select-Object Ruta, @{n = 'GB'; e = { GB $_.Bytes } }, @{n = 'Fecha'; e = { $_.Fecha.ToString('yyyy-MM-dd') } } |
    Export-Csv (Join-Path $salida "grandes.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
$especiales | Where-Object { $_.Bytes -ge 10MB } | Sort-Object Bytes -Descending |
    Select-Object Tipo, Ruta, @{n = 'GB'; e = { GB $_.Bytes } }, @{n = 'Ultimo_cambio'; e = { $_.Fecha.ToString('yyyy-MM-dd') } } |
    Export-Csv (Join-Path $salida "especiales.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8

L "== CARPETAS MAS GRANDES (nivel 1 y 2) =="
$todasCarpetas | Where-Object { $_.Nivel -le 2 } | Sort-Object Bytes -Descending | Select-Object -First 30 | ForEach-Object { L ("{0,10}  {1}" -f (Tam $_.Bytes), $_.Ruta) }
L ""
L "== CARPETAS REGENERABLES (node_modules, entornos, caches de edicion) =="
$porTipo = $especiales | Group-Object Tipo | ForEach-Object { [pscustomobject]@{ Tipo = $_.Name; N = $_.Count; Bytes = ($_.Group | Measure-Object Bytes -Sum).Sum } } | Sort-Object Bytes -Descending
foreach ($t in $porTipo) { L ("{0,10}  {1} ({2} carpetas)" -f (Tam $t.Bytes), $t.Tipo, $t.N) }
L ""

# ---------- 7) Duplicados ----------
Write-Host "`nBuscando archivos duplicados entre $($cand.Count) archivos grandes..." -ForegroundColor Cyan
$dups = @()
$grupos = $cand | Group-Object Bytes | Where-Object { $_.Count -gt 1 }
foreach ($g in $grupos) {
    $porHuella = $g.Group | ForEach-Object { [pscustomobject]@{ F = $_; H = [Escaner]::Huella($_.Ruta, $_.Bytes) } } |
                 Where-Object { $_.H } | Group-Object H | Where-Object { $_.Count -gt 1 }
    foreach ($h in $porHuella) {
        $n = $h.Count; $len = [int64]$g.Name
        $dups += [pscustomobject]@{ Copias = $n; GB_cada_uno = (GB $len); GB_recuperables = (GB ($len * ($n - 1))); Bytes = $len * ($n - 1)
                                    Archivos = (($h.Group | ForEach-Object { $_.F.Ruta }) -join "  |  ") }
    }
}
$dups = $dups | Sort-Object Bytes -Descending
$dups | Select-Object Copias, GB_cada_uno, GB_recuperables, Archivos | Export-Csv (Join-Path $salida "duplicados.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
L "== DUPLICADOS (archivos de mas de 20 MB con mismo contenido) =="
L ("{0} grupos, {1} recuperables si dejas una sola copia" -f @($dups).Count, (Tam (($dups | Measure-Object Bytes -Sum).Sum)))
$dups | Select-Object -First 15 | ForEach-Object { L ("{0,10}  x{1}  {2}" -f (Tam $_.Bytes), $_.Copias, $_.Archivos) }

$informe | Set-Content (Join-Path $salida "resumen.txt") -Encoding UTF8
Write-Host "`n`nINFORME TERMINADO en: $salida" -ForegroundColor Green
Write-Host "Ya puedes decirle a Claude que lo lea." -ForegroundColor Green
Start-Process explorer.exe $salida
Read-Host "Pulsa Enter para cerrar"
