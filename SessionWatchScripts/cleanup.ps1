# PowerShell script to clean up files older than 7 days
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

# Simple logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "[$((Get-Date).ToString('HH:mm:ss'))] [$Level] $Message"
    Write-Host $logMessage
    if ($script:logFile) { $logMessage | Out-File -FilePath $script:logFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue }
}

$retentionDays = 7
$cutoffDate = (Get-Date).AddDays(-$retentionDays)

# Get script directory and define folders to clean
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:logFile = Join-Path $scriptPath "cleanup.log"

Write-Log "Starting cleanup - retention: $retentionDays days, cutoff: $($cutoffDate.ToString('MM-dd HH:mm'))"
$foldersToClean = @(
    (Join-Path $scriptPath "AVDUserProcesses"),
    (Join-Path $scriptPath "AVDUserSessions")
)

foreach ($folder in $foldersToClean) {
    if (Test-Path $folder) {
        # Get files older than retention period
        $filesToDelete = Get-ChildItem -Path $folder -File | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        if ($filesToDelete.Count -gt 0) {
            Write-Log "Deleting $($filesToDelete.Count) old files in $(Split-Path $folder -Leaf)"
            foreach ($file in $filesToDelete) {
                try {
                    Remove-Item -Path $file.FullName -Force
                } catch {
                    Write-Log "Error deleting $($file.Name): $_" "ERROR"
                }
            }
        }
    }
}

# Truncate log files to keep them below 10MB
$maxLogSizeBytes = 1 * 1024 * 1024  # 10MB

# Find log files in the folder
$logFiles = Get-ChildItem -Path $scriptPath -Filter "*.log" -File

Write-Log "Starting log truncation - max size: $maxLogSizeBytes bytes for $logFiles"
        
foreach ($logFile in $logFiles) {
    if ($logFile.Length -gt $maxLogSizeBytes) {
        Write-Log "Truncating $($logFile.Name) - $([math]::Round($logFile.Length / 1MB, 1))MB"
                
        try {
            # Read the last 75% of the file to keep recent entries
            $keepBytes = [math]::Floor($logFile.Length * 0.75)
            $skipBytes = $logFile.Length - $keepBytes
                    
            # Read the file content to keep
            $fileStream = [System.IO.File]::OpenRead($logFile.FullName)
            $fileStream.Seek($skipBytes, [System.IO.SeekOrigin]::Begin) | Out-Null
                    
            $buffer = New-Object byte[] $keepBytes
            $fileStream.Read($buffer, 0, $keepBytes) | Out-Null
            $fileStream.Close()
                    
            # Convert to text and find the first complete line
            $text = [System.Text.Encoding]::UTF8.GetString($buffer)
            $firstNewlineIndex = $text.IndexOf("`n")
            if ($firstNewlineIndex -gt 0) {
                $text = $text.Substring($firstNewlineIndex + 1)
            }
                    
            # Add truncation marker at the beginning
            $truncationMarker = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] === LOG FILE TRUNCATED - KEEPING RECENT ENTRIES ===`n"
            $text = $truncationMarker + $text
                    
            # Write the truncated content back to the file
            [System.IO.File]::WriteAllText($logFile.FullName, $text, [System.Text.Encoding]::UTF8)
                    
        } catch {
            Write-Log "Error truncating $($logFile.Name): $_" "ERROR"
        }
    }
}


Write-Log "Cleanup completed"