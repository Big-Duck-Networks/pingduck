import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';

/// Every route of the Add monitoring unit flow is named with this prefix, so
/// "Maybe later" and "Done" can close the whole flow at once.
const agentFlowPrefix = 'agent/';

Future<T?> pushAgentFlow<T>(BuildContext context, String name, Widget screen) => Navigator.of(context).push<T>(
  MaterialPageRoute(settings: RouteSettings(name: '$agentFlowPrefix$name'), builder: (_) => screen),
);

/// Pops every route of the flow, back to where it was opened from.
void closeAgentFlow(BuildContext context) => Navigator.of(
  context,
).popUntil((r) => !(r.settings.name?.startsWith(agentFlowPrefix) ?? false));

/// The flow's page layout, after Fing's: a back arrow, a large headline and
/// a supporting line, the body, and the actions pinned to the bottom.
class FlowScaffold extends StatelessWidget {
  const FlowScaffold({
    super.key,
    this.showBack = true,
    this.illustration,
    required this.title,
    this.lead,
    required this.body,
    required this.actions,
  });

  final bool showBack;
  final Widget? illustration;
  final String title;
  final String? lead;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PingDuckColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: showBack
                    ? IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, size: 22),
                      )
                    : const SizedBox(height: 48),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (illustration != null) ...[Center(child: illustration), const SizedBox(height: 32)],
                    Text(title, style: PdText.headlineLg),
                    if (lead != null) ...[
                      const SizedBox(height: 10),
                      Text(lead!, style: PdText.bodyLg.copyWith(color: PingDuckColors.inkSecondary)),
                    ],
                    const SizedBox(height: 24),
                    body,
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: PingDuckColors.canvas,
                border: Border(top: BorderSide(color: PingDuckColors.hairline)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 8), actions[i]],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fing's "Maybe later": closes the whole flow.
class MaybeLaterButton extends StatelessWidget {
  const MaybeLaterButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => closeAgentFlow(context),
    child: Text('MAYBE LATER', style: PdText.labelLg),
  );
}

/// A full-width primary action, taller than the default button.
class FlowPrimaryButton extends StatelessWidget {
  const FlowPrimaryButton({super.key, required this.label, this.icon, this.onPressed});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      PdButton(label: label, icon: icon, style: PdButtonStyle.primary, height: 52, onPressed: onPressed);
}

/// A square icon tile, the system's stand-in for illustrations.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 64, this.color = PingDuckColors.ink, this.child});
  final IconData icon;
  final double size;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: PingDuckColors.surface1,
      border: Border.all(color: PingDuckColors.keyline, width: 2),
      boxShadow: const [BoxShadow(color: PingDuckColors.keyline, offset: Offset(3, 3))],
    ),
    child: child ?? Icon(icon, size: size * 0.5, color: color),
  );
}

/// A shell command in a code block, with a copy button.
class CommandBlock extends StatelessWidget {
  const CommandBlock(this.command, {super.key});
  final String command;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: PingDuckColors.surface2,
        border: Border.fromBorderSide(BorderSide(color: PingDuckColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
              child: SelectableText(command, style: PdText.code),
            ),
          ),
          IconButton(
            tooltip: 'Copy command',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// A dashed hairline, horizontal or vertical.
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.vertical = false, this.color = PingDuckColors.partition});
  final bool vertical;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: vertical ? const Size(1, double.infinity) : const Size(double.infinity, 1),
    painter: _DashPainter(vertical, color),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.vertical, this.color);
  final bool vertical;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final length = vertical ? size.height : size.width;
    for (double p = 0; p < length; p += 8) {
      final end = (p + 4).clamp(0, length).toDouble();
      vertical
          ? canvas.drawLine(Offset(size.width / 2, p), Offset(size.width / 2, end), paint)
          : canvas.drawLine(Offset(p, size.height / 2), Offset(end, size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.vertical != vertical || old.color != color;
}
