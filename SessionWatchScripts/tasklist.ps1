# PowerShell script to run tasklist command and save results with hostname and timestamp
# Author: GitHub Copilot
# Date: November 8, 2025

# Get current hostname
$hostname = $env:COMPUTERNAME

# Get current timestamp
$timestamp = Get-Date

# Generate filename with current date and time
$dateTimeString = Get-Date -Format "yyyyMMdd-HHmm"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputFolder = Join-Path $scriptPath "tasklist"
$outputFile = Join-Path $outputFolder "tasklist-$dateTimeString.csv"
$logFile = Join-Path $scriptPath "tasklist.log"

# Function to write both to console and log file
function Write-Log {
    param([string]$Message)
    $timestampedMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $Message
    Add-Content -Path $logFile -Value $timestampedMessage -Encoding UTF8
}

# Create output folder if it doesn't exist
if (-not (Test-Path $outputFolder)) {
    try {
        New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
        Write-Log "Created output folder: $outputFolder"
    } catch {
        Write-Log "Error creating output folder: $_"
        exit 1
    }
} else {
    Write-Log "Using existing output folder: $outputFolder"
}

# Get process information using fast Get-Process
Write-Log "Getting process information using Get-Process..."

$processedData = @()

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
                # Write-Log "Session mapping: ID $sessionId -> '$sessionName'"
            }
        }
    } catch {
        Write-Log "Error getting session info: $_"
    }
    
    # Use Get-Process - much faster than WMI
    $processes = Get-Process -IncludeUserName -ErrorAction SilentlyContinue
    
    Write-Log "Found $($processes.Count) total processes"
    
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
            
            # Write-Log "Processing: $imageName (PID: $processId, Session: $sessionId, User: '$username')"
            
            # Only include user session processes (session > 0)
            if ($sessionId -le 0) {
                # Write-Log "Skipping session 0 process: $imageName"
                continue
            }
            
            # For now, include ALL session > 0 processes regardless of username to see what we get
            # Skip system processes
            if ($username -match "NT AUTHORITY|SYSTEM") {
                # Write-Log "Skipping system process: $imageName ($username)"
                continue
            }
            
            # Get session name from our cached session info
            $sessionName = if ($sessionInfo.ContainsKey($sessionId)) { 
                $sessionInfo[$sessionId] 
            } else { 
                # Fallback if session not found in cache
                if ($sessionId -eq "1") { "console" } else { "rdp-tcp $sessionId" }
            }
            
            # Create CSV line with hostname and UTC timestamp
            $csvLine = '' + $hostname + ',' + $timestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") + ',' + $imageName + ',' + $processId + ',' + $sessionName + ',' + $sessionId + ',' + $memUsageBytes + ',' + $username + ',' + $cpuTimeSeconds
            $processedData += $csvLine
            
            # Write-Log "Added process: $imageName"
            
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
    $processedData | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Log "Task completed successfully!"
    Write-Log "CSV output saved to: $outputFile"
    Write-Log "Total processes found: $($processedData.Count)"
} catch {
    Write-Log "Error saving file: $_"
    Write-Log "Attempted path: $outputFile"
    exit 1
}