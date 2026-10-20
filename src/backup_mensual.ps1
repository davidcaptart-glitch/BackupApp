# ============================================================
#  BACKUP
#  Copia diferencial (espejo) a uno o varios discos de backup.
#  - Detecta solo los discos registrados que esten conectados
#  - Cada carpeta vive en un disco; el reparto es automatico
#  - Solo copia lo nuevo o modificado y borra lo que ya no existe
#  - Comprime con NTFS y propone liberar carpetas sin uso
# ============================================================

param([switch]$DesdeBandeja)

. (Join-Path $PSScriptRoot "config.ps1")

$ws = New-Object -ComObject WScript.Shell
# Botones: 0=OK, 1=OK/Cancelar, 4=Si/No | Iconos: 16=error, 32=pregunta, 48=aviso, 64=info | 4096=siempre encima
function Aviso($texto, $flags) { return $ws.Popup($texto, 0, $Titulo, $flags + 4096) }
function GB($b) { "{0:N1} GB" -f ($b / 1GB) }

New-Item -ItemType Directory -Path $CarpetaLogs -Force | Out-Null
$Log = Join-Path $CarpetaLogs ("backup_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".log")

# 1) Hay carpetas y discos registrados?
if (-not $Carpetas) {
    Aviso ("Todavia no has elegido que carpetas copiar.`n`n" +
           "Clic derecho en el escudo > Anadir carpeta.") 48 | Out-Null
    exit
}
$registrados = @(LeerDiscos)
if (-not $registrados) {
    Aviso ("Aun no tienes ningun disco de backup registrado.`n`n" +
           "Conecta un disco externo: el icono del escudo te ofrecera registrarlo.`n" +
           "(Tambien: clic derecho en el escudo > Discos de backup > Registrar disco conectado)") 48 | Out-Null
    exit
}

# 2) Esperar a que haya al menos un disco registrado conectado
$conectados = @(DiscosConectados)
$pendientes = @($registrados | Where-Object { DiscoToca $_ } | ForEach-Object { $_.Nombre })
if (-not $DesdeBandeja -or -not $conectados) {
    while (-not $conectados) {
        $txt = "Conecta un disco de backup y pulsa ACEPTAR.`n`nDiscos registrados: " + (($registrados | ForEach-Object { $_.Nombre }) -join ", ")
        if ($pendientes) { $txt += "`nToca copiar: " + ($pendientes -join ", ") }
        $r = Aviso ($txt + "`n`nCANCELAR = mas tarde (el icono te lo recordara).") 65
        if ($r -ne 1) { exit }
        $conectados = @(DiscosConectados)
    }
}

$resumen  = @()
$hayError = $false

foreach ($disco in $conectados) {
    Add-Content $Log "===== DISCO $($disco.Nombre) ($($disco.Letra)) ====="
    New-Item -ItemType Directory -Path $disco.Raiz -Force | Out-Null

    # 3) Compresion (solo NTFS)
    if ($disco.Formato -eq "NTFS") { compact.exe /c /i /q "$($disco.Raiz)" | Out-Null }
    else { Add-Content $Log "Formato $($disco.Formato): sin compresion" }

    # 4) Reparto: asignar carpetas nuevas y quedarnos con las de este disco
    $rep = AsignarNuevas
    $unidades = @(UnidadesActuales | Where-Object { $rep[$_.Clave] -eq $disco.Id })

    # 5) Aviso de espacio previsto
    $tam = LeerTamUnidades
    $previsto = ($unidades | ForEach-Object { [int64]$tam[$_.Clave] } | Measure-Object -Sum).Sum
    if ($previsto -gt $disco.Capacidad) {
        $r = Aviso ("Atencion: a '$($disco.Nombre)' le corresponden $(GB $previsto), pero el disco tiene $(GB $disco.Capacidad).`n" +
                    "Conviene registrar otro disco: las carpetas nuevas iran al que tenga mas espacio.`n`nCopiar igualmente?") 52
        if ($r -ne 6) { $resumen += "$($disco.Nombre): cancelado por falta de espacio"; continue }
    }

    # 6) Copia diferencial de cada unidad
    $errores = @()
    foreach ($u in $unidades) {
        if ($u.Tipo -eq 'carpeta') {
            $dst = Join-Path $disco.Raiz (Join-Path $u.Carpeta.Destino $u.Nombre)
            robocopy $u.Clave $dst /XD @Excluir /MIR /FFT /XJ /R:1 /W:2 /MT:8 /NP /NDL /LOG+:"$Log" | Out-Null
            if ($LASTEXITCODE -ge 8) { $errores += "$($u.Clave) (codigo $LASTEXITCODE)" }
        } else {
            # Archivos sueltos de la raiz: copiar solo los de primer nivel y borrar los que ya no existen
            $dst = Join-Path $disco.Raiz $u.Carpeta.Destino
            robocopy $u.Carpeta.Origen $dst /FFT /R:1 /W:2 /NP /NDL /LOG+:"$Log" | Out-Null
            if ($LASTEXITCODE -ge 8) { $errores += "$($u.Carpeta.Origen)\* (codigo $LASTEXITCODE)" }
            Get-ChildItem -LiteralPath $dst -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $u.Carpeta.Origen $_.Name)) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    # 7) Espejo: borrar del disco las carpetas que ya no existen en el origen
    $actuales = @{}; UnidadesActuales | ForEach-Object { $actuales[$_.Clave] = $true }
    foreach ($k in @($rep.Keys)) {
        if ($rep[$k] -ne $disco.Id -or $actuales.ContainsKey($k) -or $k.EndsWith('\*')) { continue }
        $c = $Carpetas | Where-Object { DentroDe $k $_.Origen } | Select-Object -First 1
        if (-not $c -or -not (Test-Path -LiteralPath $c.Origen)) { continue }   # si el disco de origen no esta, no tocar nada
        $dst = Join-Path $disco.Raiz (Join-Path $c.Destino (Split-Path $k -Leaf))
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
        $rep.Remove($k)
    }
    GuardarReparto $rep

    # 8) Guardar fecha de copia de este disco
    $lista = @(LeerDiscos)
    foreach ($d in $lista) { if ($d.Id -eq $disco.Id) { $d.UltimaCopia = (Get-Date -Format "yyyy-MM-dd HH:mm"); $d.Capacidad = $disco.Capacidad } }
    GuardarDiscos $lista

    $libre = (New-Object IO.DriveInfo $disco.Letra).AvailableFreeSpace
    if ($errores) {
        $hayError = $true
        $resumen += "$($disco.Nombre) ($($disco.Letra)): CON ERRORES en`n   " + ($errores -join "`n   ")
    } else {
        $resumen += "$($disco.Nombre) ($($disco.Letra)): correcto, $($unidades.Count) carpetas, libre $(GB $libre)"
    }

    # ========================================================
    # 9) LIBERAR ESPACIO: carpetas de este disco sin cambios en $MesesSinUso meses
    # ========================================================
    if ($errores) { continue }
    $limite = (Get-Date).AddMonths(-$MesesSinUso)
    $candidatas = @()
    foreach ($u in ($unidades | Where-Object { $_.Tipo -eq 'carpeta' })) {
        $a = Analizar $u.Clave
        if ($a.Archivos -gt 0 -and $a.Ultimo -lt $limite -and $a.Bytes -ge ($TamMinimoMB * 1MB)) {
            $candidatas += [pscustomobject]@{
                'Carpeta'       = $u.Nombre
                'Ultimo cambio' = $a.Ultimo.ToString("yyyy-MM-dd")
                'Tamano (GB)'   = [math]::Round($a.Bytes / 1GB, 2)
                'Ruta'          = $u.Clave
                '_Backup'       = Join-Path $disco.Raiz (Join-Path $u.Carpeta.Destino $u.Nombre)
                '_Archivo'      = Join-Path $disco.Raiz (Join-Path "_ARCHIVO" (Join-Path $u.Carpeta.Destino $u.Nombre))
            }
        }
    }
    if (-not $candidatas) { continue }

    $total = ($candidatas | Measure-Object 'Tamano (GB)' -Sum).Sum
    Aviso (("En '$($disco.Nombre)' hay $($candidatas.Count) carpetas sin cambios desde hace mas de $MesesSinUso meses ({0:N1} GB).`n`n" -f $total) +
           "En la siguiente ventana selecciona las que quieras BORRAR de tu PC (Ctrl+clic para varias) y pulsa ACEPTAR.`n" +
           "Si no quieres borrar nada, pulsa CANCELAR.`n`nLas carpetas borradas se conservan siempre en $($disco.Letra)\$CarpetaBackup\_ARCHIVO.") 64 | Out-Null

    $elegidas = $candidatas | Sort-Object 'Tamano (GB)' -Descending |
                Out-GridView -Title "Selecciona las carpetas que quieres BORRAR de tu PC (quedan guardadas en '$($disco.Nombre)')" -PassThru
    if (-not $elegidas) { continue }

    $gb = ($elegidas | Measure-Object 'Tamano (GB)' -Sum).Sum
    $r  = Aviso (("Vas a BORRAR de tu PC estas $($elegidas.Count) carpetas ({0:N1} GB):`n`n" -f $gb) +
                 (($elegidas | ForEach-Object { $_.Ruta }) -join "`n") +
                 "`n`nAntes comprobare que la copia es identica. Continuar?") 308
    if ($r -ne 6) { continue }

    $archivo = Join-Path $disco.Raiz "_ARCHIVO"
    $indice  = Join-Path $archivo "indice_archivo.csv"
    New-Item -ItemType Directory -Path $archivo -Force | Out-Null
    $hechas = @(); $fallos = @()
    foreach ($e in $elegidas) {
        robocopy $e.Ruta $e._Backup /XD @Excluir /MIR /L /FFT /XJ /R:0 /W:0 /NJH /NJS /NFL /NDL | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $e._Backup)) { $fallos += "$($e.Ruta)  (la copia no coincide, no se borra)"; continue }
        try {
            New-Item -ItemType Directory -Path (Split-Path $e._Archivo -Parent) -Force | Out-Null
            $destArch = $e._Archivo
            if (Test-Path -LiteralPath $destArch) { $destArch += "_" + (Get-Date -Format "yyyyMMdd") }
            Move-Item -LiteralPath $e._Backup -Destination $destArch -ErrorAction Stop
        } catch { $fallos += "$($e.Ruta)  (no se pudo archivar, no se borra)"; continue }
        try {
            Remove-Item -LiteralPath $e.Ruta -Recurse -Force -ErrorAction Stop
            $hechas += $e
            $rep = LeerReparto; $rep.Remove($e.Ruta); GuardarReparto $rep
            [pscustomobject]@{ Fecha = (Get-Date -Format "yyyy-MM-dd"); Original = $e.Ruta; Guardado_en = $destArch; GB = $e.'Tamano (GB)' } |
                Export-Csv -Path $indice -Append -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        } catch { $fallos += "$($e.Ruta)  (archivada, pero no se pudo borrar del PC; archivo en uso?)" }
    }
    $liberado = ($hechas | Measure-Object 'Tamano (GB)' -Sum).Sum
    $resumen += ("   Liberados {0:N1} GB en tu PC ($($hechas.Count) carpetas archivadas)" -f $liberado)
    if ($fallos) { $resumen += "   No se borraron:`n   " + ($fallos -join "`n   ") }
}

# 10) Resultado final
$faltan = @(LeerDiscos | Where-Object { DiscoToca $_ } | ForEach-Object { $_.Nombre })
$txt = "Copia terminada.`n`n" + ($resumen -join "`n")
if ($faltan) { $txt += "`n`nTodavia toca copiar: " + ($faltan -join ", ") + ". Conectalo cuando puedas." }
$txt += "`n`nYa puedes desconectar los discos (usa 'Expulsar' antes)."
Aviso $txt $(if ($hayError) { 48 } else { 64 }) | Out-Null
