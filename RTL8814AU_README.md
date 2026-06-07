# RTL8814AU WiFi Adapter Management Tool

A specialized tool for managing Realtek RTL8814AU WiFi adapters on Linux systems, based on the Sparrow-WiFi framework.

## Overview

This tool provides comprehensive management capabilities specifically designed for the Realtek RTL8814AU adapter, which is a dual-band (2.4GHz and 5GHz) WiFi adapter commonly found in penetration testing kits and high-performance wireless applications.

### Features

- **Adapter Detection**: Automatically detect RTL8814AU adapters on your system
- **Network Scanning**: Scan for available WiFi networks on 2.4GHz, 5GHz, or both bands
- **Channel Management**: Set specific channels and list supported channels per band
- **Monitor Mode**: Enable/disable monitor mode for packet capture
- **TX Power Control**: Set and monitor transmit power levels
- **Packet Capture**: Capture wireless packets with optional SSID filtering
- **Adapter Information**: Detailed adapter statistics and configuration

## Prerequisites

### System Requirements

- Linux operating system (Ubuntu, Kali, Debian, etc.)
- Python 3.6+
- Root/sudo access
- RTL8814AU driver installed and loaded

### Required Tools

```bash
# For network scanning and management
iw
ip
ethtool
modinfo

# For packet capture (optional)
tcpdump

# For USB device detection
usbutils (lsusb)
```

### Installation

#### 1. Install RTL8814AU Driver

Clone and compile the driver:

```bash
git clone https://github.com/morrownr/88x2bu.git
cd 88x2bu
./disable-monitor.sh
make clean
make
sudo make install
sudo modprobe 88x2bu
```

Or for the alternative driver:

```bash
git clone https://github.com/aircrack-ng/rtl8814au.git
cd rtl8814au
make clean
make
sudo make install
sudo modprobe rtl8814au
```

#### 2. Install Required Linux Tools

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    python3 \
    iw \
    net-tools \
    usbutils \
    ethtool \
    tcpdump \
    wireless-tools
```

**Kali Linux:**
```bash
sudo apt-get update
sudo apt-get install -y \
    python3 \
    iw \
    net-tools \
    usbutils \
    ethtool \
    tcpdump \
    wireless-tools
```

#### 3. Set Up the RTL8814AU Tool

```bash
# Make the tool executable
chmod +x rtl8814au_tool.py

# Optional: Create a symlink for easy access
sudo cp rtl8814au_tool.py /usr/local/bin/rtl8814au-tool
sudo chmod +x /usr/local/bin/rtl8814au-tool
```

## Usage Guide

### Command Structure

```bash
sudo python3 rtl8814au_tool.py [OPTIONS] COMMAND [ARGS]
```

### Commands

#### 1. Detect Adapters

Detect all RTL8814AU adapters connected to the system:

```bash
sudo python3 rtl8814au_tool.py detect
```

**Output:**
```
Found 1 RTL8814AU adapter(s):
  - wlan0
```

#### 2. Get Adapter Information

Display detailed information about the adapter:

```bash
sudo python3 rtl8814au_tool.py info --interface wlan0
```

**Output:**
```
RTL8814AU Adapter Information
==================================================
Interface:        wlan0
MAC Address:      AA:BB:CC:DD:EE:FF
Driver:           rtl8814au
Driver Version:   v5.8.6.4
Current Channel:  6
Current Band:     2.4GHz
TX Power:         20 dBm
Monitor Mode:     Disabled
2.4GHz Channels:  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
5GHz Channels:    36, 40, 44, 48, 52, 56, 60, 64, 100, 104, ...
```

#### 3. Scan Networks

Scan for available WiFi networks:

```bash
# Scan all bands
sudo python3 rtl8814au_tool.py scan

# Scan 2.4GHz only
sudo python3 rtl8814au_tool.py scan --band 2.4

# Scan 5GHz only
sudo python3 rtl8814au_tool.py scan --band 5

# Output as JSON
sudo python3 rtl8814au_tool.py scan --json
```

**Example Output:**
```
Found 8 network(s):

  BSSID: AA:BB:CC:DD:EE:01
  SSID:  MyNetwork
  Channel: 6
  Signal: -45 dBm
  Security: WPA, RSN

  BSSID: AA:BB:CC:DD:EE:02
  SSID:  GuestNetwork
  Channel: 44
  Signal: -62 dBm
  Security: WPA, RSN
