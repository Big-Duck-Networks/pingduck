import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_version.dart';
import 'desktop.dart';

/// In-app updates for PingDuck for Windows.
///
/// Every Windows release (`.github/workflows/release-windows.yml`) attaches
/// `latest.json` next to `PingDuckSetup.exe` and is the repo's "latest"
/// release, so [updateManifestUrl] always names the newest build. The app
/// checks it shortly after launch and then once a day, and compares build
/// numbers (the commit count on `main`, so they only go up).
///
/// Installing downloads the installer, checks its size and SHA-256 against
/// the manifest and, when this build is code-signed, that the installer is
/// signed by the same publisher. Then it runs the installer with
/// `/SILENT /UPDATE=1` through Windows' admin prompt, and the installer
/// replaces the app and the agent service and reopens the app.
///
/// A release marked required raises `minimumBuild`; older builds then
/// install it without waiting for a click (Windows still shows its prompt).
const updateManifestUrl = 'https://github.com/Big-Duck-Networks/pingduck/releases/latest/download/latest.json';

/// Wait after launch before the first check, so it never slows startup.
const _firstCheckDelay = Duration(seconds: 20);
const _checkEvery = Duration(hours: 24);

/// Refuse anything larger: the installer is ~15 MB.
const _maxInstallerBytes = 300 * 1024 * 1024;
const _maxManifestBytes = 64 * 1024;

/// `latest.json` from a Windows release.
@immutable
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    required this.size,
    this.notes = '',
    this.minimumBuild = 0,
  });

  final String version;
  final int build;
  final Uri url;
  final String sha256;
  final int size;
  final String notes;
  final int minimumBuild;

  /// Throws [FormatException] unless every required field is there and sane.
  factory UpdateManifest.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('manifest is not an object');
    final version = json['version'], build = json['build'], url = json['url'];
    final hash = json['sha256'], size = json['size'];
    if (version is! String || build is! int || url is! String || hash is! String || size is! int) {
      throw const FormatException('manifest is missing a field');
    }
    final uri = Uri.tryParse(url);
    // Only ever download over HTTPS.
    if (uri == null || uri.scheme != 'https') throw const FormatException('manifest url is not https');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) throw const FormatException('manifest sha256 is malformed');
    if (size <= 0 || size > _maxInstallerBytes) throw const FormatException('manifest size is out of range');
    final notes = json['notes'], minimum = json['minimumBuild'];
    return UpdateManifest(
      version: version,
      build: build,
      url: uri,
      sha256: hash,
      size: size,
      notes: notes is String ? notes.trim() : '',
      minimumBuild: minimum is int ? minimum : 0,
    );
  }

  bool isNewerThan(int currentBuild) => build > currentBuild;

  /// This build is below the floor a required release set.
  bool isRequiredFor(int currentBuild) => currentBuild < minimumBuild && isNewerThan(currentBuild);
}

enum UpdatePhase { idle, checking, upToDate, available, downloading, installing, failed }

@immutable
class UpdateState {
  const UpdateState({this.phase = UpdatePhase.idle, this.manifest, this.progress, this.error, this.checkedAt});

  final UpdatePhase phase;

  /// The newer release, once one is found.
  final UpdateManifest? manifest;

  /// 0–1 while downloading.
  final double? progress;
  final String? error;
  final DateTime? checkedAt;

  bool get hasUpdate => manifest != null;
  bool get isBusy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading || phase == UpdatePhase.installing;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateManifest? manifest,
    double? progress,
    String? error,
    DateTime? checkedAt,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        manifest: manifest ?? this.manifest,
        progress: progress,
        error: error,
        checkedAt: checkedAt ?? this.checkedAt,
      );
}

/// Network access for the updater; tests swap it out.
abstract class UpdateTransport {
  Future<String> fetchText(Uri url);

  /// Streams [url] into [to], reporting bytes received. Throws past [maxBytes].
  Future<void> download(Uri url, File to, {required int maxBytes, void Function(int received)? onProgress});
}

class HttpUpdateTransport implements UpdateTransport {
  static const _timeout = Duration(seconds: 30);

