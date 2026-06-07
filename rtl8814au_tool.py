#!/usr/bin/env python3
# 
# RTL8814AU Specialized WiFi Adapter Tool
# Based on Sparrow-WiFi Framework (https://github.com/ghostop14/sparrow-wifi)
# 
# Copyright 2026 - Realtek RTL8814AU Support
# GNU General Public License v3.0
#

import os
import sys
import subprocess
import re
import json
import argparse
import datetime
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict, field
from enum import Enum
import signal
import time

# ============================================================================
# RTL8814AU Detection and Verification
# ============================================================================

class ChipsetType(Enum):
    """Supported Realtek chipset variants"""
    RTL8814AU = "rtl8814au"
    UNKNOWN = "unknown"

@dataclass
class AdapterInfo:
    """Information about a detected RTL8814AU adapter"""
    interface_name: str
    mac_address: str = ""
    driver_name: str = "rtl8814au"
    driver_version: str = ""
    chipset: ChipsetType = ChipsetType.RTL8814AU
    usb_id: str = ""
    firmware_version: str = ""
    supported_bands: List[str] = field(default_factory=lambda: ["2.4GHz", "5GHz"])
    supported_channels_24ghz: List[int] = field(default_factory=lambda: list(range(1, 14)))
    supported_channels_5ghz: List[int] = field(default_factory=lambda: [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165])
    tx_power: int = 20  # dBm
    current_channel: int = 0
    current_band: str = "2.4GHz"
    monitor_mode_enabled: bool = False
    
    def to_json(self) -> str:
        """Convert adapter info to JSON"""
        data = asdict(self)
        data['chipset'] = self.chipset.value
        return json.dumps(data, indent=2, default=str)

# ============================================================================
# RTL8814AU Driver Detection
# ============================================================================

class RTL8814AUDetector:
    """Detects and manages RTL8814AU adapters"""
    
    # Known RTL8814AU USB IDs (Vendor:Device)
    KNOWN_USB_IDS = [
        "0bda:8814",  # Standard Realtek RTL8814AU
        "7392:a714",  # Edimax EW-7833AUM variant
        "7392:a812",  # Edimax variant
        "2357:0107",  # TP-Link variant
    ]
    
    @staticmethod
    def get_usb_devices() -> Dict[str, str]:
        """Get all USB WiFi devices and their IDs"""
        devices = {}
        try:
            result = subprocess.run(['lsusb'], capture_output=True, text=True, timeout=5)
            # Match pattern: Bus ### Device ###: ID xxxx:xxxx Vendor Name
            pattern = r'ID ([0-9a-f]+:[0-9a-f]+)\s+(.*)'
            for line in result.stdout.split('\n'):
                match = re.search(pattern, line)
                if match:
                    usb_id = match.group(1)
                    device_name = match.group(2)
                    devices[usb_id] = device_name
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return devices
    
    @staticmethod
    def detect_rtl8814au_adapters() -> List[str]:
        """Detect all RTL8814AU adapters connected to system"""
        adapters = []
        
        # Method 1: Check lsusb for known RTL8814AU IDs
        usb_devices = RTL8814AUDetector.get_usb_devices()
        for usb_id in RTL8814AUDetector.KNOWN_USB_IDS:
            if usb_id in usb_devices:
                # Try to find corresponding interface
                try:
                    result = subprocess.run(['iw', 'dev'], capture_output=True, text=True, timeout=5)
                    # Match: Interface wlanX
                    pattern = r'Interface\s+([a-z0-9]+)'
                    for match in re.finditer(pattern, result.stdout):
                        interface = match.group(1)
                        # Verify it's an RTL8814AU
                        if RTL8814AUDetector.verify_interface(interface):
                            if interface not in adapters:
                                adapters.append(interface)
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    pass
        
        # Method 2: Check /sys/class/net for rtl8814au driver
        sys_path = "/sys/class/net"
        if os.path.exists(sys_path):
            for interface in os.listdir(sys_path):
                if interface.startswith('w'):  # WiFi interfaces
                    driver_link = os.path.join(sys_path, interface, "device", "driver")
                    if os.path.islink(driver_link):
                        try:
                            driver_path = os.readlink(driver_link)
                            if 'rtl8814au' in driver_path.lower() or 'rtl88' in driver_path.lower():
                                if interface not in adapters:
                                    adapters.append(interface)
                        except (OSError, IOError):
                            pass
        
        return adapters
    
    @staticmethod
    def verify_interface(interface: str) -> bool:
        """Verify if interface is RTL8814AU"""
        try:
            # Check driver
            driver_path = f"/sys/class/net/{interface}/device/driver"
            if os.path.islink(driver_path):
                real_path = os.readlink(driver_path)
                if 'rtl' in real_path.lower():
                    return True
            
            # Check via ethtool
            result = subprocess.run(['ethtool', '-i', interface], 
                                  capture_output=True, text=True, timeout=5)
            if 'rtl8814' in result.stdout.lower() or 'rtl88' in result.stdout.lower():
                return True
                
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        
        return False

