param(
    [switch]$SkipWindowTweaks,
    [switch]$ForceConsole
)
$usingCustomHost = $env:TMS_HOST_UI -eq 'gui'
$minecraftVersion = "1.21.7"
$minecraftDirectory = "$env:APPDATA\.minecraft"
$scriptRoot = $PSScriptRoot
$launcherPath = $null
if (-not $usingCustomHost -and -not $ForceConsole) {
    $launcherCandidates = @(
        (Join-Path $scriptRoot "TheMinecraftServer.net Mods Installer.exe"),
        (Join-Path (Split-Path $scriptRoot -Parent) "TheMinecraftServer.net Mods Installer.exe")
    )
    $launcherPath = $launcherCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($launcherPath) {
        Start-Process -FilePath $launcherPath | Out-Null
        exit
    }
}
$modsSource = Join-Path $scriptRoot "mods"
$modsDestination = "$minecraftDirectory\mods"
$debug = $false
$modsReleaseUrl = $env:TMS_MODS_URL
$modsReleaseSha256 = $env:TMS_MODS_SHA256
$modsReleaseTag = $env:TMS_MODS_TAG
$modsReleaseRepo = $env:TMS_MODS_REPO
if ([string]::IsNullOrWhiteSpace($modsReleaseRepo)) {
    $modsReleaseRepo = "malletbjm/TheMinecraftServer.net"
}
$modsAssetFilter = $env:TMS_MODS_FILTER
$modsAssetExtensions = $env:TMS_MODS_EXTENSIONS
if ([string]::IsNullOrWhiteSpace($modsAssetExtensions)) {
    $modsAssetExtensions = ".jar"
}

$script:modsIndicatorEnabled = $false
$script:modsIndicatorTick = 0
$script:modsIndicatorTotal = 0

function Write-StatusLine {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text
    )

    if ($usingCustomHost) {
        Microsoft.PowerShell.Utility\Write-Output ("TMS_STATUS|White|{0}" -f $Text)
    }
    else {
        Write-Host $Text
    }
}

function Start-ModsDownloadIndicator {
    param(
        [int]$Total
    )

    $script:modsIndicatorTick = 0
    $script:modsIndicatorTotal = [Math]::Max(0, $Total)
    $script:modsIndicatorEnabled = $true

    if ($usingCustomHost) {
        Write-StatusLine "Downloading Mods"
        return
    }

    try {
        [Console]::Write("Downloading Mods")
    }
    catch {
        Write-Output "Downloading Mods"
        $script:modsIndicatorEnabled = $false
    }
}

function Update-ModsDownloadIndicator {
    param(
        [int]$Current,
        [string]$Name
    )

    if (-not $script:modsIndicatorEnabled) {
        return
    }

    if ($usingCustomHost) {
        $status = "Downloading Mods"
        if ($script:modsIndicatorTotal -gt 0) {
            $status = "Downloading Mods ($Current/$script:modsIndicatorTotal)"
        }
        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $status = "${status}: $Name"
        }
        Write-StatusLine $status
        return
    }

    $spinner = @('|', '/', '-', '\')
    $char = $spinner[$script:modsIndicatorTick % $spinner.Count]
    $script:modsIndicatorTick++
    $progress = ""
    if ($script:modsIndicatorTotal -gt 0) {
        $progress = " ($Current/$script:modsIndicatorTotal)"
    }
    $namePart = ""
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $namePart = " $Name"
    }

    try {
        [Console]::Write("`rDownloading Mods$progress$namePart $char")
    }
    catch {
        $script:modsIndicatorEnabled = $false
    }
}

function Stop-ModsDownloadIndicator {
    if (-not $script:modsIndicatorEnabled) {
        return
    }

    if (-not $usingCustomHost) {
        try {
            [Console]::WriteLine()
        }
        catch {
        }
    }

    $script:modsIndicatorEnabled = $false
    Write-StatusLine "Mods downloaded successfully"
}

