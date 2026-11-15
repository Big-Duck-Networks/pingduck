import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/desktop/updates.dart';

final _setupBytes = utf8.encode('pretend installer');
final _setupHash = sha256.convert(_setupBytes).toString();

Map<String, Object?> _manifest({int build = 20, int minimumBuild = 0, String? hash, int? size, String? url}) => {
      'version': '1.0.1',
      'build': build,
      'url': url ?? 'https://github.com/Big-Duck-Networks/pingduck/releases/download/desktop-v1.0.1/PingDuckSetup.exe',
      'sha256': hash ?? _setupHash,
      'size': size ?? _setupBytes.length,
      'notes': 'Faster scans.',
      'minimumBuild': minimumBuild,
      'signed': false,
    };

class _FakeTransport implements UpdateTransport {
  _FakeTransport(this.manifest, {List<int>? body}) : body = body ?? _setupBytes;
  Map<String, Object?>? manifest;
  List<int> body;
  final fetched = <Uri>[];

  @override
  Future<String> fetchText(Uri url) async {
    fetched.add(url);
    if (manifest == null) throw const SocketException('offline');
    return jsonEncode(manifest);
  }

  @override
  Future<void> download(Uri url, File to, {required int maxBytes, void Function(int)? onProgress}) async {
    if (body.length > maxBytes) throw const FormatException('too large');
    await to.writeAsBytes(body);
    onProgress?.call(body.length);
  }
}

class _FakeInstaller implements UpdateInstaller {
  String? signatureProblem;
  bool accept = true;
  File? launched;
  var quit = false;

  @override
  Future<String?> checkSignature(File setup) async => signatureProblem;

  @override
  Future<bool> launch(File setup) async {
    launched = setup;
    return accept;
  }

  @override
  Future<void> quitApp() async => quit = true;
}

void main() {
  group('UpdateManifest', () {
    test('parses a release manifest', () {
      final m = UpdateManifest.fromJson(_manifest(minimumBuild: 18));
      expect(m.version, '1.0.1');
      expect(m.build, 20);
      expect(m.notes, 'Faster scans.');
      expect(m.isNewerThan(19), isTrue);
      expect(m.isNewerThan(20), isFalse);
      expect(m.isRequiredFor(17), isTrue);
      expect(m.isRequiredFor(18), isFalse);
    });

    test('rejects non-https urls, bad hashes and odd sizes', () {
      expect(() => UpdateManifest.fromJson(_manifest(url: 'http://example.com/a.exe')), throwsFormatException);
      expect(() => UpdateManifest.fromJson(_manifest(hash: 'abc')), throwsFormatException);
      expect(() => UpdateManifest.fromJson(_manifest(size: 0)), throwsFormatException);
      expect(() => UpdateManifest.fromJson({'version': '1.0.1'}), throwsFormatException);
      expect(() => UpdateManifest.fromJson([1, 2]), throwsFormatException);
    });
  });

  group('signatureProblem', () {
    test('an unsigned build relies on the hash', () {
      expect(signatureProblem(selfStatus: 'NotSigned', selfSubject: '', setupStatus: 'NotSigned', setupSubject: ''),
          isNull);
    });

    test('a signed build needs the same publisher', () {
      const me = 'CN=Big Duck Networks';
      expect(signatureProblem(selfStatus: 'Valid', selfSubject: me, setupStatus: 'Valid', setupSubject: me), isNull);
      expect(signatureProblem(selfStatus: 'Valid', selfSubject: me, setupStatus: 'NotSigned', setupSubject: ''),
          isNotNull);
      expect(signatureProblem(selfStatus: 'Valid', selfSubject: me, setupStatus: 'Valid', setupSubject: 'CN=Other'),
          isNotNull);
    });
  });

  group('DesktopUpdater', () {
    late Directory dir;
    late _FakeTransport transport;
    late _FakeInstaller installer;
    late ProviderContainer container;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pd_update_test');
      transport = _FakeTransport(_manifest());
      installer = _FakeInstaller();
      container = ProviderContainer(overrides: [
        currentBuildProvider.overrideWithValue(14),
        updateTransportProvider.overrideWithValue(transport),
        updateInstallerProvider.overrideWithValue(installer),
        updateDownloadDirProvider.overrideWithValue(dir),
      ]);
    });

    tearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });

    DesktopUpdater updater() => container.read(desktopUpdaterProvider.notifier);
    UpdateState state() => container.read(desktopUpdaterProvider);

    test('finds a newer build from the latest release', () async {
      await updater().check();
      expect(transport.fetched.single.toString(), updateManifestUrl);
      expect(state().phase, UpdatePhase.available);
      expect(state().manifest!.version, '1.0.1');
    });

    test('is up to date on the same build', () async {
      transport.manifest = _manifest(build: 14);
      await updater().check();
      expect(state().phase, UpdatePhase.upToDate);
      expect(state().hasUpdate, isFalse);
    });

    test('a failed background check stays quiet; a requested one says so', () async {
      transport.manifest = null;
      await updater().check();
      expect(state().phase, UpdatePhase.idle);
      await updater().check(userAsked: true);
      expect(state().phase, UpdatePhase.failed);
      expect(state().error, isNotNull);
    });

    test('downloads, verifies, runs the installer and quits', () async {
      await updater().check();
      await updater().install();
      expect(installer.launched, isNotNull);
      expect(installer.launched!.readAsBytesSync(), _setupBytes);
      expect(installer.quit, isTrue);
      expect(state().phase, UpdatePhase.installing);
    });

    test('a download that does not match the manifest is deleted, never run', () async {
      transport.body = utf8.encode('tampered installer');
      transport.manifest = _manifest(size: utf8.encode('tampered installer').length);
      await updater().check();
      await updater().install();
      expect(installer.launched, isNull);
      expect(state().phase, UpdatePhase.failed);
      expect(dir.listSync(), isEmpty);
    });

    test('a bad signature stops the install', () async {
      installer.signatureProblem = 'The update isn’t signed. It wasn’t installed.';
      await updater().check();
      await updater().install();
      expect(installer.launched, isNull);
      expect(state().error, installer.signatureProblem);
      expect(dir.listSync(), isEmpty);
    });

    test('declining the admin prompt keeps the update on offer', () async {
      installer.accept = false;
      await updater().check();
      await updater().install();
      expect(installer.quit, isFalse);
      expect(state().phase, UpdatePhase.available);
      expect(state().error, 'Update cancelled.');
    });
  });

  test('the real signature check runs PowerShell and reads its answer', () async {
    // The test runner is unsigned, so any readable answer means "may run";
    // a quoting or parsing failure would say it couldn't check.
    final notepad = File('${Platform.environment['SystemRoot']}\\System32\\notepad.exe');
    expect(await WindowsUpdateInstaller().checkSignature(notepad), isNull);
  }, skip: !Platform.isWindows);

  test('encodePowerShell is UTF-16LE Base64', () {
    expect(encodePowerShell('ab'), base64.encode([0x61, 0, 0x62, 0]));
  });

  test('verifyDownload checks size and hash', () async {
    final dir = Directory.systemTemp.createTempSync('pd_verify_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/s.exe')..writeAsBytesSync(_setupBytes);
    final m = UpdateManifest.fromJson(_manifest());
    expect(await verifyDownload(f, m), isNull);
    f.writeAsBytesSync([..._setupBytes, 0]);
    expect(await verifyDownload(f, m), isNotNull);
  });
}
