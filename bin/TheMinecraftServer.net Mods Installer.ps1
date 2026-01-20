$minecraftVersion = "1.21.7"
$minecraftDirectory = "$env:APPDATA\.minecraft"
$scriptRoot = $PSScriptRoot
$modsSource = Join-Path $scriptRoot "mods"
$modsDestination = "$minecraftDirectory\mods"
$debug = $false
try {
    $windowTitle = "TheMinecraftServer.net Mods Installer - Version $minecraftVersion"
    try { if ($Host -and $Host.UI -and $Host.UI.RawUI) { $Host.UI.RawUI.WindowTitle = $windowTitle } } catch {}
    try { [Console]::Title = $windowTitle } catch {}
} 
catch {
    # Ignore if unable to set window title
}
# Set console window icon (best-effort)
function Set-ConsoleWindowIcon {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IconPath
    )
    try {
        if (-not (Test-Path -LiteralPath $IconPath)) { return }
        if (-not ("Win32.ConsoleIcon" -as [type])) {
            Add-Type -Namespace Win32 -Name ConsoleIcon -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll", SetLastError=true)]
public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
[DllImport("user32.dll", SetLastError=true)]
public static extern IntPtr LoadImage(IntPtr hInst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);
public const int WM_SETICON = 0x0080;
public const int ICON_SMALL = 0;
public const int ICON_BIG = 1;
public const uint IMAGE_ICON = 1;
public const uint LR_LOADFROMFILE = 0x0010;
'@
        }

        $hWnd = [Win32.ConsoleIcon]::GetConsoleWindow()
        if ($hWnd -eq [IntPtr]::Zero) { return }

        $hSmall = [Win32.ConsoleIcon]::LoadImage([IntPtr]::Zero, $IconPath, [Win32.ConsoleIcon]::IMAGE_ICON, 16, 16, [Win32.ConsoleIcon]::LR_LOADFROMFILE)
        $hBig = [Win32.ConsoleIcon]::LoadImage([IntPtr]::Zero, $IconPath, [Win32.ConsoleIcon]::IMAGE_ICON, 32, 32, [Win32.ConsoleIcon]::LR_LOADFROMFILE)
        if ($hSmall -ne [IntPtr]::Zero) {
            [void][Win32.ConsoleIcon]::SendMessage($hWnd, [Win32.ConsoleIcon]::WM_SETICON, [IntPtr][Win32.ConsoleIcon]::ICON_SMALL, $hSmall)
        }
        if ($hBig -ne [IntPtr]::Zero) {
            [void][Win32.ConsoleIcon]::SendMessage($hWnd, [Win32.ConsoleIcon]::WM_SETICON, [IntPtr][Win32.ConsoleIcon]::ICON_BIG, $hBig)
        }
    }
    catch {
        # Ignore if host does not support setting the icon
    }
}

$iconPath = Join-Path $scriptRoot "server-icon.ico"
Set-ConsoleWindowIcon -IconPath $iconPath
# Attempt to reduce console font size for a "zoomed out" look (best-effort)
function Set-ConsoleFontSize {
    param(
        [int]$Size = 14,
        [string]$FontName = 'Consolas'
    )
    try {
        if (-not ("Win32.ConsoleFont" -as [type])) {
            Add-Type -Namespace Win32 -Name ConsoleFont -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetCurrentConsoleFontEx(IntPtr consoleOutput, bool maximumWindow, ref CONSOLE_FONT_INFO_EX consoleFont);
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct CONSOLE_FONT_INFO_EX {
    public uint cbSize;
    public uint nFont;
    public COORD dwFontSize;
    public int FontFamily;
    public int FontWeight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)]
    public string FaceName;
}
[StructLayout(LayoutKind.Sequential)]
public struct COORD {
    public short X;
    public short Y;
}
'@
        }

        $handle = [Win32.ConsoleFont]::GetStdHandle(-11) # STD_OUTPUT_HANDLE
        $cfi = New-Object Win32.ConsoleFont+CONSOLE_FONT_INFO_EX
        $cfi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($cfi)
        $cfi.FaceName = $FontName
        $cfi.dwFontSize = New-Object Win32.ConsoleFont+COORD
        $cfi.dwFontSize.X = 0
        $cfi.dwFontSize.Y = [short]$Size
        $cfi.FontFamily = 54
        $cfi.FontWeight = 400
        [void][Win32.ConsoleFont]::SetCurrentConsoleFontEx($handle, $false, [ref]$cfi)
    }
    catch {
        # Ignore if host does not support changing the console font
    }
}

