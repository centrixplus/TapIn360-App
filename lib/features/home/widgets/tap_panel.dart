import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/api/api_models.dart';
import '../../common/nfc_motif.dart';
import '../../common/tapin_widgets.dart';
import '../home_actions.dart';
import '../home_state.dart';

/// The big tap card: NFC motif, instruction, and the iPhone **Scan card** or
/// manual **Check in** / **Check out** buttons.
class TapPanel extends StatelessWidget {
  const TapPanel({super.key, required this.state, required this.actions});

  final HomeState state;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final (title, detail) = _texts();
    final enabled = !state.blocked;
    Widget motif = NfcMotifBadge(enabled: enabled);
    if (kDebugMode && enabled) {
      // Debug builds: long-press = simulated card read (no physical card needed).
      motif = GestureDetector(key: const Key('home.motif'), onLongPress: actions.simulateTap, child: motif);
    }
    return TapInCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          motif,
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TapInText.heading(arabic: arabic),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TapInText.bodySmall(arabic: arabic).copyWith(fontSize: 15, color: TapInColors.inkMuted),
            ),
          ],
          if (state.processing) ...[const SizedBox(height: 20), const LinearProgressIndicator()],
          ..._buttons(),
        ],
      ),
    );
  }

  (String, String?) _texts() {
    if (state.blocked) return ('home.paused'.tr(), null);
    if (state.processing) return ('home.processing'.tr(), null);
    final photo = state.photoRequired;
    if (state.punchMode == PunchMode.manual) {
      return switch (state.selectedAction) {
        PunchAction.checkIn => (state.isIos ? 'home.selected_in_ios'.tr() : 'home.selected_in'.tr(), null),
        PunchAction.checkOut => (state.isIos ? 'home.selected_out_ios'.tr() : 'home.selected_out'.tr(), null),
        _ => ('home.manual_title'.tr(), 'home.manual_detail'.tr()),
      };
    }
    if (state.isIos) {
      return ('home.ios_title'.tr(), photo ? 'home.ios_detail_photo'.tr() : 'home.ios_detail'.tr());
    }
    return ('home.hold_card'.tr(), photo ? 'home.hold_detail_photo'.tr() : 'home.hold_detail'.tr());
  }

  List<Widget> _buttons() {
    if (state.blocked || state.processing) return const [];
    final manual = state.punchMode == PunchMode.manual;
    final selected = state.selectedAction;
    return [
      if (manual) ...[
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'home.check_in'.tr(),
                icon: Icons.login_rounded,
                selected: selected == PunchAction.checkIn,
                onPressed: () => actions.selectAction(PunchAction.checkIn),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                label: 'home.check_out'.tr(),
                icon: Icons.logout_rounded,
                selected: selected == PunchAction.checkOut,
                onPressed: () => actions.selectAction(PunchAction.checkOut),
              ),
            ),
          ],
        ),
      ],
      if (state.isIos && (!manual || selected != null)) ...[
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('home.scan'),
            onPressed: actions.scan,
            icon: const Icon(Icons.contactless_rounded),
            label: Text('home.scan_card'.tr()),
          ),
        ),
      ],
      if (manual && selected != null)
        TextButton(onPressed: actions.cancelAction, child: Text('common.cancel'.tr())),
    ];
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    );
    return selected
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}
