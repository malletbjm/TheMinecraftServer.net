using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace Launcher
{
    internal static class Program
    {
        private const string ResourcePrefix = "assets/bin/";
        private const string AppVersion = "1.21.7";

        [STAThread]
        private static void Main()
        {
            try
            {
                string tempRoot = Path.Combine(Path.GetTempPath(), "TheMinecraftServer.net Mods Installer", AppVersion);
                string tempBin = Path.Combine(tempRoot, "bin");
                string markerPath = Path.Combine(tempRoot, "extracted.version");

                if (!File.Exists(markerPath) || File.ReadAllText(markerPath).Trim() != AppVersion)
                {
                    ExtractResources(tempRoot);
                    File.WriteAllText(markerPath, AppVersion);
                }

                string ps1Path = Path.Combine(tempBin, "TheMinecraftServer.net Mods Installer.ps1");
                if (!File.Exists(ps1Path))
                {
                    return;
                }

                var psi = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -File \"" + ps1Path + "\"")
                {
                    WorkingDirectory = tempBin,
                    UseShellExecute = false
                };
                Process.Start(psi);
            }
            catch
            {
                // Best-effort: do not block user if the launcher fails.
            }
        }

        private static void ExtractResources(string tempRoot)
        {
            string tempBin = Path.Combine(tempRoot, "bin");
            Directory.CreateDirectory(tempBin);

            Assembly asm = Assembly.GetExecutingAssembly();
            string[] resourceNames = asm.GetManifestResourceNames();
            foreach (string name in resourceNames)
            {
                if (!name.StartsWith(ResourcePrefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                string relativePath = name.Substring(ResourcePrefix.Length);
                string filePath = Path.Combine(tempBin, relativePath.Replace('/', Path.DirectorySeparatorChar));
                string? dir = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                using Stream? input = asm.GetManifestResourceStream(name);
                if (input == null)
                {
                    continue;
                }

                using FileStream output = File.Open(filePath, FileMode.Create, FileAccess.Write, FileShare.Read);
                input.CopyTo(output);
            }
        }
    }
}