function Get-ModsArchive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        [string]$ExpectedSha256
    )

    $destinationDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir | Out-Null
    }

    if (Test-Path -LiteralPath $DestinationPath) {
        if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            return
        }

        $existingHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        if ($existingHash -eq $ExpectedSha256.ToUpperInvariant()) {
            return
        }

        Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
    }

    Start-ModsDownloadIndicator -Total 1
    try {
        Update-ModsDownloadIndicator -Current 1 -Name "mods archive"
        $invokeParams = @{
            Uri = $Url
            OutFile = $DestinationPath
        }
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $invokeParams.UseBasicParsing = $true
        }
        Invoke-WebRequest @invokeParams
    }
    finally {
        Stop-ModsDownloadIndicator
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $actualHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedSha256.ToUpperInvariant()) {
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            throw "Mods archive checksum mismatch."
        }
    }
}

function Ensure-ModsSource {
    if (Test-Path -LiteralPath $modsSource) {
        Remove-Item -LiteralPath $modsSource -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $modsSource | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($modsReleaseUrl)) {
        $cacheRoot = Join-Path $env:TEMP "TheMinecraftServer.net Mods Installer"
        $archivePath = Join-Path $cacheRoot ("mods-" + $minecraftVersion + ".zip")
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        }
        try {
            Get-ModsArchive -Url $modsReleaseUrl -DestinationPath $archivePath -ExpectedSha256 $modsReleaseSha256
            Expand-Archive -LiteralPath $archivePath -DestinationPath $modsSource -Force

            $nestedMods = Join-Path $modsSource "mods"
            $modsFiles = Get-ChildItem -LiteralPath $modsSource -File -Recurse -ErrorAction SilentlyContinue
            if ((Test-Path -LiteralPath $nestedMods) -and $modsFiles.Count -eq 0) {
                Copy-Item -LiteralPath (Join-Path $nestedMods "*") -Destination $modsSource -Recurse -Force
                Remove-Item -LiteralPath $nestedMods -Recurse -Force
            }
        }
        finally {
            if (Test-Path -LiteralPath $archivePath) {
                Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $cacheRoot) {
                $leftovers = Get-ChildItem -LiteralPath $cacheRoot -Force -ErrorAction SilentlyContinue
                if (-not $leftovers) {
                    Remove-Item -LiteralPath $cacheRoot -Force -ErrorAction SilentlyContinue
                }
            }
        }

        return
    }

    $extensions = $modsAssetExtensions.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
    }

    $headers = @{ "User-Agent" = "TMS-Mods-Installer" }
    if (-not [string]::IsNullOrWhiteSpace($modsReleaseTag)) {
        $releaseApi = "https://api.github.com/repos/$modsReleaseRepo/releases/tags/$modsReleaseTag"
        $release = Invoke-RestMethod -Uri $releaseApi -Headers $headers -Method Get
        if (-not $release -or -not $release.assets) {
            throw "No assets found for release tag '$modsReleaseTag'."
        }
        $assets = @($release.assets)
    }
    else {
        $releasesApi = "https://api.github.com/repos/$modsReleaseRepo/releases?per_page=100"
        $releases = Invoke-RestMethod -Uri $releasesApi -Headers $headers -Method Get
        if (-not $releases) {
            throw "No releases found for $modsReleaseRepo."
        }

        $matchingReleases = $releases | Where-Object {
            -not $_.draft -and $_.name -and $_.name -like "*$minecraftVersion*"
        }
        if (-not $matchingReleases -or $matchingReleases.Count -eq 0) {
            throw "No published release found with name containing '$minecraftVersion'."
        }

        $modsNamedReleases = @($matchingReleases | Where-Object { $_.name -like "mods-$minecraftVersion*" })
        if ($modsNamedReleases -and $modsNamedReleases.Count -gt 0) {
            $selectedRelease = $modsNamedReleases | Sort-Object { $_.published_at } -Descending | Select-Object -First 1
        }
        else {
            $selectedRelease = $matchingReleases | Sort-Object { $_.published_at } -Descending | Select-Object -First 1
        }
        if (-not $selectedRelease.assets) {
            throw "No assets found for release '$($selectedRelease.name)'."
        }
        $assets = @($selectedRelease.assets)
    }
    $filteredAssets = $assets
    if (-not [string]::IsNullOrWhiteSpace($modsAssetFilter)) {
        $filteredAssets = $assets | Where-Object { $_.name -like "*$modsAssetFilter*" }
        if (-not $filteredAssets -or $filteredAssets.Count -eq 0) {
            $filteredAssets = $assets
        }
    }

    $filteredAssets = $filteredAssets | Where-Object {
        $name = $_.name
        foreach ($ext in $extensions) {
            if ($name.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }

    if (-not $filteredAssets -or $filteredAssets.Count -eq 0) {
        if ($matchingReleases) {
            $sortedMatching = $matchingReleases | Sort-Object { $_.published_at } -Descending
            $orderedCandidates = @()
            if ($modsNamedReleases -and $modsNamedReleases.Count -gt 0) {
                $orderedCandidates += ($modsNamedReleases | Sort-Object { $_.published_at } -Descending)
            }
            $orderedCandidates += ($sortedMatching | Where-Object { $modsNamedReleases -notcontains $_ })

            foreach ($candidate in $orderedCandidates) {
                if (-not $candidate.assets) {
                    continue
                }
                $candidateAssets = @($candidate.assets)
                $candidateFiltered = $candidateAssets | Where-Object {
                    $name = $_.name
                    foreach ($ext in $extensions) {
                        if ($name.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
                            return $true
                        }
                    }
                    return $false
                }
                if ($candidateFiltered -and $candidateFiltered.Count -gt 0) {
                    $selectedRelease = $candidate
                    $filteredAssets = $candidateFiltered
                    break
                }
            }
        }
    }

    if (-not $filteredAssets -or $filteredAssets.Count -eq 0) {
        $extSummary = $modsAssetExtensions
        if ([string]::IsNullOrWhiteSpace($extSummary)) {
            $extSummary = ".jar"
        }
        throw "No matching mods assets found for Minecraft $minecraftVersion in repo '$modsReleaseRepo' (extensions: $extSummary)."
    }

    $downloads = @()
    foreach ($asset in $filteredAssets) {
        $downloadUrl = $asset.browser_download_url
        if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
            continue
        }

        $destinationPath = Join-Path $modsSource $asset.name
        if (Test-Path -LiteralPath $destinationPath) {
            Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
        }

        $downloads += [pscustomobject]@{
            Url = $downloadUrl
            Path = $destinationPath
            Name = $asset.name
        }
    }

    if (-not $downloads -or $downloads.Count -eq 0) {
        return
    }

    Start-ModsDownloadIndicator -Total $downloads.Count
    try {
        for ($i = 0; $i -lt $downloads.Count; $i++) {
            $item = $downloads[$i]
            Update-ModsDownloadIndicator -Current ($i + 1) -Name $item.Name
            $invokeParams = @{
                Uri = $item.Url
                OutFile = $item.Path
            }
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $invokeParams.UseBasicParsing = $true
            }
            Invoke-WebRequest @invokeParams
        }
    }
    finally {
        Stop-ModsDownloadIndicator
    }
}
if (-not $usingCustomHost) {
    try {
        [Console]::BackgroundColor = 'Black'
        [Console]::ForegroundColor = 'White'
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $raw = $Host.UI.RawUI
            $raw.BackgroundColor = 'Black'
            $raw.ForegroundColor = 'White'
        }
    } catch {}
}
try {
    $windowTitle = "TheMinecraftServer.net Mods Installer - Version $minecraftVersion"
    try { if ($Host -and $Host.UI -and $Host.UI.RawUI) { $Host.UI.RawUI.WindowTitle = $windowTitle } } catch {}
    try { [Console]::Title = $windowTitle } catch {}
} 
catch {
    # Ignore if unable to set window title
}
if (-not $usingCustomHost) {
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
}
if (-not $usingCustomHost) {
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

    if (-not $SkipWindowTweaks) {
        Set-ConsoleFontSize -Size 10
    }
}
if (-not $usingCustomHost) {
    # Center all console text output helpers (place this at $PLACEHOLDER$)
    function Get-ConsoleWidth {
        try { return $Host.UI.RawUI.WindowSize.Width } catch { return 120 }
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
        $fgColor = Convert-ToConsoleColor $ForegroundColor ([ConsoleColor]::White)
        $bgColor = Convert-ToConsoleColor $BackgroundColor ([ConsoleColor]::Black)
        if ($len -ge $width -or $width -le 0) {
            # Too long or unknown width: just write normally
            if ($NoNewLine) {
                $Host.UI.Write($fgColor, $bgColor, $Line)
            }
            else {
                $Host.UI.WriteLine($fgColor, $bgColor, $Line)
            }
            return
        }

        $pad = [int]([Math]::Floor(($width - $len) / 2))
        $spaces = ' ' * $pad
        if ($NoNewLine) {
            $Host.UI.Write($fgColor, $bgColor, $spaces + $Line)
        }
        else {
            $Host.UI.WriteLine($fgColor, $bgColor, $spaces + $Line)
        }
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
}
else {
    # In GUI mode, route Write-Host to standard output so the wrapper can capture it.
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
            $text -split "`n" | ForEach-Object {
                $line = ($_ -replace "`r","")
                Microsoft.PowerShell.Utility\Write-Output ("TMS_COLOR|{0}|{1}" -f $ForegroundColor, $line)
            }
        }
    }
    function Clear-Host {
        Microsoft.PowerShell.Utility\Write-Output "TMS_CLEAR"
    }
}
try {
    if (-not $usingCustomHost) {
        [Console]::BackgroundColor = 'Black'
        [Console]::ForegroundColor = 'White'
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $raw = $Host.UI.RawUI
            $raw.BackgroundColor = 'Black'
            $raw.ForegroundColor = 'White'
        }
        try { [Console]::CursorVisible = $false } catch {}
    }
    Clear-Host
}
catch {
    # Host may not support color changes; ignore
}

