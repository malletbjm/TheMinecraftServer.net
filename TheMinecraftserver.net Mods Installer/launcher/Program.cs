using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Drawing;
using System.Runtime.InteropServices;

namespace Launcher
{
    internal static class Program
    {
        private const string ResourcePrefix = "assets/bin/";
        private const int DefaultColumns = 117;
        private const int DefaultRows = 36;
        private const string ColorPrefix = "TMS_COLOR|";
        private const string StatusPrefix = "TMS_STATUS|";
        private const string ClearMarker = "TMS_CLEAR";

        [STAThread]
        private static void Main()
        {
            EnsurePowerShellEnvironment();
            try
            {
                string exePath = Environment.ProcessPath ?? string.Empty;
                string stamp;
                if (!string.IsNullOrWhiteSpace(exePath) && File.Exists(exePath))
                {
                    var exeInfo = new FileInfo(exePath);
                    stamp = exeInfo.Length + "_" + exeInfo.LastWriteTimeUtc.Ticks;
                }
                else
                {
                    stamp = DateTime.UtcNow.Ticks.ToString();
                }
                string tempRoot = Path.Combine(Path.GetTempPath(), "TheMinecraftServer.net Mods Installer", stamp);
                string tempBin = Path.Combine(tempRoot, "bin");
                string markerPath = Path.Combine(tempRoot, "extracted.marker");
                if (!File.Exists(markerPath))
                {
                    ExtractResources(tempRoot);
                    File.WriteAllText(markerPath, "ok");
                }

                string ps1Path = Path.Combine(tempBin, "TheMinecraftServer.net Mods Installer.ps1");
                if (!File.Exists(ps1Path))
                {
                    ShowFatalError("The installer script could not be found.");
                    return;
                }
                string iconPath = Path.Combine(tempBin, "server-icon.ico");
                Icon? appIcon = TryLoadIcon(iconPath, exePath);

                Environment.SetEnvironmentVariable("TMS_HOST_UI", "gui");
                TrySetAppUserModelId("TheMinecraftServer.net.ModsInstaller");

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                var form = new MainForm(appIcon, DefaultColumns, DefaultRows);

                Task.Run(() => RunScript(form, ps1Path, tempBin));
                Application.Run(form);
            }
            catch (Exception ex)
            {
                ShowFatalError(ex.Message);
            }
        }

