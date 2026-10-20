// BackupApp.exe: punto de entrada del programa.
// Arranca los scripts de PowerShell que estan junto al .exe sin mostrar ninguna ventana.
//   BackupApp.exe            -> icono de la bandeja (bandeja.ps1)
//   BackupApp.exe /copiar    -> hacer una copia ahora (backup_mensual.ps1)
//   BackupApp.exe /medir     -> medir el tamano de las carpetas (medir_tamanos.ps1)
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("BackupApp")]
[assembly: AssemblyProduct("BackupApp")]
[assembly: AssemblyDescription("Copias de seguridad a discos externos")]

static class Programa
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string opcion = args.Length > 0 ? args[0].ToLowerInvariant().TrimStart('/', '-') : "";
        string script;
        switch (opcion)
        {
            case "":       script = "bandeja.ps1"; break;
            case "copiar": script = "backup_mensual.ps1"; break;
            case "medir":  script = "medir_tamanos.ps1"; break;
            default:
                MessageBox.Show("Opcion desconocida: " + args[0] + "\n\nUso: BackupApp.exe [/copiar | /medir]", "BackupApp");
                return 2;
        }
        string ruta = Path.Combine(dir, script);
        if (!File.Exists(ruta))
        {
            MessageBox.Show("Falta el archivo " + ruta + "\n\nVuelve a instalar el programa.", "BackupApp", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        var info = new ProcessStartInfo(ps,
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + ruta + "\"");
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WorkingDirectory = dir;
        Process.Start(info);
        return 0;
    }
}