if (-not $SkipWindowTweaks -and -not $usingCustomHost) {
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
}

$banner = @'
 _____                                                                                                        _____
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
$bannerLines = $banner -split "`r?`n"
$bannerLines = $bannerLines | ForEach-Object { $_.TrimEnd() }
$banner = $bannerLines -join "`n"
$script:bannerText = $banner
$script:bannerLogoLineIndexes = 5..10
$script:bannerFireLineIndexes = 3..7
$script:bannerAccentLines = @{
    8 = @(
        "(_|_))",
        "_(_/((_)) ((_|(_|(_)(_",
        "(_))  ((_))((_|_))  ((_) _(_/((_))"
    )
}

function Convert-ToConsoleColor {
    param(
        $val,
        [ConsoleColor]$default
    )

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

function Write-CenteredColoredLine {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Segments,
        [Parameter(Mandatory=$true)]
        $ForegroundColors,
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
    )

    if ($Segments.Count -ne $ForegroundColors.Count) {
        $line = $Segments -join ''
        Write-Host $line -ForegroundColor DarkRed
        return
    }

    $line = $Segments -join ''
    $width = Get-ConsoleWidth
    $len = ($line -replace "`r","").Length
    $pad = if ($len -ge $width -or $width -le 0) { 0 } else { [int]([Math]::Floor(($width - $len) / 2)) }
    $spaces = ' ' * $pad
    $bgColor = Convert-ToConsoleColor $BackgroundColor ([ConsoleColor]::Black)

    try {
        $origFg = [Console]::ForegroundColor
        $origBg = [Console]::BackgroundColor

        if ($spaces) {
            $firstColor = Convert-ToConsoleColor $ForegroundColors[0] ([ConsoleColor]::DarkRed)
            [Console]::ForegroundColor = $firstColor
            [Console]::BackgroundColor = $bgColor
            [Console]::Write($spaces)
        }

        for ($i = 0; $i -lt $Segments.Count; $i++) {
            $fgColor = Convert-ToConsoleColor $ForegroundColors[$i] ([ConsoleColor]::DarkRed)
            [Console]::ForegroundColor = $fgColor
            [Console]::BackgroundColor = $bgColor
            [Console]::Write($Segments[$i])
        }

        [Console]::WriteLine()
    }
    catch {
        Write-Host $line -ForegroundColor DarkRed
    }
    finally {
        try {
            if ($null -ne $origFg) { [Console]::ForegroundColor = $origFg }
            if ($null -ne $origBg) { [Console]::BackgroundColor = $origBg }
        } catch {}
    }
}

