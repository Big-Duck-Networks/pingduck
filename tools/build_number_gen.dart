// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Build Number & Version Generator for PingDuck.
///
/// Features & Improvements over standard generators:
/// - Robust Monorepo Auto-Discovery: Locates pingduck_app/pubspec.yaml from any working directory
/// - SemVer Bumping: Supports --patch, --minor, --major version bumps
/// - CalVer (YYYY.MM.DD) and custom version overrides
/// - Flexible Build Strategies: Sequential (+1), Git commit count (--git), or timestamp (--timestamp)
/// - Auto-Generates Compile-Time Dart Constant: Generates lib/core/constants/app_version.dart for UI
/// - CI/CD Integration: Supports --github-output and --json
/// - Safe & Atomic: Validates before writing, supports --dry-run
///
/// Usage:
///   dart run tools/build_number_gen.dart                 # Increments build number (+1), preserves version
///   dart run tools/build_number_gen.dart --patch         # Bumps patch (1.0.0 -> 1.0.1) & increments build
///   dart run tools/build_number_gen.dart --minor         # Bumps minor (1.0.0 -> 1.1.0) & increments build
///   dart run tools/build_number_gen.dart --major         # Bumps major (1.0.0 -> 2.0.0) & increments build
///   dart run tools/build_number_gen.dart --calver        # Sets version name to today's date (YYYY.MM.DD)
///   dart run tools/build_number_gen.dart --git           # Uses git commit count as build number
///   dart run tools/build_number_gen.dart --timestamp     # Uses chronological timestamp (YMMddHHmm)
///   dart run tools/build_number_gen.dart --version 1.2.0 # Explicitly sets version name
///   dart run tools/build_number_gen.dart --build 50      # Explicitly sets build number
///   dart run tools/build_number_gen.dart --sync          # Reads and prints current full version
///   dart run tools/build_number_gen.dart --dry-run       # Previews changes without writing to disk
///   dart run tools/build_number_gen.dart --json          # Outputs result in JSON format

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    _printHelp();
    return;
  }

  // 1. Locate pubspec.yaml in monorepo
  final pubspecFile = _findPubspecFile();
  if (pubspecFile == null) {
    stderr.writeln('Error: Could not locate pingduck_app/pubspec.yaml.');
    stderr.writeln('Please run this command from the repository root or pingduck_app directory.');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s*([^\s+]+)(?:\+(\d+))?', multiLine: true);
  final match = versionRegex.firstMatch(pubspecContent);

  if (match == null) {
    stderr.writeln('Error: Could not find valid "version:" entry in ${pubspecFile.path}');
    exit(1);
  }

  final currentVersionName = match.group(1) ?? '1.0.0';
  final currentBuildNumber = int.tryParse(match.group(2) ?? '1') ?? 1;
  final currentFullVersion = match.group(2) != null
      ? '$currentVersionName+$currentBuildNumber'
      : currentVersionName;

  // 2. Parse command line flags
  final isDryRun = args.contains('--dry-run');
  final isSyncOnly = args.contains('--sync') || args.contains('--sync-only');
  final isJson = args.contains('--json');
  final useGit = args.contains('--git');
  final useTimestamp = args.contains('--timestamp');
  final useCalVer = args.contains('--calver');
  final bumpPatch = args.contains('--patch');
  final bumpMinor = args.contains('--minor');
  final bumpMajor = args.contains('--major');
  final noCode = args.contains('--no-code');
  final githubOutput = args.contains('--github-output');

  String? customVersion;
  int? customBuild;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--version' || args[i] == '-v') {
      if (i + 1 < args.length) customVersion = args[i + 1];
    } else if (args[i] == '--build' || args[i] == '-b') {
      if (i + 1 < args.length) customBuild = int.tryParse(args[i + 1]);
    }
  }

  // Handle read-only sync flag
  if (isSyncOnly) {
    if (isJson) {
      print(jsonEncode({
        'version': currentVersionName,
        'build': currentBuildNumber,
        'fullVersion': currentFullVersion,
      }));
    } else {
      print(currentFullVersion);
    }
    return;
  }

  // 3. Compute new Version Name
  String newVersionName;
  if (customVersion != null) {
    newVersionName = customVersion;
  } else if (useCalVer) {
    final now = DateTime.now();
    final yyyy = now.year.toString();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    newVersionName = '$yyyy.$mm.$dd';
  } else if (bumpMajor) {
    newVersionName = _bumpSemVer(currentVersionName, SemVerPart.major);
  } else if (bumpMinor) {
    newVersionName = _bumpSemVer(currentVersionName, SemVerPart.minor);
  } else if (bumpPatch) {
    newVersionName = _bumpSemVer(currentVersionName, SemVerPart.patch);
  } else {
    newVersionName = currentVersionName;
  }

  // 4. Compute new Build Number
  int newBuildNumber;
  if (customBuild != null) {
    newBuildNumber = customBuild;
  } else if (useGit) {
    newBuildNumber = _getGitCommitCount() ?? (currentBuildNumber + 1);
  } else if (useTimestamp) {
    final now = DateTime.now();
    final y = (now.year % 10).toString();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    newBuildNumber = int.tryParse('$y$mm$dd$hh$min') ?? (currentBuildNumber + 1);
  } else {
    newBuildNumber = currentBuildNumber + 1;
  }

  final newFullVersion = '$newVersionName+$newBuildNumber';
  final gitHash = _getGitShortSha() ?? 'unknown';

  // 5. Output summary
  if (isJson) {
    print(jsonEncode({
      'previousVersion': currentFullVersion,
      'newVersion': newFullVersion,
      'versionName': newVersionName,
      'buildNumber': newBuildNumber,
      'gitCommit': gitHash,
      'dryRun': isDryRun,
    }));
  } else {
    print('========================================');
    print('  PingDuck App Build & Version Generator');
    print('========================================');
    print('Target File      : ${pubspecFile.path}');
    print('Previous Version : $currentFullVersion');
    print('New Version      : $newFullVersion');
    print('Version Name     : $newVersionName');
    print('Build Number     : $newBuildNumber');
    print('Git Commit SHA   : $gitHash');
    print('Dry Run          : $isDryRun');
    print('========================================');
  }

  if (isDryRun) {
    if (!isJson) print('[Dry Run] No files modified.');
    return;
  }

  // 6. Update pubspec.yaml atomically
  final updatedPubspec = pubspecContent.replaceFirst(
    versionRegex,
    'version: $newFullVersion',
  );
  pubspecFile.writeAsStringSync(updatedPubspec);
  if (!isJson) print('Updated ${pubspecFile.path} -> version: $newFullVersion');

  // 7. Auto-generate Dart compile-time constant file (lib/core/constants/app_version.dart)
  if (!noCode) {
    _generateDartConstants(pubspecFile.parent, newVersionName, newBuildNumber, newFullVersion, gitHash);
  }

  // 8. GitHub Actions CI Output support
  if (githubOutput) {
    _writeGithubOutput({
      'version_name': newVersionName,
      'build_number': newBuildNumber.toString(),
      'full_version': newFullVersion,
      'git_commit': gitHash,
    });
  }

  if (!isJson) {
    print('\n[Success] PingDuck version set to $newFullVersion');
  }
}

