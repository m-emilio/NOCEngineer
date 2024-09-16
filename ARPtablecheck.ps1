# Description: Analyzes the ARP table to detect possible ARP poisoning attacks and checks network connectivity with a prompt to conitnue analysis if the connectivity check fails.

# Path to log file
$logFile = "C:\NOC_Logs\ARP_Poisoning_Detection_Log.txt"

# Define the host for connectivity check (e.g., default gateway, DNS server, etc.)
$connectivityCheckHost = "8.8.8.8"  # Google's public DNS server

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

# Function to check network connectivity
function Check-Connectivity {
    param (
        [string]$host
    )
    Log-Output "Checking network connectivity to $host..."
    if (Test-Connection -ComputerName $host -Count 2 -Quiet) {
        Log-Output "Connectivity to $host is successful."
        return $true
    }
    else {
        Log-Output "Connectivity to $host failed."
        return $false
    }
}

# Function to analyze the ARP table
function Analyze-ARPTable {
    # Get the ARP table
    $arpTable = arp -a

    # Parse the ARP table to extract IP and MAC addresses
    $arpEntries = @()
    foreach ($line in $arpTable) {
        if ($line -match "^\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([a-f0-9:-]{17}|[a-f0-9]{12})\s+\S+$") {
            $arpEntries += [PSCustomObject]@{
                IPAddress = $matches[1]
                MACAddress = $matches[2].ToLower()
            }
        }
    }

    # Group ARP entries by MAC address to detect duplicates
    $duplicateMACs = $arpEntries | Group-Object -Property MACAddress | Where-Object { $_.Count -gt 1 }

    # Check for potential ARP poisoning
    if ($duplicateMACs.Count -gt 0) {
        foreach ($dup in $duplicateMACs) {
            Log-Output "Possible ARP Poisoning detected for MAC: $($dup.Name)"
            Log-Output "Associated IP Addresses: $($dup.Group.IPAddress -join ', ')"
        }
    }
    else {
        Log-Output "No ARP Poisoning detected."
    }
}

# Start ARP table analysis with connectivity check
Log-Output "Starting ARP table analysis with connectivity check..."

# Perform connectivity check before analyzing the ARP table
if (Check-Connectivity -host $connectivityCheckHost) {
    # Prompt the user to continue or cancel the ARP analysis
    $userResponse = Read-Host "Connectivity check successful. Do you want to continue with ARP analysis? (Y/N)"
    if ($userResponse.ToUpper() -eq 'Y') {
        Analyze-ARPTable
    }
    else {
        Log-Output "ARP analysis was canceled by the user."
    }
}
else {
    Log-Output "Skipping ARP analysis due to failed connectivity check."
}

Log-Output "ARP table analysis script completed."