function Write-CenteredFireLine {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Line,
        [int]$RelativeIndex = 0
    )

    $framePattern = '^(?<prefix>\s*\|\s{3}\|\s)(?<inner>.*?)(?<suffix>\s\|\s{3}\|)$'
    if (-not ($Line -match $framePattern)) {
        Write-Host $Line -ForegroundColor DarkRed
        return
    }

    $prefix = $Matches['prefix']
    $inner = $Matches['inner']
    $suffix = $Matches['suffix']

    $width = Get-ConsoleWidth
    $len = ($Line -replace "`r","").Length
    $pad = if ($len -ge $width -or $width -le 0) { 0 } else { [int]([Math]::Floor(($width - $len) / 2)) }
    $spaces = ' ' * $pad

    $baseColor = [ConsoleColor]::DarkRed
    if ($RelativeIndex -le 2) { $baseColor = [ConsoleColor]::Yellow }
    elseif ($RelativeIndex -le 5) { $baseColor = [ConsoleColor]::Red }

    try {
        $origFg = [Console]::ForegroundColor
        $origBg = [Console]::BackgroundColor

        if ($spaces) {
            [Console]::ForegroundColor = [ConsoleColor]::DarkRed
            [Console]::BackgroundColor = [ConsoleColor]::Black
            [Console]::Write($spaces)
        }

        [Console]::ForegroundColor = [ConsoleColor]::DarkRed
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::Write($prefix)

        foreach ($ch in $inner.ToCharArray()) {
            if ($ch -eq ' ') {
                [Console]::ForegroundColor = [ConsoleColor]::DarkRed
            }
            else {
                [Console]::ForegroundColor = $baseColor
            }
            [Console]::BackgroundColor = [ConsoleColor]::Black
            [Console]::Write($ch)
        }

        [Console]::ForegroundColor = [ConsoleColor]::DarkRed
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::Write($suffix)
        [Console]::WriteLine()
    }
    catch {
        Write-Host $Line -ForegroundColor DarkRed
    }
    finally {
        try {
            if ($null -ne $origFg) { [Console]::ForegroundColor = $origFg }
            if ($null -ne $origBg) { [Console]::BackgroundColor = $origBg }
        } catch {}
    }
}

