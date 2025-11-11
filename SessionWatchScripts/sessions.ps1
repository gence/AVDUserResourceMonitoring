# PowerShell script to run query user command and save results with hostname and timestamp
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

# Get current hostname
$hostname = $env:COMPUTERNAME

# Get current timestamp
$timestamp = Get-Date

# Generate filename with current date and time
$dateTimeString = Get-Date -Format "yyyyMMdd-HHmm"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputFolder = Join-Path $scriptPath "AVDUserSessions"
$outputFile = Join-Path $outputFolder "sessions-$dateTimeString.csv"
$logFile = Join-Path $scriptPath "AVDUserSessions.log"

# Function to write both to console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    Write-Host $logMessage
    
    # Write to log file if defined
    if ($logFile -and (Test-Path (Split-Path $logFile -Parent))) {
        try {
            $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
        } catch {
            Write-Host "Warning: Could not write to log file: $_"
        }
    }
}

# Create output folder if it doesn't exist
if (-not (Test-Path $outputFolder)) {
    try {
        New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
        Write-Log "Created output folder: $outputFolder"
    } catch {
        Write-Log "Error creating output folder: $_" "ERROR"
        exit 1
    }
} else {
    Write-Log "Using existing output folder: $outputFolder"
}

# Run query user command and capture output
Write-Log "Running query user command..."

try {
    $queryUserOutput = query user 2>&1
} catch {
    Write-Log "Error running query user command: $_" "ERROR"
    exit 1
}

$processedData = @()
$lines = $queryUserOutput -split "`n"

# Process data lines (skip header line if present)
$skipHeader = $true
foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -ne "") {
        # Skip the header line that starts with "USERNAME"
        if ($skipHeader -and $line -match "^\s*USERNAME") {
            $skipHeader = $false
            continue
        }
        
        # Skip empty lines and process data lines
        if (-not $skipHeader) {
            # Parse query user output (fixed-width format) and convert to CSV
            # Typical format: USERNAME SESSIONNAME ID STATE IDLE TIME LOGON TIME
            
            # Parse the fixed-width output
            if ($line -match '^\s*(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\S*)\s+(.*)$') {
                $username = $matches[1] -replace '^>', ''  # Remove > prefix for active user
                $sessionName = $matches[2]
                $sessionId = $matches[3]
                $state = $matches[4]
                $idleTime = if ($matches[5] -eq "." -or $matches[5] -eq "") { "0" } else { $matches[5] }
                $logonTimeRaw = $matches[6].Trim()
                
                # Format session name - convert to lowercase and replace # with spaces
                $sessionName = $sessionName.ToLower() -replace '#', ' '
                
                # Convert logon time to UTC
                $logonTimeUtc = ""
                try {
                    $logonTimeLocal = [DateTime]::Parse($logonTimeRaw)
                    $logonTimeUtc = $logonTimeLocal.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                } catch {
                    $logonTimeUtc = $logonTimeRaw
                }
                
                # Create CSV line with hostname and UTC timestamp
                $csvLine = $timestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") + ',' + $hostname + ',' + $username + ',' + $sessionName + ',' + $sessionId + ',' + $state + ',' + $idleTime + ',' + $logonTimeUtc
                $processedData += $csvLine
            } elseif ($line -match '^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\S*)\s+(.*)$') {
                # Handle disconnected sessions (no session name)
                $username = $matches[1] -replace '^>', ''  # Remove > prefix for active user
                $sessionName = ""
                $sessionId = $matches[2]
                $state = $matches[3]
                $idleTime = if ($matches[4] -eq "." -or $matches[4] -eq "") { "0" } else { $matches[4] }
                $logonTimeRaw = $matches[5].Trim()
                
                # Convert logon time to UTC
                $logonTimeUtc = ""
                try {
                    $logonTimeLocal = [DateTime]::Parse($logonTimeRaw)
                    $logonTimeUtc = $logonTimeLocal.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                } catch {
                    $logonTimeUtc = $logonTimeRaw
                }
                
                # Create CSV line with hostname and UTC timestamp
                $csvLine = $timestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") + ',' + $hostname + ',' + $username + ',' + $sessionName + ',' + $sessionId + ',' + $state + ',' + $idleTime + ',' + $logonTimeUtc
                $processedData += $csvLine
            }
        }
    }
}

# Save to CSV file
Write-Log "Saving CSV results to $outputFile..."
#Write-Log "Current working directory: $(Get-Location)"
#Write-Log "Script directory: $scriptPath"
#Write-Log "Full output path: $outputFile"

try {
    # Use New-Item with -Value to create file without BOM
    # Use Windows-standard CRLF line endings for better AMA compatibility
    $csvContent = $processedData -join "`r`n"
    New-Item -Path $outputFile -ItemType File -Value $csvContent -Force | Out-Null
    Write-Log "Task completed successfully!"
    Write-Log "CSV output saved to: $outputFile"
    Write-Log "Total sessions found: $($processedData.Count)"
} catch {
    Write-Log "Error saving file: $_" "ERROR"
    Write-Log "Attempted path: $outputFile" "ERROR"
    exit 1
}