```

#### 4. Channel Management

Set or view WiFi channels:

```bash
# Set channel to 6 (2.4GHz)
sudo python3 rtl8814au_tool.py channel --set 6

# Set channel to 36 (5GHz)
sudo python3 rtl8814au_tool.py channel --set 36

# List supported 2.4GHz channels
sudo python3 rtl8814au_tool.py channel --list --band 2.4

# List supported 5GHz channels
sudo python3 rtl8814au_tool.py channel --list --band 5

# Get current channel
sudo python3 rtl8814au_tool.py channel
```

**Channel Reference:**

2.4GHz Channels: 1-13 (varies by region)
5GHz Channels: 36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165

#### 5. Monitor Mode

Enable/disable monitor mode for packet capture:

```bash
# Enable monitor mode
sudo python3 rtl8814au_tool.py monitor --enable

# Disable monitor mode
sudo python3 rtl8814au_tool.py monitor --disable

# Check current status
sudo python3 rtl8814au_tool.py monitor
```

**Note:** When monitor mode is enabled, the adapter creates a `wlan0mon` interface and disconnects from any active networks.

#### 6. TX Power Control

Configure transmit power:

```bash
# Set TX power to 20 dBm (maximum)
sudo python3 rtl8814au_tool.py power --set 20

# Set TX power to 10 dBm (reduced)
sudo python3 rtl8814au_tool.py power --set 10

# Get current TX power
sudo python3 rtl8814au_tool.py power --get

# View TX power info
sudo python3 rtl8814au_tool.py power
```

**TX Power Guidelines:**
- Valid range: 1-30 dBm
- Typical maximum: 20 dBm
- Reduced power (10 dBm) for testing near field effects
- Check local regulations before increasing TX power

#### 7. Packet Capture

Capture wireless traffic:

```bash
# Start capturing packets to file.pcap
sudo python3 rtl8814au_tool.py capture --start capture.pcap

# Start capture with SSID filter
sudo python3 rtl8814au_tool.py capture --start capture.pcap --ssid MyNetwork

# Stop capturing
sudo python3 rtl8814au_tool.py capture --stop
```

**Note:** Monitor mode will be automatically enabled for packet capture.

## Advanced Usage

### Integration with Sparrow-WiFi

The RTL8814AU tool can be integrated with Sparrow-WiFi for enhanced functionality:

```bash
# Run Sparrow-WiFi with RTL8814AU adapter
sudo python3 sparrow-wifi.py --interface wlan0
```

### Scripting Examples

#### Example 1: Multi-Channel Scan

```bash
#!/bin/bash

INTERFACE="wlan0"
OUTPUT_DIR="./scan_results"

mkdir -p "$OUTPUT_DIR"

# Scan each 2.4GHz channel individually
for channel in 1 6 11; do
    echo "Scanning channel $channel..."
    sudo python3 rtl8814au_tool.py --interface "$INTERFACE" channel --set $channel
    sleep 1
    sudo python3 rtl8814au_tool.py --interface "$INTERFACE" scan --json > "$OUTPUT_DIR/scan_ch$channel.json"
done

echo "Scans completed. Results in $OUTPUT_DIR"
```

#### Example 2: Signal Strength Monitor

```bash
#!/bin/bash

INTERFACE="wlan0"
SSID="MyNetwork"

echo "Monitoring signal strength for $SSID..."

