import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/services/push_alerts.dart';

void main() {
  const nas = AlertDevice(hostname: 'nas', vendor: 'Synology', mac: '00:11:32:00:00:01');
  const tv = AlertDevice(vendor: 'LG Electronics', mac: 'a8:23:fe:00:00:02');
  const bare = AlertDevice(mac: 'aa:bb:cc:00:00:03');

  test('one device names it and the network', () {
    final t = newDeviceAlertText([nas], 'HomeWiFi');
    expect(t.title, 'New device on HomeWiFi');
    expect(t.body, 'nas');
  });

  test('names fall back from hostname to vendor to MAC', () {
    final t = newDeviceAlertText([nas, tv, bare], 'HomeWiFi');
    expect(t.title, '3 new devices on HomeWiFi');
    expect(t.body, 'nas, LG Electronics, aa:bb:cc:00:00:03');
  });

  test('more than three devices are summarised', () {
    final t = newDeviceAlertText([nas, tv, bare, nas, tv], null);
    expect(t.title, '5 new devices on your network');
    expect(t.body, 'nas, LG Electronics, aa:bb:cc:00:00:03 and 2 more');
  });

  test('no details yet still says something useful', () {
    final t = newDeviceAlertText(const [], '');
    expect(t.title, 'New device on your network');
    expect(t.body, 'Open PingDuck to see it.');
  });

  test('a device with nothing known is not blank', () {
    expect(const AlertDevice(hostname: '').displayName, 'Unknown device');
  });
}