/// Locates pubspec.yaml across monorepo layouts.
File? _findPubspecFile() {
  final candidates = [
    File('pingduck_app/pubspec.yaml'),
    File('pubspec.yaml'),
    File('../pingduck_app/pubspec.yaml'),
    File('../pubspec.yaml'),
  ];

  for (final file in candidates) {
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      if (content.contains('name: pingduck_app')) {
        return file;
      }
    }
  }

  // Search up to 3 levels up
  var dir = Directory.current;
  for (int i = 0; i < 3; i++) {
    final sub = File('${dir.path}/pingduck_app/pubspec.yaml');
    if (sub.existsSync()) return sub;
    final here = File('${dir.path}/pubspec.yaml');
    if (here.existsSync() && here.readAsStringSync().contains('name: pingduck_app')) {
      return here;
    }
    dir = dir.parent;
  }
  return null;
}

enum SemVerPart { major, minor, patch }

/// Safely increments semantic version components.
String _bumpSemVer(String version, SemVerPart part) {
  final clean = version.split('-').first; // strip pre-release
  final parts = clean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }

  var major = parts[0];
  var minor = parts[1];
  var patch = parts[2];

  switch (part) {
    case SemVerPart.major:
      major += 1;
      minor = 0;
      patch = 0;
      break;
    case SemVerPart.minor:
      minor += 1;
      patch = 0;
      break;
    case SemVerPart.patch:
      patch += 1;
      break;
  }

  return '$major.$minor.$patch';
}