Set-ConsoleFontSize -Size 10
# Center all console text output helpers (place this at $PLACEHOLDER$)
function Get-ConsoleWidth {
    try { return $Host.UI.RawUI.WindowSize.Width } catch { return [Console]::WindowWidth }
}

function Center-WriteLine {
    param(
        [string]$Line,
        $ForegroundColor = [ConsoleColor]::White,
        $BackgroundColor = [ConsoleColor]::Black,
        [switch]$NoNewLine
    )

    function Convert-ToConsoleColor($val, $default) {
        if ($val -is [System.ConsoleColor]) { return $val }
        $s = [string]$val
        if ($s -match '::') { $s = $s.Split('::')[-1] }
        $s = $s.Trim('[',']','"',"'",' ')
        try {
            return [System.Enum]::Parse([System.ConsoleColor], $s)
        } catch {
            return $default
        }
    }

    if ($null -eq $Line) { $Line = '' }
    $width = Get-ConsoleWidth
    $len = ($Line -replace "`r","").Length
    if ($len -ge $width -or $width -le 0) {
        # Too long or unknown width: just write normally
        if ($NoNewLine) { [Console]::Write($Line) } else { [Console]::WriteLine($Line) }
        return
    }

    $pad = [int]([Math]::Floor(($width - $len) / 2))
    $spaces = ' ' * $pad

    $oldFg = [Console]::ForegroundColor
    $oldBg = [Console]::BackgroundColor
    try {
        $fgColor = Convert-ToConsoleColor $ForegroundColor $oldFg
        $bgColor = Convert-ToConsoleColor $BackgroundColor $oldBg
        [Console]::ForegroundColor = $fgColor
        [Console]::BackgroundColor = $bgColor
    } catch {}
    if ($NoNewLine) { [Console]::Write($spaces + $Line) } else { [Console]::WriteLine($spaces + $Line) }
    try {
        [Console]::ForegroundColor = $oldFg
        [Console]::BackgroundColor = $oldBg
    } catch {}
}

# Override Write-Host to center text (supports -ForegroundColor, -BackgroundColor and -NoNewline)
function Write-Host {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(ValueFromPipeline=$true, Position=0, ValueFromRemainingArguments=$true)]
        $Object,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black,
        [switch]$NoNewline
    )
    process {
        $text = if ($Object -is [System.Array]) { ($Object -join ' ') } else { [string]$Object }
        # preserve multiple lines
        $text -split "`n" | ForEach-Object {
            Center-WriteLine -Line ($_ -replace "`r","") -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewLine:$NoNewline
        }
    }
}

# Override Write-Output to center text (most uses in this script are user-facing)
function Write-Output {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true, Position=0)]
        $InputObject
    )
    process {
        $text = [string]$InputObject
        $text -split "`n" | ForEach-Object {
            Center-WriteLine -Line ($_ -replace "`r","") -ForegroundColor [ConsoleColor]::White -BackgroundColor [ConsoleColor]::Black
        }
    }
}
try {
    [Console]::BackgroundColor = 'Black'
    [Console]::ForegroundColor = 'White'
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $raw = $Host.UI.RawUI
        $raw.BackgroundColor = 'Black'
        $raw.ForegroundColor = 'White'
    }
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
}
catch {
    # Host may not support color changes; ignore
}

