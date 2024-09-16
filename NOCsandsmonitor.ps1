# Description: Monitors server availability and service status, logs results to a file.

# Define the servers to monitor
$servers = @(
    "Server1",
    "Server2",
    "Server3"
)

# Define the services to check on each server
$servicesToMonitor = @(
    "Spooler",        # Print Spooler
    "wuauserv",       # Windows Update
    "LanmanServer"    # Server service
)

# Log file path
$logFile = "C:\NOC_Logs\Server_Monitoring_Log.txt"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path (Split-Path $logFile))) {
    New-Item -Path (Split-Path $logFile) -ItemType Directory
}

# Function to log output
function Log-Output {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Start monitoring
foreach ($server in $servers) {
    Log-Output "Checking server: $server"
    
    # Test server availability
    if (Test-Connection -ComputerName $server -Count 2 -Quiet) {
        Log-Output "Server $server is reachable."

        # Check the status of each service
        foreach ($service in $servicesToMonitor) {
            try {
                $serviceStatus = Get-Service -Name $service -ComputerName $server -ErrorAction Stop
                if ($serviceStatus.Status -eq 'Running') {
                    Log-Output "Service '$service' on $server is running."
                } else {
                    Log-Output "Service '$service' on $server is NOT running."
                }
            }
            catch {
                Log-Output "Service '$service' on $server could not be queried. Error: $_"
            }
        }
    }
    else {
        Log-Output "Server $server is NOT reachable."
    }

    Log-Output "Completed checks for server: $server"
}

Log-Output "Monitoring script finished."