  HttpClient _client() => HttpClient()
    ..connectionTimeout = _timeout
    ..userAgent = 'PingDuck/${AppVersion.versionName} (Windows)';

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    // GET follows GitHub's redirect to its download host.
    final res = await (await client.getUrl(url)).close().timeout(_timeout);
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return res;
  }

  @override
  Future<String> fetchText(Uri url) async {
    final client = _client();
    try {
      final res = await _get(client, url);
      final bytes = <int>[];
      await for (final chunk in res.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxManifestBytes) throw const FormatException('manifest too large');
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(Uri url, File to, {required int maxBytes, void Function(int received)? onProgress}) async {
    final client = _client();
    final sink = to.openWrite();
    try {
      final res = await _get(client, url);
      var received = 0;
      await for (final chunk in res.timeout(_timeout)) {
        received += chunk.length;
        if (received > maxBytes) throw const FormatException('download larger than the manifest says');
        sink.add(chunk);
        onProgress?.call(received);
      }
    } finally {
      await sink.close();
      client.close(force: true);
    }
  }
}

/// Talks to Windows for the updater; tests swap it out.
abstract class UpdateInstaller {
  /// Null when the installer may run; otherwise why not.
  Future<String?> checkSignature(File setup);

  /// Runs the installer through the admin prompt. False if the user said no.
  Future<bool> launch(File setup);

  /// Closes the app so the installer can replace it.
  Future<void> quitApp();
}

class WindowsUpdateInstaller implements UpdateInstaller {
  static const installerArgs = ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/UPDATE=1'];

  /// Paths go through the environment, never into the script, and the script
  /// goes as -EncodedCommand: Windows' argument parsing would strip its
  /// quotes otherwise.
  Future<ProcessResult> _powershell(String script, Map<String, String> env) => Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encodePowerShell(script)],
        environment: env,
      );

  @override
  Future<String?> checkSignature(File setup) async {
    const script = r'''
$self = Get-AuthenticodeSignature -LiteralPath $env:PD_SELF
$new  = Get-AuthenticodeSignature -LiteralPath $env:PD_SETUP
"$($self.Status)|$($self.SignerCertificate.Subject)|$($new.Status)|$($new.SignerCertificate.Subject)"
''';
    final r = await _powershell(script, {'PD_SELF': Platform.resolvedExecutable, 'PD_SETUP': setup.path});
    final parts = '${r.stdout}'.trim().split('|');
    if (r.exitCode != 0 || parts.length != 4) return 'Couldn’t check the update’s signature.';
    return signatureProblem(
      selfStatus: parts[0],
      selfSubject: parts[1],
      setupStatus: parts[2],
      setupSubject: parts[3],
    );
  }

  @override
  Future<bool> launch(File setup) async {
    // Start-Process goes through ShellExecute, which shows the admin prompt
    // the installer's manifest asks for; Process.start would just fail.
    const script = r'''
Start-Process -FilePath $env:PD_SETUP -ArgumentList $env:PD_ARGS.Split(' ') -Verb RunAs
''';
    final r = await _powershell(script, {'PD_SETUP': setup.path, 'PD_ARGS': installerArgs.join(' ')});
    // Declining the prompt makes Start-Process throw, so a non-zero exit.
    return r.exitCode == 0;
  }

  @override
  Future<void> quitApp() => quitDesktopApp();
}

/// PowerShell's -EncodedCommand form: Base64 of the script in UTF-16LE.
@visibleForTesting
String encodePowerShell(String script) =>
    base64.encode([for (final c in script.codeUnits) ...[c & 0xff, c >> 8]]);

/// Null when an installer may run. A signed build only runs an installer
/// with a valid signature from its own publisher; an unsigned build (before
/// code signing is set up) has nothing to compare against and relies on the
/// manifest's SHA-256.
@visibleForTesting
String? signatureProblem({
  required String selfStatus,
  required String selfSubject,
  required String setupStatus,
  required String setupSubject,
}) {
  if (selfStatus != 'Valid') return null;
  if (setupStatus != 'Valid') return 'The update isn’t signed. It wasn’t installed.';
  if (setupSubject != selfSubject) return 'The update is signed by someone else. It wasn’t installed.';
  return null;
}

