<#
.SYNOPSIS
    Stops the video wallpaper process started by Start-VideoWallpaper.ps1.

.DESCRIPTION
    This script reads a Process ID (PID) from a temporary file created by the start script
    ($env:TEMP\videowallpaper.pid), terminates the corresponding mpv process, and cleans up
    the PID file.

.EXAMPLE
    .\Stop-VideoWallpaper.ps1
    This command stops the currently running video wallpaper.

.NOTES
    Author: Jules (AI Assistant)
    Version: 1.0
    Requires: The PID file 'videowallpaper.pid' to exist in the temp directory.
#>
[CmdletBinding()]
param ()

$pidFilePath = Join-Path $env:TEMP "videowallpaper.pid"

# --- Check if the PID file exists ---
if (-not (Test-Path -Path $pidFilePath -PathType Leaf)) {
    Write-Warning "PID file not found. Is the video wallpaper currently running?"
    Write-Warning "If you believe it is, you may need to stop the 'mpv.exe' process manually using Task Manager."
    exit 0 # Exit gracefully as there's nothing to do.
}

# --- Read Process ID from file ---
try {
    $processId = Get-Content -Path $pidFilePath
    # Validate that the content is a number
    if ($processId -notmatch '^\d+$') {
        Write-Error "The PID file at '$pidFilePath' contains invalid data: '$processId'."
        Write-Error "Please remove the file and stop the 'mpv.exe' process manually."
        exit 1
    }
}
catch {
    Write-Error "Failed to read the PID file at '$pidFilePath'."
    Write-Error $_.Exception.Message
    exit 1
}

# --- Stop the Process ---
Write-Host "Attempting to stop video wallpaper process with ID: $processId"
try {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue

    if ($null -ne $process) {
        # Check if the process to be stopped is indeed mpv
        if ($process.ProcessName -eq 'mpv') {
            Stop-Process -Id $processId -Force
            Write-Host "Process $processId (mpv.exe) has been terminated."
        } else {
            Write-Warning "The process with ID $processId is not 'mpv'. It is '$($process.ProcessName)'."
            Write-Warning "Aborting for safety. Please check the PID file and stop the process manually if needed."
            exit 1
        }
    } else {
        Write-Warning "No process with ID $processId was found. It may have already been stopped."
    }
}
catch {
    Write-Error "An error occurred while trying to stop the process."
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    # --- Clean up the PID file ---
    Write-Verbose "Cleaning up PID file: $pidFilePath"
    Remove-Item -Path $pidFilePath -ErrorAction SilentlyContinue
}

Write-Host "Video wallpaper stopped successfully."