        private static void RunScript(MainForm form, string scriptPath, string workingDir)
        {
            try
            {
                if (!File.Exists(scriptPath))
                {
                    form.AppendLine("Launcher error: Installer script is missing.", System.Drawing.Color.Red, System.Drawing.Color.Black, true);
                    return;
                }

                string? powerShell = FindPowerShellExecutable();
                if (string.IsNullOrWhiteSpace(powerShell))
                {
                    form.AppendLine("Launcher error: PowerShell was not found on this machine.", System.Drawing.Color.Red, System.Drawing.Color.Black, true);
                    return;
                }

                using var process = new Process();
                process.StartInfo = new ProcessStartInfo
                {
                    FileName = powerShell,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    RedirectStandardInput = true,
                    CreateNoWindow = true,
                    WorkingDirectory = workingDir
                };
                process.StartInfo.ArgumentList.Add("-NoProfile");
                process.StartInfo.ArgumentList.Add("-ExecutionPolicy");
                process.StartInfo.ArgumentList.Add("Bypass");
                process.StartInfo.ArgumentList.Add("-File");
                process.StartInfo.ArgumentList.Add(scriptPath);
                process.StartInfo.Environment["TMS_HOST_UI"] = "gui";

                form.SetContinueHandler(() =>
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            process.StandardInput.WriteLine();
                            process.StandardInput.Flush();
                        }
                    }
                    catch
                    {
                    }
                });
                form.SetCloseHandler(() =>
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            process.Kill(true);
                        }
                    }
                    catch
                    {
                    }
                });

                process.Start();

                Task outputTask = PumpOutputAsync(process.StandardOutput, form, System.Drawing.Color.White, detectPrompt: true);
                Task errorTask = PumpOutputAsync(process.StandardError, form, System.Drawing.Color.Red, detectPrompt: false);

                process.WaitForExit();
                Task.WaitAll(outputTask, errorTask);
            }
            catch (Exception ex)
            {
                form.AppendLine("Launcher error: " + ex.Message, System.Drawing.Color.Red, System.Drawing.Color.Black, true);
            }
            finally
            {
                if (form.IsHandleCreated)
                {
                    form.BeginInvoke(new Action(() =>
                    {
                        form.AllowClose(true);
                        form.Close();
                    }));
                }
            }
        }

        private static async Task PumpOutputAsync(TextReader reader, MainForm form, System.Drawing.Color color, bool detectPrompt)
        {
            try
            {
                string? line;
                while ((line = await reader.ReadLineAsync().ConfigureAwait(false)) != null)
                {
                    string localLine = line;
                    if (string.Equals(localLine, ClearMarker, StringComparison.Ordinal))
                    {
                        form.ClearOutput();
                        continue;
                    }
                    System.Drawing.Color lineColor = color;
                    string outputLine = localLine;
                    if (TryParseColoredLine(localLine, out var parsedLine, out var parsedColor))
                    {
                        outputLine = parsedLine;
                        lineColor = parsedColor;
                    }

                    if (TryParseStatusLine(localLine, out var statusLine, out var statusColor))
                    {
                        form.SetStatusLine(statusLine, statusColor, System.Drawing.Color.Black, true);
                        continue;
                    }

                    form.AppendLine(outputLine, lineColor, System.Drawing.Color.Black, true);
                    if (detectPrompt && outputLine.IndexOf("Press Enter", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        form.ShowContinue(outputLine);
                    }
                }
            }
            catch
            {
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

                using Stream? resourceStream = asm.GetManifestResourceStream(name);
                if (resourceStream == null)
                {
                    continue;
                }

                using FileStream output = File.Open(filePath, FileMode.Create, FileAccess.Write, FileShare.Read);
                resourceStream.CopyTo(output);
            }
        }

        private static Icon? TryLoadIcon(string iconPath, string exePath)
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(iconPath) && File.Exists(iconPath))
                {
                    return new Icon(iconPath);
                }

                if (!string.IsNullOrWhiteSpace(exePath) && File.Exists(exePath))
                {
                    return Icon.ExtractAssociatedIcon(exePath);
                }
            }
            catch
            {
            }

            return null;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

        private static void TrySetAppUserModelId(string appId)
        {
            try
            {
                SetCurrentProcessExplicitAppUserModelID(appId);
            }
            catch
            {
            }
        }

        private static string? FindPowerShellExecutable()
        {
            string? pwsh = FindOnPath("pwsh.exe");
            if (!string.IsNullOrWhiteSpace(pwsh))
            {
                return pwsh;
            }

            return FindOnPath("powershell.exe");
        }

        private static string? FindOnPath(string name)
        {
            string? pathEnv = Environment.GetEnvironmentVariable("PATH");
            if (string.IsNullOrWhiteSpace(pathEnv))
            {
                return null;
            }

            foreach (string part in pathEnv.Split(Path.PathSeparator))
            {
                if (string.IsNullOrWhiteSpace(part))
                {
                    continue;
                }

                string candidate = Path.Combine(part.Trim(), name);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }

            return null;
        }

        private static bool TryParseColoredLine(string line, out string text, out System.Drawing.Color color)
        {
            text = line;
            color = System.Drawing.Color.White;

            if (string.IsNullOrEmpty(line) || !line.StartsWith(ColorPrefix, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            string payload = line.Substring(ColorPrefix.Length);
            string[] parts = payload.Split('|', 2);
            if (parts.Length != 2)
            {
                return false;
            }

            text = parts[1];
            color = MapConsoleColor(parts[0], System.Drawing.Color.White);
            return true;
        }

        private static bool TryParseStatusLine(string line, out string text, out System.Drawing.Color color)
        {
            text = line;
            color = System.Drawing.Color.White;

            if (string.IsNullOrEmpty(line) || !line.StartsWith(StatusPrefix, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            string payload = line.Substring(StatusPrefix.Length);
            string[] parts = payload.Split('|', 2);
            if (parts.Length != 2)
            {
                return false;
            }

            text = parts[1];
            color = MapConsoleColor(parts[0], System.Drawing.Color.White);
            return true;
        }

        private static System.Drawing.Color MapConsoleColor(string name, System.Drawing.Color fallback)
        {
            if (!Enum.TryParse(name, true, out ConsoleColor parsed))
            {
                return fallback;
            }

            return parsed switch
            {
                ConsoleColor.Black => System.Drawing.Color.Black,
                ConsoleColor.DarkBlue => System.Drawing.Color.FromArgb(0, 0, 139),
                ConsoleColor.DarkGreen => System.Drawing.Color.FromArgb(0, 100, 0),
                ConsoleColor.DarkCyan => System.Drawing.Color.FromArgb(0, 139, 139),
                ConsoleColor.DarkRed => System.Drawing.Color.FromArgb(139, 0, 0),
                ConsoleColor.DarkMagenta => System.Drawing.Color.FromArgb(139, 0, 139),
                ConsoleColor.DarkYellow => System.Drawing.Color.FromArgb(184, 134, 11),
                ConsoleColor.Gray => System.Drawing.Color.FromArgb(192, 192, 192),
                ConsoleColor.DarkGray => System.Drawing.Color.FromArgb(128, 128, 128),
                ConsoleColor.Blue => System.Drawing.Color.FromArgb(0, 0, 255),
                ConsoleColor.Green => System.Drawing.Color.FromArgb(0, 255, 0),
                ConsoleColor.Cyan => System.Drawing.Color.FromArgb(0, 255, 255),
                ConsoleColor.Red => System.Drawing.Color.FromArgb(255, 0, 0),
                ConsoleColor.Magenta => System.Drawing.Color.FromArgb(255, 0, 255),
                ConsoleColor.Yellow => System.Drawing.Color.FromArgb(255, 255, 0),
                ConsoleColor.White => System.Drawing.Color.White,
                _ => fallback
            };
        }

        private static void EnsurePowerShellEnvironment()
        {
            try
            {
                string userProfile = EnsureEnvWithFallback(
                    "USERPROFILE",
                    Environment.SpecialFolder.UserProfile,
                    Path.Combine(GetSystemDrive(), "Users", Environment.UserName));

                EnsureEnvWithFallback(
                    "HOME",
                    Environment.SpecialFolder.UserProfile,
                    userProfile);

                EnsureEnvWithFallback(
                    "APPDATA",
                    Environment.SpecialFolder.ApplicationData,
                    Path.Combine(userProfile, "AppData", "Roaming"));

                EnsureEnvWithFallback(
                    "LOCALAPPDATA",
                    Environment.SpecialFolder.LocalApplicationData,
                    Path.Combine(userProfile, "AppData", "Local"));

                string programData = EnsureEnvWithFallback(
                    "ProgramData",
                    Environment.SpecialFolder.CommonApplicationData,
                    Path.Combine(GetSystemDrive(), "ProgramData"));

                if (!string.IsNullOrWhiteSpace(programData))
                {
                    Environment.SetEnvironmentVariable("PROGRAMDATA", programData);
                }

                EnsureHomeDrivePath(userProfile);
            }
            catch
            {
            }
        }

        private static string EnsureEnvWithFallback(string name, Environment.SpecialFolder folder, string fallback)
        {
            string? current = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(current))
            {
                return current;
            }

            string path = Environment.GetFolderPath(folder);
            if (string.IsNullOrWhiteSpace(path))
            {
                path = fallback;
            }

            if (!string.IsNullOrWhiteSpace(path))
            {
                Environment.SetEnvironmentVariable(name, path);
            }

            return path;
        }

        private static void EnsureHomeDrivePath(string userProfile)
        {
            if (string.IsNullOrWhiteSpace(userProfile))
            {
                return;
            }

            string? homeDrive = Environment.GetEnvironmentVariable("HOMEDRIVE");
            string? homePath = Environment.GetEnvironmentVariable("HOMEPATH");
            if (!string.IsNullOrWhiteSpace(homeDrive) && !string.IsNullOrWhiteSpace(homePath))
            {
                return;
            }

            string drive = Path.GetPathRoot(userProfile) ?? "C:\\";
            string path = userProfile.Substring(drive.Length - 1);
            Environment.SetEnvironmentVariable("HOMEDRIVE", drive.TrimEnd('\\'));
            Environment.SetEnvironmentVariable("HOMEPATH", path);
        }

        private static string GetSystemDrive()
        {
            string? drive = Environment.GetEnvironmentVariable("SystemDrive");
            if (string.IsNullOrWhiteSpace(drive))
            {
                drive = "C:";
            }

            return drive.TrimEnd('\\');
        }

        private static void ShowFatalError(string message)
        {
            try
            {
                MessageBox.Show(
                    "The installer failed to start." + Environment.NewLine + Environment.NewLine +
                    message,
                    "Launcher error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            catch
            {
            }
        }

        // Console window management removed; the custom host UI owns sizing, centering, and icon.
    }
}