# Attempt to remove scroll bars by making the buffer exactly the window size (best-effort)
try {
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $raw = $Host.UI.RawUI
        $win = $raw.WindowSize
        $raw.BufferSize = New-Object System.Management.Automation.Host.Size ($win.Width, $win.Height)
        $raw.WindowPosition = New-Object System.Management.Automation.Host.Coordinates (0,0)
    }
}
catch {
    # Host may not support buffer/window changes; ignore
}
# Attempt to resize the console to fit the banner nicely (best-effort, clamped to host limits)
try {
    $raw = $Host.UI.RawUI
    $desiredWidth = 120
    $desiredHeight = 40

    $maxWidth = $raw.MaxPhysicalWindowSize.Width
    $maxHeight = $raw.MaxPhysicalWindowSize.Height

    $newWidth = [Math]::Min($desiredWidth, $maxWidth)
    $newHeight = [Math]::Min($desiredHeight, $maxHeight)

    # Set buffer to exactly the window size to avoid vertical scrolling
    $raw.BufferSize = New-Object System.Management.Automation.Host.Size ($newWidth, $newHeight)
    $raw.WindowSize = New-Object System.Management.Automation.Host.Size ($newWidth, $newHeight)

    # Ensure window shows from the top-left and cursor is at the top-left
    $raw.WindowPosition = New-Object System.Management.Automation.Host.Coordinates (0, 0)
    $raw.CursorPosition = New-Object System.Management.Automation.Host.Coordinates (0, 0)

    # Clear to ensure the buffer/window start at the top
    Clear-Host
}
catch {
    # If resizing/positioning fails (remote session, restricted host, etc.), continue without stopping the script
}
try {
    # Fallbacks for hosts that ignore RawUI sizing (e.g., Windows Terminal)
    mode con: cols=$desiredWidth lines=$desiredHeight | Out-Null
    if ($env:WT_SESSION) {
        # Request terminal resize via ANSI escape sequence (rows;cols)
        [Console]::Write("`e[8;{0};{1}t" -f $desiredHeight, $desiredWidth)
    }
}
catch {
    # Ignore if host does not support resizing
}
try {
    if (-not ("Win32.ConsoleWindow" -as [type])) {
        Add-Type -Namespace Win32 -Name ConsoleWindow -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll", SetLastError=true)]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
[DllImport("user32.dll", SetLastError=true)]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
'@
    }

    Add-Type -AssemblyName System.Windows.Forms

    $hWnd = [Win32.ConsoleWindow]::GetConsoleWindow()
    if ($hWnd -ne [IntPtr]::Zero) {
        $screenW = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width
        $screenH = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height

        $SWP_NOSIZE = 0x0001
        $SWP_NOZORDER = 0x0004
        $rect = New-Object Win32.ConsoleWindow+RECT

        # Retry a few quick times so centering happens as soon as the window size is valid
        for ($i = 0; $i -lt 5; $i++) {
            if ([Win32.ConsoleWindow]::GetWindowRect($hWnd, [ref]$rect)) {
                $winWidth = $rect.Right - $rect.Left
                $winHeight = $rect.Bottom - $rect.Top
                if ($winWidth -gt 0 -and $winHeight -gt 0) {
                    $newX = [Math]::Max(0, [int](($screenW - $winWidth) / 2))
                    $newY = [Math]::Max(0, [int](($screenH - $winHeight) / 2))
                    [void][Win32.ConsoleWindow]::SetWindowPos($hWnd, [IntPtr]::Zero, $newX, $newY, 0, 0, $SWP_NOSIZE -bor $SWP_NOZORDER)
                    break
                }
            }
            Start-Sleep -Milliseconds 10
        }
    }
}
catch {
    # Ignore if host does not support moving the window
}

