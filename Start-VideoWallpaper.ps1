<#
.SYNOPSIS
    Sets a local video file as an animated desktop wallpaper on Windows 10/11.

.DESCRIPTION
    This script uses the lightweight media player mpv to render a video file directly onto the
    desktop background layer (WorkerW). It is designed for minimal resource consumption by leveraging
    GPU hardware acceleration and running without audio.

    It requires mpv.exe to be available in the system's PATH.

.PARAMETER VideoPath
    The full path to the local video file to be used as the wallpaper. This parameter is mandatory.

.EXAMPLE
    .\Start-VideoWallpaper.ps1 -VideoPath "C:\Users\YourUser\Videos\my-wallpaper.mp4"
    This command will start the specified video as the desktop wallpaper.

.NOTES
    Author: Jules (AI Assistant)
    Version: 1.0
    Requires: Windows 10 or Windows 11, PowerShell 5.1 or later, mpv.exe in PATH.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Please provide the full path to your video file.")]
    [string]$VideoPath
)

# --- Prerequisite Check ---
Write-Verbose "Checking for mpv.exe in system PATH..."
if (-not (Get-Command mpv.exe -ErrorAction SilentlyContinue)) {
    Write-Error "mpv.exe not found. Please download it from https://mpv.io/installation/, add it to your system's PATH, and try again."
    exit 1
}
Write-Verbose "mpv.exe found."

# --- File Existence Check ---
Write-Verbose "Checking if video file exists at path: $VideoPath"
if (-not (Test-Path -Path $VideoPath -PathType Leaf)) {
    Write-Error "The specified video file was not found at: $VideoPath"
    exit 1
}
Write-Verbose "Video file found."

# --- Win32 API P/Invoke Setup ---
# We need to use the Win32 API to find the correct window handle for the desktop.
# The target is a window with the class name "WorkerW", which is a child of "SHELLDLL_DefView".
# This C# code block makes the necessary Win32 functions available to PowerShell.
$cSharpCode = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string lclassName, string windowTitle);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static IntPtr GetWorkerW() {
        IntPtr progman = FindWindow("Progman", null);
        UIntPtr result;

        // This message is sent to Progman to create the WorkerW window if it doesn't exist.
        SendMessageTimeout(progman, 0x052C, new UIntPtr(0), IntPtr.Zero, 0x0, 1000, out result);

        IntPtr workerW = IntPtr.Zero;
        EnumWindows(new EnumWindowsProc((tophandle, topparamhandle) => {
            IntPtr p = FindWindowEx(tophandle, IntPtr.Zero, "SHELLDLL_DefView", "");
            if (p != IntPtr.Zero) {
                workerW = FindWindowEx(IntPtr.Zero, tophandle, "WorkerW", "");
            }
            return true;
        }), IntPtr.Zero);

        return workerW;
    }
}
"@

try {
    Add-Type -TypeDefinition $cSharpCode -Namespace Win32API
}
catch {
    Write-Error "Failed to compile Win32 API helper code. This script requires PowerShell 5.1+ and a .NET environment."
    Write-Error $_.Exception.Message
    exit 1
}

# --- Desktop Window Handle Detection ---
Write-Host "Searching for the desktop window handle (WorkerW)..."
$workerwHandle = [Win32API.Win32]::GetWorkerW()

if ($workerwHandle -eq [IntPtr]::Zero) {
    Write-Error "Could not find the WorkerW desktop handle. Your system may have an unusual desktop configuration."
    exit 1
}

# Format the handle as a hex string for display, but use the integer for the process.
$handleValue = $workerwHandle.ToInt64()
Write-Host "Found desktop handle: 0x$($handleValue.ToString('X'))"

# --- Launching the Video Wallpaper ---
$pidFilePath = Join-Path $env:TEMP "videowallpaper.pid"

# These are the arguments for mpv, chosen for optimal performance and appearance as a wallpaper.
$mpvArgs = @(
    "--wid=$handleValue",       # Attach to the WorkerW window handle.
    "--loop",                   # Loop the video indefinitely.
    "--no-audio",               # Mute audio.
    "--hwdec=auto",             # Use hardware decoding for minimum CPU usage.
    "--player-operation-mode=pseudo-gui", # Run as a background-style process.
    "--no-border",              # No window decorations.
    "--panscan=1.0",            # Fill the screen (for 16:9 content on a 16:9 screen).
    "'$VideoPath'"              # The path to the video file.
)

Write-Host "Starting video wallpaper..."
try {
    # Start mpv as a new process and get its details.
    $process = Start-Process mpv -ArgumentList $mpvArgs -PassThru -WindowStyle Minimized

    # Store the process ID in a temporary file for the stop script.
    $process.Id | Out-File -FilePath $pidFilePath -Encoding ascii

    Write-Host "Video wallpaper started successfully. Process ID: $($process.Id)"
    Write-Host "To stop, run the 'Stop-VideoWallpaper.ps1' script."
}
catch {
    Write-Error "Failed to start mpv.exe. Ensure it's working correctly."
    Write-Error $_.Exception.Message
    # Clean up PID file if process failed to start
    if (Test-Path $pidFilePath) {
        Remove-Item $pidFilePath
    }
    exit 1
}