function Write-CenteredAccentLine {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Line,
        [Parameter(Mandatory=$true)]
        [string[]]$AccentStrings,
        [ConsoleColor]$DefaultColor = [ConsoleColor]::White,
        [ConsoleColor]$AccentColor = [ConsoleColor]::Red
    )

    $framePattern = '^(?<prefix>\s*\|\s{3}\|\s)(?<inner>.*?)(?<suffix>\s\|\s{3}\|)$'
    if (-not ($Line -match $framePattern)) {
        Write-Host $Line -ForegroundColor $DefaultColor
        return
    }

    $prefix = $Matches['prefix']
    $inner = $Matches['inner']
    $suffix = $Matches['suffix']

    $ranges = @()
    foreach ($needle in $AccentStrings) {
        if ([string]::IsNullOrWhiteSpace($needle)) { continue }
        $idx = $inner.IndexOf($needle, [StringComparison]::Ordinal)
        if ($idx -ge 0) {
            $ranges += [pscustomobject]@{ Start = $idx; End = $idx + $needle.Length - 1 }
        }
    }

    if (-not $ranges -or $ranges.Count -eq 0) {
        Write-Host $Line -ForegroundColor $DefaultColor
        return
    }

    $ranges = $ranges | Sort-Object Start
    $merged = @()
    foreach ($r in $ranges) {
        if (-not $merged) {
            $merged += $r
            continue
        }
        $last = $merged[-1]
        if ($r.Start -le ($last.End + 1)) {
            if ($r.End -gt $last.End) { $last.End = $r.End }
        }
        else {
            $merged += $r
        }
    }

    $width = Get-ConsoleWidth
    $len = ($Line -replace "`r","").Length
    $pad = if ($len -ge $width -or $width -le 0) { 0 } else { [int]([Math]::Floor(($width - $len) / 2)) }
    $spaces = ' ' * $pad

    try {
        $origFg = [Console]::ForegroundColor
        $origBg = [Console]::BackgroundColor

        if ($spaces) {
            [Console]::ForegroundColor = [ConsoleColor]::DarkRed
            [Console]::BackgroundColor = [ConsoleColor]::Black
            [Console]::Write($spaces)
        }

        [Console]::ForegroundColor = [ConsoleColor]::DarkRed
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::Write($prefix)

        $chars = $inner.ToCharArray()
        for ($i = 0; $i -lt $chars.Length; $i++) {
            $useAccent = $false
            foreach ($r in $merged) {
                if ($i -ge $r.Start -and $i -le $r.End) { $useAccent = $true; break }
            }
            [Console]::ForegroundColor = if ($useAccent) { $AccentColor } else { $DefaultColor }
            [Console]::BackgroundColor = [ConsoleColor]::Black
            [Console]::Write($chars[$i])
        }

        [Console]::ForegroundColor = [ConsoleColor]::DarkRed
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::Write($suffix)
        [Console]::WriteLine()
    }
    catch {
        Write-Host $Line -ForegroundColor $DefaultColor
    }
    finally {
        try {
            if ($null -ne $origFg) { [Console]::ForegroundColor = $origFg }
            if ($null -ne $origBg) { [Console]::BackgroundColor = $origBg }
        } catch {}
    }
}