while true; do
    sudo python3 rtl8814au_tool.py --interface "$INTERFACE" scan --json | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for bssid, net in data.items():
    if net['ssid'] == '$SSID':
        print(f\"[{net['channel']}] {net['signal']} dBm\")
        break
"
    sleep 2
done
```

#### Example 3: Site Survey

```bash
#!/bin/bash

INTERFACE="wlan0"

echo "=== RTL8814AU Site Survey ==="
echo "Timestamp: $(date)"
echo ""

echo "Adapter Information:"
sudo python3 rtl8814au_tool.py --interface "$INTERFACE" info
echo ""

echo "2.4GHz Networks:"
sudo python3 rtl8814au_tool.py --interface "$INTERFACE" scan --band 2.4
echo ""

echo "5GHz Networks:"
sudo python3 rtl8814au_tool.py --interface "$INTERFACE" scan --band 5
```

## Troubleshooting

### Issue: "No RTL8814AU adapters detected"

**Solutions:**
1. Verify driver is loaded:
   ```bash
   lsmod | grep rtl
   ```

2. Check if adapter is recognized:
   ```bash
   lsusb | grep RTL
   ```

3. Reload the driver:
   ```bash
   sudo modprobe -r rtl8814au
   sudo modprobe rtl8814au
   ```

### Issue: Monitor mode won't enable

**Solutions:**
1. Check if device is already in monitor mode:
   ```bash
   iw dev
   ```

2. Verify driver supports monitor mode:
   ```bash
   iw phy0 info | grep monitor
   ```

3. Try disabling and re-enabling:
   ```bash
   sudo python3 rtl8814au_tool.py monitor --disable
   sudo python3 rtl8814au_tool.py monitor --enable
   ```

### Issue: Scan returns no networks

**Solutions:**
1. Ensure adapter is not in monitor mode or manually associated
2. Check RF interference with:
   ```bash
   iw dev wlan0 scan freq 2400-2500
   ```

3. Try scanning a specific band:
   ```bash
   sudo python3 rtl8814au_tool.py scan --band 2.4
   ```

### Issue: TX power won't change

**Solutions:**
1. Check regulatory domain:
   ```bash
   iw reg get
   ```

2. Verify adapter supports custom TX power:
   ```bash
   iw dev wlan0 get power
   ```

3. Use regulatory domain override (advanced):
   ```bash
   sudo iw reg set US
   ```

## Performance Tips

### 1. Optimize for Speed

```bash
# Use 5GHz band for faster scanning
sudo python3 rtl8814au_tool.py scan --band 5
```

### 2. Reduce Interference

```bash
# Set to channel with less interference
# (typically 1, 6, 11 for 2.4GHz)
sudo python3 rtl8814au_tool.py channel --set 6
```

### 3. Monitor Mode Performance

```bash
# Enable monitor mode once, then keep it enabled
# for continuous packet capture without re-enabling
sudo python3 rtl8814au_tool.py monitor --enable
```

## Security Considerations

⚠️ **Important:**
- Only use this tool on networks you own or have explicit permission to test
- Comply with all local laws and regulations regarding wireless testing
- Monitor mode and packet capture may be illegal in your jurisdiction without proper authorization
- The RTL8814AU is commonly used in penetration testing - ensure responsible use

## Hardware Specifications

### RTL8814AU Specifications

| Specification | Details |
|---|---|
| **Chipset** | Realtek RTL8814AU |
| **Bands** | 2.4GHz & 5GHz (Dual Band) |
| **Standards** | 802.11ac, 802.11n, 802.11a/g/b |
| **Data Rate** | Up to 1200 Mbps |
| **Antenna** | Typically 2-4 external antennas |
| **TX Power** | 20 dBm (typical) |
| **Frequency Range** | 2.4GHz: 2400-2500 MHz, 5GHz: 5000-6000 MHz |
| **Interface** | USB 3.0 |
| **Operating Temperature** | 0-40°C |
| **Storage Temperature** | -10-60°C |

## Supported Adapters

This tool supports adapters with the RTL8814AU chipset, including:

- Alfa AWUS1900 (AWUS036ACS)
- Edimax EW-7833AUM
- TP-Link Archer T4U Plus
- Various OEM variants with RTL8814AU chipset

## Contributing

To contribute improvements or report issues:

1. Test thoroughly with your RTL8814AU adapter
2. Document any driver-specific behaviors
3. Submit detailed bug reports with error output
4. Include adapter brand/model and Linux distribution info

## References

- [Sparrow-WiFi GitHub](https://github.com/ghostop14/sparrow-wifi)
- [Realtek Linux Driver Documentation](https://github.com/morrownr/88x2bu)
- [Linux Wireless Documentation](https://wireless.kernel.org/)
- [iw manual pages](https://wireless.kernel.org/en/users/documentation/iw)

## License

GNU General Public License v3.0 - See LICENSE file for details

## Disclaimer

This tool is provided for educational and authorized testing purposes only. Unauthorized access to computer networks is illegal. Users are responsible for ensuring compliance with all applicable laws and regulations.

---

**Last Updated:** 2026
**Version:** 1.0.0
**Tested with:** RTL8814AU driver v5.8.6+, Linux kernel 5.4+
