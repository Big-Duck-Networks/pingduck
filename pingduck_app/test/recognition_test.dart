import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/recognition/recognition.dart';
import 'package:pingduck_app/features/scanner/domain/device_kind.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';

/// Devices as the core reported them on the test LAN (10.42.0.0/24).
DiscoveredDevice device({
  String ip = '10.42.0.9',
  String? hostname,
  String? vendor,
  String? model,
  String? server,
  int? ttl,
  List<String> services = const [],
  Set<DiscoverySource> sources = const {DiscoverySource.icmp},
}) =>
    DiscoveredDevice(
      ip: ip,
      hostname: hostname,
      vendor: vendor,
      model: model,
      server: server,
      ttl: ttl,
      services: services,
      sources: sources,
      isOnline: true,
    );

Recognition recognize(DiscoveredDevice d) => Recognizer.of(d, DeviceKind.of(d));

void main() {
  test('HP printer: brand, model and family it announced over mDNS', () {
    final r = recognize(device(
      vendor: 'HP Inc.',
      model: 'HP OfficeJet Pro 9010 series',
      ttl: 64,
      services: ['_ipp._tcp'],
      sources: {DiscoverySource.icmp, DiscoverySource.mdns},
    ));
    expect(r.brand, const Fact('HP', Confidence.known));
    expect(r.model, const Fact('OfficeJet Pro 9010 series', Confidence.known));
    expect(r.family, const Fact('OfficeJet Pro', Confidence.known));
    expect(r.os, isNull);
  });

  test('Chromecast: its SSDP server string names Android 14', () {
    final r = recognize(device(
      vendor: 'Google, Inc.',
      model: 'Chromecast',
      server: 'Linux/5.15.170-android14-11-gf4a1f03072a, UPnP/1.0, Portable SDK for UPnP devices/1.14.13',
      ttl: 64,
      sources: {DiscoverySource.mdns, DiscoverySource.ssdp},
    ));
    expect(r.brand?.value, 'Google');
    expect(r.family?.value, 'Chromecast');
    expect(r.os?.name, 'Android');
    expect(r.os?.version, '14');
    expect(r.os?.vendor, 'Google');
    expect(r.os?.isGuess, isFalse);
  });

  test('Lenovo PC on Windows: LCFC is Lenovo, and TTL 128 suggests Windows', () {
    final r = recognize(device(ip: '10.42.0.100', vendor: 'LCFC(Hefei) Electronics Technology co., ltd', ttl: 128));
    expect(r.brand, const Fact('Lenovo', Confidence.likely));
    expect(r.model, isNull);
    expect(r.os?.name, 'Windows');
    expect(r.os?.vendor, 'Microsoft');
    expect(r.os?.isGuess, isTrue);
  });

  test('a PC running PingDuck for Windows says so in its SSDP server string', () {
    final r = recognize(device(
      vendor: 'GIGA-BYTE TECHNOLOGY CO.,LTD.',
      model: 'PingDuck Agent',
      server: 'Windows/10 UPnP/1.1 PingDuckAgent/0.3.1',
      ttl: 128,
      sources: {DiscoverySource.ssdp},
    ));
    expect(r.brand?.value, 'Gigabyte');
    expect(r.os?.name, 'Windows');
    expect(r.os?.isGuess, isFalse);
  });

  test('Samsung TV: Samsung-Linux is Tizen', () {
    final r = recognize(device(
      vendor: 'Samsung Electronics Co.,Ltd',
      model: 'U7900F',
      server: 'Samsung-Linux/4.1, UPnP/1.0, Samsung_UPnP_SDK/1.0',
      sources: {DiscoverySource.ssdp},
    ));
    expect(r.brand?.value, 'Samsung');
    expect(r.family?.value, 'Smart TV');
    expect(r.os?.name, 'Tizen');
  });

  test('Wi-Fi module makers are the module, not the brand', () {
    final r = recognize(device(vendor: 'Espressif Inc.', ttl: 255));
    expect(r.brand, isNull);
    expect(r.module?.value, 'Espressif');
    expect(r.os, isNull);  // TTL 255 is too broad to name an OS
  });

  test('a phone with a private MAC shows only what its hostname gives away', () {
    expect(recognize(device(vendor: 'Private (randomized MAC)', ttl: 64)).hasDevice, isFalse);
    expect(recognize(device(vendor: 'Private (randomized MAC)', ttl: 64)).os, isNull);

    final iphone = recognize(device(vendor: 'Private (randomized MAC)', hostname: 'Carls-iPhone'));
    expect(iphone.brand, const Fact('Apple', Confidence.likely));
    expect(iphone.os?.name, 'iOS');
    expect(iphone.os?.isGuess, isTrue);
  });

  test('Apple model identifiers name the product and its OS', () {
    final r = recognize(device(
      vendor: 'Apple, Inc.',
      model: 'MacBookPro18,1',
      services: ['_companion-link._tcp'],
      sources: {DiscoverySource.mdns},
    ));
    expect(r.brand, const Fact('Apple', Confidence.known));
    expect(r.model?.value, 'MacBook Pro');
    expect(r.family?.value, 'MacBook');
    expect(r.os?.name, 'macOS');
    expect(r.os?.isGuess, isFalse);
  });

  test('Windows default hostnames suggest Windows', () {
    expect(recognize(device(hostname: 'DESKTOP-4F2K9QZ')).os?.name, 'Windows');
  });

  test('unknown vendors are tidied, not invented', () {
    final r = recognize(device(vendor: 'Proxmox Server Solutions GmbH'));
    expect(r.brand?.value, 'Proxmox');
    expect(r.os?.name, 'Linux');
    expect(recognize(device(vendor: 'Acme Widgets Co., Ltd.')).brand?.value, 'Acme Widgets');
    expect(recognize(device()).hasDevice, isFalse);
  });

  test('old caches with a server banner in model do not show it as the model', () {
    final r = recognize(device(vendor: 'TP-Link Systems Inc.', model: 'Linux UPnP/1.0 MiniUPnPd/2.2'));
    expect(r.model, isNull);
    expect(r.brand?.value, 'TP-Link');
  });
}