/// This build's number; tests override it.
final currentBuildProvider = Provider<int>((ref) => AppVersion.buildNumber);
final updateTransportProvider = Provider<UpdateTransport>((ref) => HttpUpdateTransport());
final updateInstallerProvider = Provider<UpdateInstaller>((ref) => WindowsUpdateInstaller());

/// Where installers are downloaded; tests override it.
final updateDownloadDirProvider = Provider<Directory>(
  (ref) => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}PingDuckUpdate'),
);

final desktopUpdaterProvider = NotifierProvider<DesktopUpdater, UpdateState>(DesktopUpdater.new);

class DesktopUpdater extends Notifier<UpdateState> {
  Timer? _timer;

  @override
  UpdateState build() {
    ref.onDispose(() => _timer?.cancel());
    return const UpdateState();
  }

  /// Schedules the background checks. Desktop release builds only: a debug
  /// build's number isn't comparable with CI's.
  void start() {
    if (!isDesktop || kDebugMode || _timer != null) return;
    _timer = Timer(_firstCheckDelay, () {
      _timer = Timer.periodic(_checkEvery, (_) => _backgroundCheck());
      _backgroundCheck();
    });
  }

  Future<void> _backgroundCheck() async {
    await check();
    final m = state.manifest;
    if (m != null && m.isRequiredFor(ref.read(currentBuildProvider)) && state.phase == UpdatePhase.available) {
      await install();
    }
  }

  /// Looks for a newer release. Quiet on failure unless [userAsked].
  Future<void> check({bool userAsked = false}) async {
    if (state.isBusy) return;
    state = state.copyWith(phase: UpdatePhase.checking);
    try {
      final text = await ref.read(updateTransportProvider).fetchText(Uri.parse(updateManifestUrl));
      final manifest = UpdateManifest.fromJson(jsonDecode(text));
      final now = DateTime.now();
      if (manifest.isNewerThan(ref.read(currentBuildProvider))) {
        state = UpdateState(phase: UpdatePhase.available, manifest: manifest, checkedAt: now);
      } else {
        state = UpdateState(phase: UpdatePhase.upToDate, checkedAt: now);
      }
    } catch (e) {
      debugPrint('update check failed: $e');
      state = userAsked
          ? state.copyWith(phase: UpdatePhase.failed, error: 'Couldn’t check for updates. Try again later.')
          : state.copyWith(phase: state.hasUpdate ? UpdatePhase.available : UpdatePhase.idle);
    }
  }

  /// Downloads, verifies and runs the installer, then closes the app.
  Future<void> install() async {
    final m = state.manifest;
    if (m == null || state.isBusy) return;
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    final dir = ref.read(updateDownloadDirProvider);
    final setup = File('${dir.path}${Platform.pathSeparator}PingDuckSetup-${m.version}+${m.build}.exe');
    try {
      await dir.create(recursive: true);
      // Never reuse a file from earlier: always download and verify afresh.
      if (await setup.exists()) await setup.delete();
      await ref.read(updateTransportProvider).download(
            m.url,
            setup,
            maxBytes: m.size,
            onProgress: (n) => state = state.copyWith(phase: UpdatePhase.downloading, progress: n / m.size),
          );
      final problem = await verifyDownload(setup, m) ?? await ref.read(updateInstallerProvider).checkSignature(setup);
      if (problem != null) {
        await _discard(setup);
        state = state.copyWith(phase: UpdatePhase.failed, error: problem);
        return;
      }
      state = state.copyWith(phase: UpdatePhase.installing);
      final installer = ref.read(updateInstallerProvider);
      if (!await installer.launch(setup)) {
        state = state.copyWith(phase: UpdatePhase.available, error: 'Update cancelled.');
        return;
      }
      await installer.quitApp();
    } catch (e) {
      debugPrint('update install failed: $e');
      await _discard(setup);
      state = state.copyWith(phase: UpdatePhase.failed, error: 'Couldn’t download the update. Try again later.');
    }
  }

  Future<void> _discard(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Null when [file] matches [m]'s size and SHA-256; otherwise why not.
@visibleForTesting
Future<String?> verifyDownload(File file, UpdateManifest m) async {
  if (await file.length() != m.size) return 'The download was incomplete. Try again.';
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != m.sha256) return 'The download didn’t match the release. It wasn’t installed.';
  return null;
}
