import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../recognition/brand_logo.dart';
import '../../recognition/recognition.dart';

/// Node Inspect's Device and Operating system cards. Only fields with a
/// signal behind them are shown; inferred ones carry a LIKELY tag and the
/// user's own answers a SET BY YOU tag. [onEdit] opens the label editor.
class RecognitionPanels extends StatelessWidget {
  const RecognitionPanels(
    this.recognition, {
    super.key,
    required this.onEdit,
    this.onConfirm,
  });
  final Recognition recognition;
  final VoidCallback onEdit;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final r = recognition;
    final os = r.os;
    final edit = TextButton.icon(
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: const Text('EDIT'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );

    Widget? buildConfirm() => onConfirm == null || !r.hasGuesses
        ? null
        : TextButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('CONFIRM'),
            style: TextButton.styleFrom(
              foregroundColor: PingDuckColors.live,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );

    final deviceConfirm = buildConfirm();
    final deviceTrailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (deviceConfirm != null) ...[deviceConfirm, const SizedBox(width: 4)],
        edit,
      ],
    );

    if (!r.hasDevice && os == null) {
      return PdPanel(
        title: 'Device',
        icon: Icons.devices_outlined,
        trailing: edit,
        child: Text(
          'Not recognized yet. Tell PingDuck what it is, and devices that look the same will use your answer too.',
          style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.hasDevice)
          _FactsPanel(
            title: 'Device',
            icon: Icons.devices_outlined,
            trailing: deviceTrailing,
            headline: r.model ?? r.family ?? r.brand ?? r.module!,
            caption: r.model != null
                ? 'Model'
                : r.family != null
                    ? 'Family'
                    : r.brand != null
                        ? 'Brand'
                        : 'Network module',
            logo: r.brand == null ? null : BrandLogo.forName(r.brand!.value),
            rows: [
              ('Brand', r.brand),
              ('Model', r.model),
              ('Family', r.family),
              ('Network module', r.module),
            ],
          ),
        if (r.hasDevice && os != null) const SizedBox(height: 16),
        if (os != null)
          _FactsPanel(
            title: 'Operating system',
            icon: Icons.terminal_outlined,
            trailing: r.hasDevice ? (os.isGuess ? buildConfirm() : null) : deviceTrailing,
            headline: Fact(os.version == null ? os.name : '${os.name} ${os.version}', os.confidence),
            caption: 'Operating system',
            logo: BrandLogo.forName(os.name),
            rows: [
              if (os.vendor != null) ('Brand', Fact(os.vendor!, os.confidence)),
              ('Name', Fact(os.name, os.confidence)),
              if (os.version != null) ('Version', Fact(os.version!, os.confidence)),
            ],
          ),
      ],
    );
  }
}

class _FactsPanel extends StatelessWidget {
  const _FactsPanel({
    required this.title,
    required this.icon,
    required this.headline,
    required this.caption,
    required this.rows,
    this.logo,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Fact headline;
  final String caption;
  final Widget? logo;
  final Widget? trailing;
  final List<(String, Fact?)> rows;

  @override
  Widget build(BuildContext context) {
    return PdPanel(
      title: title,
      icon: icon,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline.value, style: PdText.headlineSm),
                    const SizedBox(height: 2),
                    Text(
                      headline.isGuess
                          ? '$caption · likely'
                          : headline.isUser
                              ? '$caption · set by you'
                              : caption,
                      style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              if (logo != null) ...[const SizedBox(width: 12), logo!],
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, fact) in rows)
            if (fact != null) _FactRow(label: label, fact: fact),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.fact});
  final String label;
  final Fact fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: PingDuckColors.hairline))),
      child: Row(
        children: [
          Text(label, style: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                if (fact.isGuess) const PdChip('LIKELY', tone: PdTone.pending),
                if (fact.isUser) const PdChip('SET BY YOU', tone: PdTone.ink),
                Text(fact.value, style: PdText.bodyMd, textAlign: TextAlign.end),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