# ============================================================================
# RTL8814AU Adapter Manager
# ============================================================================

class RTL8814AUManager:
    """Main manager for RTL8814AU adapter operations"""
    
    def __init__(self, interface: str = None):
        """Initialize manager with specific interface or auto-detect"""
        self.interface = interface
        self.adapter_info = None
        self.monitor_process = None
        
        if interface is None:
            adapters = RTL8814AUDetector.detect_rtl8814au_adapters()
            if adapters:
                self.interface = adapters[0]
            else:
                raise RuntimeError("No RTL8814AU adapters detected!")
        
        self._initialize_adapter_info()
    
    def _initialize_adapter_info(self):
        """Gather adapter information"""
        self.adapter_info = AdapterInfo(interface_name=self.interface)
        
        # Get MAC address
        try:
            result = subprocess.run(['ip', 'link', 'show', self.interface],
                                  capture_output=True, text=True, timeout=5)
            match = re.search(r'link/ether\s+([0-9a-f:]+)', result.stdout)
            if match:
                self.adapter_info.mac_address = match.group(1).upper()
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        # Get driver version
        self._update_driver_version()
        
        # Get current channel
        self._update_channel_info()
    
    def _update_driver_version(self):
        """Get RTL8814AU driver version"""
        try:
            result = subprocess.run(['modinfo', '8814au'],
                                  capture_output=True, text=True, timeout=5)
            match = re.search(r'version:\s+([^\n]+)', result.stdout)
            if match:
                self.adapter_info.driver_version = match.group(1)
        except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
            self.adapter_info.driver_version = "unknown"
    
    def _update_channel_info(self):
        """Update current channel information"""
        try:
            result = subprocess.run(['iw', 'dev', self.interface, 'link'],
                                  capture_output=True, text=True, timeout=5)
            # Match: frequency XXXX MHz (Channel YY)
            match = re.search(r'frequency\s+(\d+)\s*MHz.*Channel\s+(\d+)', result.stdout)
            if match:
                frequency = int(match.group(1))
                channel = int(match.group(2))
                self.adapter_info.current_channel = channel
                
                if frequency < 3000:
                    self.adapter_info.current_band = "2.4GHz"
                else:
                    self.adapter_info.current_band = "5GHz"
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
    
    # ========================================================================
    # Scanning Operations
    # ========================================================================
    
    def scan_networks(self, band: str = "all") -> Dict[str, dict]:
        """
        Scan for WiFi networks
        
        Args:
            band: "2.4", "5", or "all"
        
        Returns:
            Dictionary of networks found
        """
        networks = {}
        
        try:
            result = subprocess.run(['iw', 'dev', self.interface, 'scan'],
                                  capture_output=True, text=True, timeout=30)
            
            networks = self._parse_scan_output(result.stdout, band)
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            print(f"Error scanning networks: {e}", file=sys.stderr)
        
        return networks
    
    def _parse_scan_output(self, scan_output: str, band: str = "all") -> Dict[str, dict]:
        """Parse iw scan output"""
        networks = {}
        current_bss = None
        
        for line in scan_output.split('\n'):
            # New BSS
            if line.startswith('BSS'):
                match = re.search(r'BSS\s+([0-9a-f:]+)', line)
                if match:
                    current_bss = match.group(1)
                    networks[current_bss] = {
                        'bssid': current_bss,
                        'ssid': '',
                        'channel': 0,
                        'frequency': 0,
                        'signal': 0,
                        'security': [],
                    }
            
            if current_bss is None:
                continue
            
            # SSID
            match = re.search(r'SSID:\s+(.+)', line)
            if match:
                networks[current_bss]['ssid'] = match.group(1)
            
            # Frequency and Channel
            match = re.search(r'freq:\s+(\d+)', line)
            if match:
                freq = int(match.group(1))
                networks[current_bss]['frequency'] = freq
                networks[current_bss]['channel'] = self._freq_to_channel(freq)
            
            # Signal strength
            match = re.search(r'signal:\s+(-?\d+)\s+dBm', line)
            if match:
                networks[current_bss]['signal'] = int(match.group(1))
            
            # Security
            if 'RSN' in line or 'WPA' in line:
                match = re.search(r'(WPA|RSN|WEP)', line)
                if match and match.group(1) not in networks[current_bss]['security']:
                    networks[current_bss]['security'].append(match.group(1))
        
        # Filter by band if needed
        if band != "all":
            filtered = {}
            band_freq_min, band_freq_max = self._get_band_frequency_range(band)
            for bssid, net_info in networks.items():
                if band_freq_min <= net_info['frequency'] <= band_freq_max:
                    filtered[bssid] = net_info
            return filtered
        
        return networks
    
    @staticmethod
    def _freq_to_channel(frequency: int) -> int:
        """Convert frequency (MHz) to channel number"""
        if 2407 < frequency < 2485:
            return (frequency - 2407) // 5
        elif 5000 < frequency < 6000:
            return (frequency - 5000) // 5
        return 0
    
    @staticmethod
    def _get_band_frequency_range(band: str) -> Tuple[int, int]:
        """Get frequency range for band"""
        if band == "2.4":
            return 2400, 2500
        elif band == "5":
            return 5000, 6000
        return 0, 10000
    
    # ========================================================================
    # Channel Control
    # ========================================================================
    
    def set_channel(self, channel: int, band: str = None) -> bool:
        """
        Set WiFi channel
        
        Args:
            channel: Channel number
            band: "2.4" or "5" (auto-detect if None)
        
        Returns:
            True if successful
        """
        if band is None:
            band = "2.4" if channel < 14 else "5"
        
        # Validate channel for band
        if band == "2.4" and channel not in self.adapter_info.supported_channels_24ghz:
            print(f"Invalid 2.4GHz channel: {channel}", file=sys.stderr)
            return False
        elif band == "5" and channel not in self.adapter_info.supported_channels_5ghz:
            print(f"Invalid 5GHz channel: {channel}", file=sys.stderr)
            return False
        
        try:
            subprocess.run(['iw', 'dev', self.interface, 'set', 'channel', str(channel)],
                         capture_output=True, text=True, timeout=5, check=True)
            
            self.adapter_info.current_channel = channel
            self.adapter_info.current_band = band
            return True
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            print(f"Error setting channel: {e}", file=sys.stderr)
            return False
    
    def get_supported_channels(self, band: str = "2.4") -> List[int]:
        """Get supported channels for band"""
        if band == "2.4":
            return self.adapter_info.supported_channels_24ghz
        elif band == "5":
            return self.adapter_info.supported_channels_5ghz
        return []
    
    # ========================================================================
    # Monitor Mode Operations
    # ========================================================================
    
    def enable_monitor_mode(self) -> bool:
        """Enable monitor mode on adapter"""
        if self.adapter_info.monitor_mode_enabled:
            print("Monitor mode already enabled", file=sys.stderr)
            return True
        
        try:
            # Create monitor interface
            mon_interface = f"{self.interface}mon"
            subprocess.run(['iw', self.interface, 'interface', 'add', mon_interface, 
                           'type', 'monitor'],
                         capture_output=True, text=True, timeout=5, check=True)
            
            # Bring up interface
            subprocess.run(['ip', 'link', 'set', mon_interface, 'up'],
                         capture_output=True, text=True, timeout=5, check=True)
            
            self.adapter_info.monitor_mode_enabled = True
            return True
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            print(f"Error enabling monitor mode: {e}", file=sys.stderr)
            return False
    
    def disable_monitor_mode(self) -> bool:
        """Disable monitor mode"""
        if not self.adapter_info.monitor_mode_enabled:
            return True
        
        try:
            mon_interface = f"{self.interface}mon"
            subprocess.run(['ip', 'link', 'set', mon_interface, 'down'],
                         capture_output=True, text=True, timeout=5, check=True)
            subprocess.run(['iw', 'dev', mon_interface, 'del'],
                         capture_output=True, text=True, timeout=5, check=True)
            
            self.adapter_info.monitor_mode_enabled = False
            return True
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            print(f"Error disabling monitor mode: {e}", file=sys.stderr)
            return False
    
    # ========================================================================
    # Power Management
    # ========================================================================
    
    def set_tx_power(self, power: int) -> bool:
        """
        Set transmit power
        
        Args:
            power: Power in dBm (typically 1-20)
        
        Returns:
            True if successful
        """
        if power < 1 or power > 30:
            print(f"Power must be between 1-30 dBm", file=sys.stderr)
            return False
        
        try:
            subprocess.run(['iw', 'dev', self.interface, 'set', 'txpower', 'fixed',
                           str(power * 100)],  # Convert to mBm
                         capture_output=True, text=True, timeout=5, check=True)
            
            self.adapter_info.tx_power = power
            return True
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            print(f"Error setting TX power: {e}", file=sys.stderr)
            return False
    
    def get_tx_power(self) -> int:
        """Get current transmit power"""
        try:
            result = subprocess.run(['iw', 'dev', self.interface, 'get', 'txpower'],
                                  capture_output=True, text=True, timeout=5)
            match = re.search(r'(\d+)\s*mBm', result.stdout)
            if match:
                return int(match.group(1)) // 100  # Convert from mBm to dBm
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        return self.adapter_info.tx_power
    
    # ========================================================================
    # Packet Capture
    # ========================================================================
    
    def start_packet_capture(self, output_file: str, filter_ssid: str = None) -> bool:
        """
        Start capturing packets
        
        Args:
            output_file: Path to save pcap file
            filter_ssid: Optional SSID to filter on
        
        Returns:
            True if successful
        """
        # First enable monitor mode
        if not self.enable_monitor_mode():
            return False
        
        mon_interface = f"{self.interface}mon"
        
        try:
            cmd = ['tcpdump', '-i', mon_interface, '-w', output_file]
            
            if filter_ssid:
                # This is a simplified filter - tcpdump doesn't directly filter by SSID
                cmd.append(f"'(subtype beacon) and (substring \"{filter_ssid}\")'")
            
            self.monitor_process = subprocess.Popen(cmd, 
                                                   stdout=subprocess.PIPE,
                                                   stderr=subprocess.PIPE)
            return True
        except FileNotFoundError:
            print("tcpdump not installed", file=sys.stderr)
            return False
    
    def stop_packet_capture(self) -> bool:
        """Stop packet capture"""
        if self.monitor_process:
            try:
                self.monitor_process.send_signal(signal.SIGINT)
                self.monitor_process.wait(timeout=5)
                return True
            except subprocess.TimeoutExpired:
                self.monitor_process.kill()
                return False
        
        return False
    
    # ========================================================================
    # Information Methods
    # ========================================================================
    
    def get_adapter_info(self) -> AdapterInfo:
        """Get adapter information"""
        self._update_driver_version()
        self._update_channel_info()
        return self.adapter_info
    
    def print_adapter_info(self):
        """Print adapter information in human-readable format"""
        info = self.get_adapter_info()
        
        print(f"RTL8814AU Adapter Information")
        print(f"=" * 50)
        print(f"Interface:        {info.interface_name}")
        print(f"MAC Address:      {info.mac_address}")
        print(f"Driver:           {info.driver_name}")
        print(f"Driver Version:   {info.driver_version}")
        print(f"Current Channel:  {info.current_channel}")
        print(f"Current Band:     {info.current_band}")
        print(f"TX Power:         {info.tx_power} dBm")
        print(f"Monitor Mode:     {'Enabled' if info.monitor_mode_enabled else 'Disabled'}")
        print(f"2.4GHz Channels:  {', '.join(map(str, info.supported_channels_24ghz))}")
        print(f"5GHz Channels:    {', '.join(map(str, info.supported_channels_5ghz))}")

