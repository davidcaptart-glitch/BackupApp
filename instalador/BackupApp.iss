; ============================================================
;  Instalador de BackupApp (Inno Setup 6)
;  - Por usuario, sin permisos de administrador. La carpeta se puede elegir.
;  - Cierra la version anterior con salir.senal (sin perder los cambios pendientes).
;  - Tambien lo usan las actualizaciones: setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
;  Se compila con herramientas\publicar.ps1 (antes hay que ejecutar compilar.ps1).
; ============================================================
#define MiVersion Trim(FileRead(FileOpen(AddBackslash(SourcePath) + "..\VERSION")))
#define MiRepo "https://github.com/davidcaptart-glitch/BackupApp"

[Setup]
AppId={{9DEE011B-A9FD-4CC5-B01F-4A3ED6EB3129}
AppName=BackupApp
AppVersion={#MiVersion}
AppVerName=BackupApp {#MiVersion}
AppPublisher=BackupApp
AppPublisherURL={#MiRepo}
AppSupportURL={#MiRepo}/issues
AppUpdatesURL={#MiRepo}/releases
VersionInfoVersion={#MiVersion}
DefaultDirName={userpf}\BackupApp
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=BackupApp-setup-{#MiVersion}
SetupIconFile=..\recursos\BackupApp.ico
UninstallDisplayIcon={app}\BackupApp.exe
UninstallDisplayName=BackupApp
WizardStyle=modern
LicenseFile=..\LICENSE
InfoBeforeFile=privacidad.txt
WizardSizePercent=110
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "inicio"; Description: "Abrir BackupApp al iniciar Windows (recomendado: así vigila tus carpetas y te avisa)"

[Files]
Source: "..\dist\BackupApp\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[InstallDelete]
; Restos de las versiones de prueba (instalar.bat)
Type: files; Name: "{userstartup}\Backup (bandeja).lnk"
Type: files; Name: "{app}\iniciar_bandeja.vbs"
Type: files; Name: "{app}\Hacer copia ahora.bat"

[Icons]
; AppUserModelID: el mismo que declara el programa (ui.ps1), para que la barra de tareas muestre el icono de BackupApp
Name: "{userprograms}\BackupApp"; Filename: "{app}\BackupApp.exe"; AppUserModelID: "davidcaptart.BackupApp"
Name: "{userprograms}\BackupApp - Hacer copia ahora"; Filename: "{app}\BackupApp.exe"; Parameters: "/copiar"; AppUserModelID: "davidcaptart.BackupApp"
Name: "{userstartup}\BackupApp"; Filename: "{app}\BackupApp.exe"; Tasks: inicio

[Run]
Filename: "{app}\BackupApp.exe"; Description: "Abrir BackupApp ahora"; Flags: nowait postinstall skipifsilent
; En una actualizacion (modo silencioso) se vuelve a abrir solo; /SINABRIR=1 lo evita (pruebas)
Filename: "{app}\BackupApp.exe"; Flags: nowait; Check: AbrirTrasActualizar

[Code]
const
  MUTEX_ICONO = 'BackupMensualBandeja';

function AbrirTrasActualizar: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:SINABRIR|0}') = '0');
end;

function DirDatos: String;
begin
  Result := ExpandConstant('{localappdata}\BackupApp');
end;

{ Pide al icono que guarde y se cierre (salir.senal); si no responde, lo cierra a la fuerza }
function CerrarIcono: Boolean;
var
  i, Codigo: Integer;
begin
  Result := True;
  if not CheckForMutexes(MUTEX_ICONO) then Exit;
  ForceDirectories(DirDatos);
  SaveStringToFile(DirDatos + '\salir.senal', 'instalador', False);
  for i := 1 to 60 do begin
    if not CheckForMutexes(MUTEX_ICONO) then Exit;
    Sleep(500);
  end;
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name=''powershell.exe''\" | Where-Object { $_.CommandLine -like ''*bandeja.ps1*'' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"',
    '', SW_HIDE, ewWaitUntilTerminated, Codigo);
  Sleep(1000);
  DeleteFile(DirDatos + '\salir.senal');
  Result := not CheckForMutexes(MUTEX_ICONO);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not CerrarIcono then
    Result := 'No se pudo cerrar BackupApp. Ciérralo desde el icono del escudo (clic derecho > Salir) y vuelve a intentarlo.';
end;

function InitializeUninstall: Boolean;
begin
  Result := CerrarIcono;
  if not Result then
    MsgBox('No se pudo cerrar BackupApp. Ciérralo desde el icono del escudo (clic derecho > Salir) y vuelve a intentarlo.', mbError, MB_OK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DirExists(DirDatos) and not UninstallSilent then
    if MsgBox('¿Borrar también tu configuración e historial de BackupApp?' + #13#10#13#10 +
              'Las copias que hay en tus discos de backup no se tocan.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(DirDatos, True, True, True);
end;
