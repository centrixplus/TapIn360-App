import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Settings → Log out. With waiting taps it asks "Discard N unsent taps?" and
/// logs out only on confirm (spec §6.3).
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final waiting = await ref.read(tapStoreProvider).waitingCount();
  if (!context.mounted) return;
  final confirmed = await _confirm(
    context,
    title: waiting > 0
        ? 'logout.discard_title'.tr(namedArgs: {'count': '$waiting'})
        : 'logout.confirm_title'.tr(),
    body: waiting > 0 ? 'logout.discard_body'.tr() : 'logout.confirm_body'.tr(),
    confirm: waiting > 0 ? 'logout.discard_confirm'.tr() : 'settings.logout'.tr(),
  );
  if (confirmed) await ref.read(sessionProvider.notifier).logout();
}

/// Change company (TapIn360): logs out first, with the same discard question.
/// Returns whether to go ahead.
Future<bool> confirmChangeCompany(BuildContext context, WidgetRef ref) async {
  final loggedIn = ref.read(sessionProvider).isLoggedIn;
  final waiting = await ref.read(tapStoreProvider).waitingCount();
  if (!context.mounted) return false;
  if (!loggedIn && waiting == 0) return true;
  return _confirm(
    context,
    title: waiting > 0
        ? 'logout.discard_title'.tr(namedArgs: {'count': '$waiting'})
        : 'logout.change_company_title'.tr(),
    body: waiting > 0 ? 'logout.discard_body'.tr() : 'logout.change_company_body'.tr(),
    confirm: waiting > 0 ? 'logout.change_company_discard'.tr() : 'logout.change_company_confirm'.tr(),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('common.cancel'.tr())),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