# ============================================================================
# CLI Interface
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="RTL8814AU WiFi Adapter Management Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s detect                     # Detect RTL8814AU adapters
  %(prog)s info --interface wlan0     # Get adapter information
  %(prog)s scan --band 2.4            # Scan 2.4GHz networks
  %(prog)s channel --set 6            # Set to channel 6
  %(prog)s monitor --enable           # Enable monitor mode
  %(prog)s power --set 20             # Set TX power to 20 dBm
        """)
    
    parser.add_argument('--interface', '-i', help='WiFi interface name (auto-detect if not specified)')
    parser.add_argument('--json', '-j', action='store_true', help='Output as JSON')
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Detect command
    subparsers.add_parser('detect', help='Detect RTL8814AU adapters')
    
    # Info command
    subparsers.add_parser('info', help='Display adapter information')
    
    # Scan command
    scan_parser = subparsers.add_parser('scan', help='Scan for networks')
    scan_parser.add_argument('--band', choices=['all', '2.4', '5'], default='all',
                            help='Band to scan')
    
    # Channel command
    channel_parser = subparsers.add_parser('channel', help='Manage channels')
    channel_parser.add_argument('--set', type=int, help='Set channel number')
    channel_parser.add_argument('--list', action='store_true', help='List supported channels')
    channel_parser.add_argument('--band', choices=['2.4', '5'], help='Band for channel list')
    
    # Monitor command
    monitor_parser = subparsers.add_parser('monitor', help='Monitor mode operations')
    monitor_parser.add_argument('--enable', action='store_true', help='Enable monitor mode')
    monitor_parser.add_argument('--disable', action='store_true', help='Disable monitor mode')
    
    # Power command
    power_parser = subparsers.add_parser('power', help='TX power management')
    power_parser.add_argument('--set', type=int, help='Set TX power (dBm)')
    power_parser.add_argument('--get', action='store_true', help='Get current TX power')
    
    # Capture command
    capture_parser = subparsers.add_parser('capture', help='Packet capture operations')
    capture_parser.add_argument('--start', type=str, metavar='FILE', help='Start capture to file')
    capture_parser.add_argument('--stop', action='store_true', help='Stop capture')
    capture_parser.add_argument('--ssid', help='Filter by SSID')
    
    args = parser.parse_args()
    
    # Handle root check
    if os.geteuid() != 0:
        print("ERROR: This tool requires root privileges. Run with 'sudo'.", file=sys.stderr)
        sys.exit(1)
    
    # Detect command
    if args.command == 'detect':
        adapters = RTL8814AUDetector.detect_rtl8814au_adapters()
        if adapters:
            print(f"Found {len(adapters)} RTL8814AU adapter(s):")
            for adapter in adapters:
                print(f"  - {adapter}")
        else:
            print("No RTL8814AU adapters detected")
        return 0
    
    # Get or detect interface
    interface = args.interface
    try:
        manager = RTL8814AUManager(interface)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    
    # Route to commands
    try:
        if args.command == 'info':
            if args.json:
                print(manager.adapter_info.to_json())
            else:
                manager.print_adapter_info()
        
        elif args.command == 'scan':
            networks = manager.scan_networks(args.band)
            
            if args.json:
                print(json.dumps(networks, indent=2))
            else:
                print(f"Found {len(networks)} network(s):")
                for bssid, net in networks.items():
                    print(f"\n  BSSID: {bssid}")
                    print(f"  SSID:  {net['ssid']}")
                    print(f"  Channel: {net['channel']}")
                    print(f"  Signal: {net['signal']} dBm")
                    if net['security']:
                        print(f"  Security: {', '.join(net['security'])}")
        
        elif args.command == 'channel':
            if args.set:
                if manager.set_channel(args.set):
                    print(f"Channel set to {args.set}")
                else:
                    return 1
            elif args.list:
                band = args.band or '2.4'
                channels = manager.get_supported_channels(band)
                print(f"Supported {band}GHz channels: {', '.join(map(str, channels))}")
            else:
                info = manager.get_adapter_info()
                print(f"Current channel: {info.current_channel} ({info.current_band})")
        
        elif args.command == 'monitor':
            if args.enable:
                if manager.enable_monitor_mode():
                    print("Monitor mode enabled")
                else:
                    return 1
            elif args.disable:
                if manager.disable_monitor_mode():
                    print("Monitor mode disabled")
                else:
                    return 1
            else:
                info = manager.get_adapter_info()
                print(f"Monitor mode: {'Enabled' if info.monitor_mode_enabled else 'Disabled'}")
        
        elif args.command == 'power':
            if args.set:
                if manager.set_tx_power(args.set):
                    print(f"TX power set to {args.set} dBm")
                else:
                    return 1
            elif args.get:
                power = manager.get_tx_power()
                print(f"Current TX power: {power} dBm")
            else:
                info = manager.get_adapter_info()
                print(f"TX power: {info.tx_power} dBm")
        
        elif args.command == 'capture':
            if args.start:
                if manager.start_packet_capture(args.start, args.ssid):
                    print(f"Started packet capture to {args.start}")
                    print("Press Ctrl+C to stop...")
                    try:
                        while True:
                            time.sleep(1)
                    except KeyboardInterrupt:
                        if manager.stop_packet_capture():
                            print("\nCapture stopped")
                else:
                    return 1
            elif args.stop:
                if manager.stop_packet_capture():
                    print("Capture stopped")
                else:
                    return 1
        
        else:
            parser.print_help()
    
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