$banner = @'
 ( ___ )                                                                                                      ( ___ )
  |   |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|   | 
  |   |                    *                                     (                                             |   | 
  |   |   *   )   )      (  `                           (       ))\ )                                       )  |   | 
  |   | ` )  /(( /(   (  )\))(  (          (    (      ))\ ) ( /(()/(   (  (    )     (  (            (  ( /(  |   | 
  |   |  ( )(_))\()) ))\((_)()\ )\  (     ))\ ( )(  ( /(()/( )\())(_)) ))\ )(  /((   ))\ )(    (     ))\ )\()) |   | 
  |   | (_(_()|(_)\ /((_|_()((_|(_) )\ ) /((_))(()\ )(_))(_)|_))(_))  /((_|()\(_))\ /((_|()\   )\ ) /((_|_))/  |   | 
  |   | |_   _| |(_|_)) |  \/  |(_)_(_/((_)) ((_|(_|(_)(_) _| |_/ __|(_))  ((_))((_|_))  ((_) _(_/((_)) | |_   |   | 
  |   |   | | | ' \/ -_)| |\/| || | ' \)) -_) _| '_/ _` |  _|  _\__ \/ -_)| '_\ V // -_)| '_|| ' \)) -_)|  _|  |   | 
  |   |   |_| |_||_\___||_|  |_||_|_||_|\___\__|_| \__,_|_|  \__|___/\___||_|  \_/ \___||_|(_)_||_|\___| \__|  |   | 
  |___|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~|___| 
 (_____)                                                                                                      (_____)
'@

$welcomeMessage = @'
//////////////////////////////////////////////
//                                          //
//  TheMinecraftServer.net Mods Installer   //
//              Version 1.21.7              //
//                                          //
//////////////////////////////////////////////
'@

$infoMessage = @'
////////////////////////////////////////////////////
//                                                //
//               This script will:                //
//                                                //
//  - Install Fabric for Minecraft                //
//  - Backup existing mods and install new mods   //
//  - Update launcher profile RAM settings        //
//                                                //
////////////////////////////////////////////////////
'@

$continueMessage = 'Press Enter to continue or Ctrl+C to cancel'

# Clear the console window before showing the installer and message
Clear-Host
Write-Host "`n"
Write-Host $banner -ForegroundColor DarkRed
Write-Host "`n"
Write-Host $welcomeMessage -ForegroundColor White
Write-Host "`n"
Write-Host $infoMessage -ForegroundColor White
Write-Host "`n`n"
Write-Host $continueMessage -ForegroundColor White

[void](Read-Host)
Clear-Host
Write-Host "`n"
Write-Host $banner -ForegroundColor DarkRed
Write-Host "`n`n`n"

#Check to see if Java is installed
$javaCheck = Get-Command java -ErrorAction SilentlyContinue
if (-not $javaCheck) {
    Write-Output "Java is not installed. Please install Java using this download link and try again:"
    Write-Output "https://www.java.com/en/download/"
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

#Check to see if Minecraft folder exists
if (-not (Test-Path -Path $minecraftDirectory)) {
    Write-Output "Minecraft folder not found at: $minecraftDirectory. Please ensure Minecraft is installed."
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

#Run Fabric Installer
try {
    $jarPath = Join-Path $scriptRoot "Fabric Installer.jar"
    # Run java and capture both stdout and stderr, suppressing direct console output
    $output = & java -jar "$jarPath" client -mcversion $minecraftVersion -dir $minecraftDirectory -downloadMinecraft 2>&1
    # If java returned a non-zero exit code, throw so the catch block runs
    if ($LASTEXITCODE -ne 0) {
        if ($debug -eq $true) {
            Write-Output "Fabric installer output:"
            Write-Output $output
        }
        throw
    }
    Write-Output "Fabric Installed successfully."
}
catch {
    Write-Output "Error: Could not install Fabric."
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

#Check if mods source folder exists
if (-not (Test-Path -Path $modsSource)) {
    Write-Output "Mods source not found: $modsSource, cancelling installation."
    exit
}

#Create mods folder in .Minecraft folder if it doesn't exist
if (-Not (Test-Path -Path $modsDestination)) {
    New-Item -ItemType Directory -Path $modsDestination | Out-Null
}

# Clear existing mods in the mods folder by moving them to an "Old mods" folder with versioning
try {
    # Get all items in the modsDestination that are not folders
    $files = Get-ChildItem -LiteralPath $modsDestination -Force -File

    # Create "Old mods" folder if it doesn't exist
    $oldModsFolder = Join-Path $modsDestination 'Old mods'
    if (-not (Test-Path -LiteralPath $oldModsFolder)) {
        New-Item -ItemType Directory -Path $oldModsFolder | Out-Null
    }

    # Determine version from mod filenames by collecting all mc<version> occurrences and choosing the most common
    $versionCounts = @{}
    foreach ($f in $files) {
        $regexMatches = [regex]::Matches($f.Name, 'mc(?<ver>\d+(?:\.\d+)*)')
        foreach ($m in $regexMatches) {
            $ver = $m.Groups['ver'].Value
            if ($ver) {
                if (-not $versionCounts.ContainsKey($ver)) { $versionCounts[$ver] = 0 }
                $versionCounts[$ver]++
            }
        }
    }

    # Select the most common detected version; fallback to configured minecraftVersion if none found
    if ($versionCounts.Count -gt 0) {
        $maxCount = ($versionCounts.Values | Measure-Object -Maximum).Maximum
        $candidates = @($versionCounts.GetEnumerator() | Where-Object { $_.Value -eq $maxCount } | ForEach-Object { $_.Key })

        if ($candidates.Count -gt 1) {
            # Pick the highest semantic version when counts tie
            $detectedVersion = $candidates | Sort-Object {[version]$_} -Descending | Select-Object -First 1
        }
        else {
            $detectedVersion = $candidates[0]
        }
    }
    else {
    $detectedVersion = $minecraftVersion
    }

    # Create version-specific folder inside "Old mods"
    $versionFolder = Join-Path $oldModsFolder $detectedVersion
    if (-not (Test-Path -LiteralPath $versionFolder)) {
        New-Item -ItemType Directory -Path $versionFolder | Out-Null
    }

    # Move non-folder items into the versioned "Old mods" folder
    foreach ($file in $files) {
        Move-Item -LiteralPath $file.FullName -Destination $versionFolder -Force -ErrorAction Stop
    }

    Write-Output "Moved existing mods to: $versionFolder"
}
catch {
    Write-Output "Error: Failed to empty mods folder. $($_.Exception.Message)"
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

try {
    Copy-Item -Path (Join-Path $modsSource '*') -Destination $modsDestination -Recurse -Force -ErrorAction Stop
    Write-Output "Mods copied successfully."
}
catch {
    Write-Output "Error copying mods: $($_.Exception.Message)"
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

#Update the launcher profile to increase max RAM to 1/3 of system RAM
try {
    $launcherProfilesPath = "$minecraftDirectory\launcher_profiles.json"
    $profilesJson = Get-Content -Path $launcherProfilesPath -Raw | ConvertFrom-Json
    # Update the fabric-loader profile to use -Xmx in gigabytes
    $targetProfileName = "fabric-loader-$minecraftVersion"
    $targetProp = $profilesJson.profiles.PSObject.Properties | Where-Object { $_.Name -eq $targetProfileName }

    if ($targetProp) {
        $totalMemoryGB = [math]::Floor((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
        $maxRamGB = [math]::Max(1, [math]::Floor($totalMemoryGB / 3))

        # Ensure the profile object has a writable javaArgs property
        if (-not ($targetProp.Value.PSObject.Properties.Name -contains 'javaArgs')) {
            $targetProp.Value | Add-Member -NotePropertyName javaArgs -NotePropertyValue "-Xmx${maxRamGB}G" -Force
        }
        else {
            $existingArgs = $targetProp.Value.javaArgs
            # Remove any existing -Xmx (M or G) and append the new -Xmx in G
            $newArgs = ($existingArgs -replace "-Xmx\d+[MG]", "").Trim()
            if ($newArgs) { $newArgs += " " }
            $newArgs += "-Xmx${maxRamGB}G"
            $targetProp.Value.javaArgs = $newArgs
        }
    }

    $profilesJson | ConvertTo-Json -Depth 10 | Set-Content -Path $launcherProfilesPath -Force
    Write-Output "Launcher profiles updated to set max RAM to ${maxRamGB}G."
}
catch {
    Write-Output "Error updating launcher profiles: $($_.Exception.Message)"
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

Write-Host "`n`n`n"
$successMessage = @'
//////////////////////////////////////////////
//                                          //
// TheMinecraftServer.net - Version 1.21.7  //
//       Mods Installed Successfully!       //
//                                          //
//////////////////////////////////////////////
'@
Write-Host $successMessage -ForegroundColor Green
Write-Host "`n`n`n"
Write-Host 'Press Enter to exit'
[void](Read-Host)
exit
