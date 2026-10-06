import 'package:flutter/material.dart';

import 'discovered_device.dart';

/// What a device probably is, inferred from what it advertises. Only real
/// signals are used (mDNS service types, UPnP device types, vendor, model,
/// hostname); when nothing matches the device stays [unknown].
enum DeviceKind {
  gateway('Gateway', Icons.router_outlined),
  network('Network', Icons.hub_outlined),
  nas('NAS', Icons.dns_outlined),
  workstation('Workstation', Icons.laptop_outlined),
  mobile('Mobile', Icons.smartphone_outlined),
  media('Media', Icons.tv_outlined),
  speaker('Speaker', Icons.speaker_outlined),
  printer('Printer', Icons.print_outlined),
  iot('IoT', Icons.lightbulb_outline),
  virtual('VM', Icons.memory_outlined),
  unknown('Device', Icons.devices_other_outlined);

  const DeviceKind(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Filter groups used by the topology view.
  String get group => switch (this) {
        gateway || network => 'Network',
        nas || workstation || virtual => 'Compute',
        media || speaker => 'Media',
        iot || printer => 'IoT',
        mobile => 'Mobile',
        unknown => 'Other',
      };

  static DeviceKind of(DiscoveredDevice d, {String? gatewayIp}) {
    if (gatewayIp != null && d.ip == gatewayIp) return gateway;
    final services = d.services.map((s) => s.toLowerCase()).toSet();
    final text = [d.hostname, d.model, d.vendor].whereType<String>().join(' ').toLowerCase();
    bool svc(String s) => services.any((x) => x.contains(s));
    bool word(Iterable<String> words) => words.any(text.contains);

    if (svc('internetgatewaydevice') || svc('wanconnection') || svc('wandevice')) return gateway;
    if (word(['qemu', 'kvm', 'hyper-v', 'docker', 'vmware', 'virtualbox']) || text.contains('virtual nic')) {
      return virtual;
    }
    if (svc('_ipp.') || svc('_printer.') || svc('_pdl-datastream') || word(['printer', 'laserjet', 'officejet'])) {
      return printer;
    }
    if (svc('_googlecast') || svc('_airplay') || svc('_amzn-wplay') || svc('mediarenderer') || svc('dial') ||
        word(['chromecast', 'roku', 'apple tv', 'fire tv', 'shield', 'bravia', 'smart tv', 'screen'])) {
      // Cast-capable speakers advertise the same services as TVs.
      if (word(['nest mini', 'nest audio', 'home mini', 'echo', 'sonos', 'homepod', 'speaker'])) return speaker;
      return media;
    }
    if (svc('_sonos') || svc('_raop') || svc('_spotify-connect') || word(['sonos', 'homepod', 'speaker'])) {
      return speaker;
    }
    if (word(['synology', 'qnap', 'diskstation', 'truenas', 'unraid', 'nas', 'proxmox', 'pve'])) return nas;
    if (svc('_hap.') || svc('_homekit') || svc('_hue') || svc('_matter') || svc('_esphomelib') ||
        word(['hue', 'shelly', 'tasmota', 'esp32', 'esp8266', 'espressif', 'tuya', 'nest', 'ring', 'wyze', 'tp-link smart'])) {
      return iot;
    }
    if (word(['iphone', 'ipad', 'pixel', 'galaxy', 'android', 'oneplus']) || svc('_companion-link')) return mobile;
    if (svc('_workstation') || svc('_smb.') || svc('_afpovertcp') || svc('_ssh.') ||
        word(['macbook', 'imac', 'desktop-', 'laptop', 'thinkpad', 'mint', 'ubuntu', 'debian', 'windows'])) {
      return workstation;
    }
    if (word(['switch', 'access point', 'unifi', 'mesh', 'deco', 'eero', 'orbi'])) return network;
    if (d.vendor != null && d.vendor!.startsWith('Private')) return mobile;  // randomized MACs are mostly phones
    return unknown;
  }
}
