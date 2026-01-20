using System;
using System.Diagnostics;
using System.IO;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string vbsPath = Path.Combine(exeDir, "bin", "TheMinecraftServer.net Mods Installer.vbs");
            if (!File.Exists(vbsPath))
            {
                return;
            }

            var psi = new ProcessStartInfo("wscript.exe", "\"" + vbsPath + "\"")
            {
                WorkingDirectory = Path.Combine(exeDir, "bin"),
                UseShellExecute = false
            };
            Process.Start(psi);
        }
        catch
        {
            // Best-effort: do not block user if the launcher fails.
        }
    }
}
