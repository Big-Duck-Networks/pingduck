import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/pingduck_colors.dart';
import '../../core/theme/pingduck_theme.dart';
import '../../core/widgets/pd_widgets.dart';
import '../account/presentation/account_screen.dart';
import '../scanner/application/scan_controller.dart';
import '../scanner/presentation/discovery_screen.dart';
import '../tools/presentation/tools_screen.dart';
import '../topology/presentation/topology_screen.dart';

enum AppTab { discovery, topology, tools, account }

final appTabProvider = NotifierProvider<AppTabController, AppTab>(AppTabController.new);

class AppTabController extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.discovery;

  void go(AppTab tab) => state = tab;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(appTabProvider);
    return Scaffold(
      appBar: const _Header(),
      body: IndexedStack(
        index: tab.index,
        children: const [DiscoveryScreen(), TopologyScreen(), ToolsScreen(), AccountScreen()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: PingDuckColors.hairline))),
        child: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (i) => ref.read(appTabProvider.notifier).go(AppTab.values[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'DISCOVERY'),
            NavigationDestination(icon: Icon(Icons.hub_outlined), label: 'TOPOLOGY'),
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
    final lan = scan.lan;
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
                  child: Text('PINGDUCK', style: PdText.headlineMd.copyWith(color: PingDuckColors.live, letterSpacing: 1.5)),
                ),
                Text('LAN RECON', style: PdText.labelMd.copyWith(letterSpacing: 2), overflow: TextOverflow.clip, maxLines: 1),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150),
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
                  color: lan == null ? PingDuckColors.inkMuted : PingDuckColors.live,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text((lan?.interfaceName ?? 'LAN').toUpperCase(),
                          style: PdText.labelSm.copyWith(color: PingDuckColors.route),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(lan?.cidr ?? 'not scanned', style: PdText.code, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
