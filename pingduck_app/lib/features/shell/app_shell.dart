import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/lan_connectivity.dart';
import '../../core/theme/pingduck_colors.dart';
import '../../core/theme/pingduck_theme.dart';
import '../../core/widgets/pd_widgets.dart';
import '../account/presentation/account_screen.dart';
import '../networks/presentation/my_networks_screen.dart';
import '../scanner/application/scan_controller.dart';
import '../scanner/presentation/overview_screen.dart';
import '../tools/presentation/tools_screen.dart';

// Topology (lib/features/topology) is parked: the code is kept and tested, but
// it has no tab. To bring it back, add `topology` here after `overview`, plus
// its screen and destination below.
enum AppTab { overview, tools, account }

final appTabProvider = NotifierProvider<AppTabController, AppTab>(AppTabController.new);

class AppTabController extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.overview;

  void go(AppTab tab) => state = tab;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(appTabProvider);
    // Follow the connection: stop a scan when Wi-Fi drops, rescan when it
    // comes back.
    ref.listen(lanConnectedProvider, (prev, next) {
      final was = prev?.value, now = next.value;
      if (was == null || now == null || was == now) return;
      final scanner = ref.read(scanControllerProvider.notifier);
      now ? scanner.scan(automatic: true) : scanner.cancel();
    });
    return Scaffold(
      appBar: const _Header(),
      body: IndexedStack(index: tab.index, children: const [OverviewScreen(), ToolsScreen(), AccountScreen()]),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PingDuckColors.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (i) => ref.read(appTabProvider.notifier).go(AppTab.values[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'OVERVIEW'),
            NavigationDestination(icon: Icon(Icons.handyman_outlined), label: 'TOOLS'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'ACCOUNT'),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget implements PreferredSizeWidget {
  const _Header();

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final online = ref.watch(lanConnectedProvider).isOnLan;
    final lan = online ? scan.lan : null;
    return AppBar(
      toolbarHeight: 72,
      titleSpacing: 16,
      title: Row(
        children: [
          const DuckLogo(size: 36),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'PINGDUCK',
                    style: PdText.headlineMd.copyWith(color: PingDuckColors.live, letterSpacing: 1.5),
                  ),
                ),
                Text(
                  'LAN RECON',
                  style: PdText.labelMd.copyWith(letterSpacing: 2),
                  overflow: TextOverflow.clip,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Semantics(
            button: true,
            label: 'My networks',
            child: InkWell(
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyNetworksScreen())),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 170),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: PingDuckColors.surface1,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      color: !online
                          ? PingDuckColors.critical
                          : lan == null
                          ? PingDuckColors.inkMuted
                          : PingDuckColors.live,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            online ? (lan?.interfaceName ?? 'LAN').toUpperCase() : 'OFFLINE',
                            style: PdText.labelSm.copyWith(color: PingDuckColors.route),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            online ? (lan?.cidr ?? 'not scanned') : 'no Wi-Fi',
                            style: PdText.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: PingDuckColors.inkSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