function Write-Banner {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Lines,
        [int[]]$LogoLineIndexes = $script:bannerLogoLineIndexes,
        [int[]]$FireLineIndexes = $script:bannerFireLineIndexes,
        [hashtable]$AccentLines = $script:bannerAccentLines
    )

    if ($usingCustomHost) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $lineColor = [ConsoleColor]::DarkRed
            if ($FireLineIndexes -contains $i) {
                $relative = [array]::IndexOf($FireLineIndexes, $i)
                if ($relative -le 2) { $lineColor = [ConsoleColor]::Yellow }
                elseif ($relative -le 5) { $lineColor = [ConsoleColor]::Red }
                else { $lineColor = [ConsoleColor]::DarkRed }
            }
            elseif ($LogoLineIndexes -contains $i) { $lineColor = [ConsoleColor]::White }
            Write-Host $Lines[$i] -ForegroundColor $lineColor
        }
        return
    }

    $framePattern = '^(?<prefix>\s*\|\s{3}\|\s)(?<inner>.*?)(?<suffix>\s\|\s{3}\|)$'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($AccentLines.ContainsKey($i) -and ($line -match $framePattern)) {
            Write-CenteredAccentLine -Line $line -AccentStrings $AccentLines[$i]
        }
        elseif ($FireLineIndexes -contains $i) {
            $relative = [array]::IndexOf($FireLineIndexes, $i)
            Write-CenteredFireLine -Line $line -RelativeIndex $relative
        }
        elseif (($LogoLineIndexes -contains $i) -and ($line -match $framePattern)) {
            Write-CenteredColoredLine -Segments @($Matches['prefix'], $Matches['inner'], $Matches['suffix']) -ForegroundColors @('DarkRed', 'White', 'DarkRed')
        }
        else {
            Write-Host $line -ForegroundColor DarkRed
        }
    }
}

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

$continueMessage = 'Press Enter to continue'

# Clear the console window before showing the installer and message
Clear-Host
Write-Host "`n"
Write-Banner -Lines $bannerLines
Write-Host "`n"
Write-Host $welcomeMessage -ForegroundColor White
Write-Host "`n"
Write-Host $infoMessage -ForegroundColor White
Write-Host "`n`n"
Write-Host $continueMessage -ForegroundColor White

[void](Read-Host)
Clear-Host
Write-Host "`n"
Write-Banner -Lines $bannerLines
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

#Ensure mods are present (download from GitHub Releases if missing)
try {
    Ensure-ModsSource
}
catch {
    Write-Output "Error: Failed to prepare mods. $($_.Exception.Message)"
    Write-Host 'Press Enter to exit'
    [void](Read-Host)
    exit
}

$modsFiles = Get-ChildItem -LiteralPath $modsSource -File -Recurse -ErrorAction SilentlyContinue
if (-not $modsFiles -or $modsFiles.Count -eq 0) {
    Write-Output "Mods source is empty: $modsSource, cancelling installation."
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
    Write-Output "Mods installed successfully."
    if (Test-Path -LiteralPath $modsSource) {
        Remove-Item -LiteralPath $modsSource -Recurse -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Output "Error installing mods: $($_.Exception.Message)"
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
