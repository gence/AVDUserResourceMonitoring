# PowerShell script to run tasklist command and save results with hostname and timestamp
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

# Get current hostname
$hostname = $env:COMPUTERNAME

# Get current timestamp
$timestamp = Get-Date

# Generate filename with current date and time
$dateTimeString = Get-Date -Format "yyyyMMdd-HHmm"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputFolder = Join-Path $scriptPath "AVDUserProcesses"
$outputFile = Join-Path $outputFolder "processes-$dateTimeString.csv"
$logFile = Join-Path $scriptPath "AVDUserProcesses.log"

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

try {
    # Get all session information once and store in memory
    Write-Log "Getting session information..."
    $sessionInfo = @{}
    try {
        $querySessionOutput = query session
        foreach ($line in $querySessionOutput) {
            if ($line -match '^\s*(\S+)\s+(\S*)\s+(\d+)\s+') {
                $sessionName = $matches[1].ToLower() -replace '#', ' ' -replace '^>', ''
                $sessionId = [int]$matches[3]
                $sessionInfo[$sessionId] = $sessionName
            }
        }
    } catch {
        Write-Log "Error getting session info: $_" "ERROR"
    }

    # Get process information using Get-Process
    Write-Log "Getting process information using Get-Process..."
    $processes = Get-Process -IncludeUserName | Where-Object { $_.SessionId -gt 0 -and $_.UserName -notmatch '^(NT AUTHORITY\\(SYSTEM|LOCAL SERVICE|NETWORK SERVICE))$' -and $_.ProcessName -notin @('fontdrvhost','dwm','csrss') } | Select-Object ProcessName, Id, SessionId, WorkingSet64, TotalProcessorTime, UserName
    Write-Log "Found $($processes.Count) total processes"
    
    # Initialize array to hold processed data
    $processedData = @()

    foreach ($process in $processes) {
        try {
            # Get basic info
            $imageName = $process.ProcessName + ".exe"
            $processId = $process.Id
            $sessionId = $process.SessionId
            $memUsageBytes = $process.WorkingSet64
            $cpuTimeSeconds = [math]::Round($process.TotalProcessorTime.TotalSeconds, 0)
            
            # Check if UserName property exists and has value
            $username = if ($process.PSObject.Properties["UserName"] -and $process.UserName) { 
                $process.UserName 
            } else { 
                "NoUserName" 
            }
            
            # Get session name from our cached session info
            $sessionName = if ($sessionInfo.ContainsKey($sessionId)) { 
                $sessionInfo[$sessionId] 
            } else { 
                # Fallback if session not found in cache
                if ($sessionId -eq "1") { "console" } else { "rdp-tcp $sessionId" }
            }
            
            # Create CSV line with hostname and UTC timestamp
            $csvLine = $timestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") + ',' + $hostname + ',' + $imageName + ',' + $processId + ',' + $username + ',' + $sessionName + ',' + $sessionId + ',' + $memUsageBytes + ',' + $cpuTimeSeconds
            $processedData += $csvLine
            
        } catch {
            Write-Log "Error processing process $($process.ProcessName): $_"
            continue
        }
    }
} catch {
    Write-Log "Error getting process information: $_"
    exit 1
}

Write-Log "Processed $($processedData.Count) processes for output"

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
    Write-Log "Total processes found: $($processedData.Count)"
} catch {
    Write-Log "Error saving file: $_"
    Write-Log "Attempted path: $outputFile"
    exit 1
}