/// Generates a static Dart constant file in pingduck_app/lib/core/constants/app_version.dart
void _generateDartConstants(Directory appDir, String versionName, int buildNumber, String fullVersion, String gitHash) {
  final constantsDir = Directory('${appDir.path}/lib/core/constants');
  if (!constantsDir.existsSync()) {
    constantsDir.createSync(recursive: true);
  }

  final targetFile = File('${constantsDir.path}/app_version.dart');
  final now = DateTime.now().toUtc().toIso8601String().split('T').first;

  final code = '''// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by tools/build_number_gen.dart

/// Compile-time application version metadata for PingDuck.
class AppVersion {
  AppVersion._();

  /// Semantic version string (e.g. "1.0.0").
  static const String versionName = '$versionName';

  /// Monotonically increasing build number (e.g. $buildNumber).
  static const int buildNumber = $buildNumber;

  /// Combined Flutter version identifier (e.g. "$fullVersion").
  static const String fullVersion = '$fullVersion';

  /// Git commit short hash at build time.
  static const String gitCommit = '$gitHash';

  /// Build generation date (UTC, YYYY-MM-DD).
  static const String buildDate = '$now';

  /// Returns user-facing formatted version string.
  static String get display => 'v\$versionName (\$buildNumber)';
}
''';

  targetFile.writeAsStringSync(code);
  print('Generated ${targetFile.path}');
}

int? _getGitCommitCount() {
  try {
    final result = Process.runSync('git', ['rev-list', '--count', 'HEAD']);
    if (result.exitCode == 0) {
      return int.tryParse(result.stdout.toString().trim());
    }
  } catch (_) {}
  return null;
}

String? _getGitShortSha() {
  try {
    final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (result.exitCode == 0) {
      return result.stdout.toString().trim();
    }
  } catch (_) {}
  return null;
}

void _writeGithubOutput(Map<String, String> values) {
  final outputPath = Platform.environment['GITHUB_OUTPUT'];
  if (outputPath != null && outputPath.isNotEmpty) {
    final file = File(outputPath);
    final sink = file.openWrite(mode: FileMode.append);
    values.forEach((k, v) => sink.writeln('$k=$v'));
    sink.close();
  }
}

void _printHelp() {
  print('''
PingDuck App Build Number & Version Generator

Usage:
  dart run tools/build_number_gen.dart [options]

Version Name Options:
  --patch              Bump patch version (1.0.0 -> 1.0.1)
  --minor              Bump minor version (1.0.0 -> 1.1.0)
  --major              Bump major version (1.0.0 -> 2.0.0)
  --calver             Set version to today's CalVer date (YYYY.MM.DD)
  --version, -v <val>  Specify custom version name explicitly (e.g. 1.2.0)

Build Number Options:
  --build, -b <num>    Specify custom build number explicitly (e.g. 100)
  --git                Use Git commit count as build number
  --timestamp          Use chronological timestamp (YMMddHHmm) as build number
  (default)            Increments existing build number by +1

Automation & Output Options:
  --sync               Print current version from pubspec.yaml and exit
  --dry-run            Preview calculation without modifying any files
  --json               Output result as JSON for automated pipelines
  --no-code            Skip generating lib/core/constants/app_version.dart
  --github-output      Write version variables to \$GITHUB_OUTPUT for CI/CD
  --help, -h           Show this help message
''');
}
