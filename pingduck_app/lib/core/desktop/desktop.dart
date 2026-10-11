import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/scanner/application/scan_controller.dart';

/// PingDuck for Windows, like Fing Desktop: a normal window that closes to
/// the tray and can start with Windows (minimized). Elsewhere every call
/// here is a no-op.
bool get isDesktop =>
    debugDesktopOverride ?? (Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST'));

/// Tests run on Windows too; they get the phone layout unless they set this.
bool? debugDesktopOverride;

/// The window size the desktop layout is designed for.
const desktopMinSize = Size(960, 640);

/// Passed by the Run-key entry, so a login start goes straight to the tray.
const minimizedFlag = '--minimized';

Future<void> initDesktop(List<String> args) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'PingDuck',
    size: Size(1280, 820),
    minimumSize: desktopMinSize,
    center: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (!args.contains(minimizedFlag)) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  // Close hides to the tray; Quit in the tray menu exits.
  await windowManager.setPreventClose(true);
}

/// Registers the tray icon and the close-to-tray behaviour around the app.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> with WindowListener, TrayListener {
  static const _open = 'open', _scan = 'scan', _quit = 'quit';

  @override
  void initState() {
    super.initState();
    if (!isDesktop) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    _setUpTray();
  }

  Future<void> _setUpTray() async {
    await trayManager.setIcon('assets/branding/tray.ico');
    await trayManager.setToolTip('PingDuck');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _open, label: 'Open PingDuck'),
          MenuItem(key: _scan, label: 'Scan now'),
          MenuItem.separator(),
          MenuItem(key: _quit, label: 'Quit PingDuck'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() => windowManager.hide();

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case _open:
        _show();
      case _scan:
        ref.read(scanControllerProvider.notifier).scan();
      case _quit:
        trayManager.destroy();
        windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Start PingDuck with Windows": a value under the user's Run key (no admin).
class StartWithWindows {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _value = 'PingDuck';

  static Future<bool> enabled() async {
    if (!isDesktop) return false;
    final r = await Process.run('reg', ['query', _key, '/v', _value]);
    return r.exitCode == 0;
  }

  static Future<void> set(bool on) async {
    if (!isDesktop) return;
    if (on) {
      final exe = Platform.resolvedExecutable;
      await Process.run('reg', ['add', _key, '/v', _value, '/t', 'REG_SZ', '/d', '"$exe" $minimizedFlag', '/f']);
    } else {
      await Process.run('reg', ['delete', _key, '/v', _value, '/f']);
    }
  }
}
