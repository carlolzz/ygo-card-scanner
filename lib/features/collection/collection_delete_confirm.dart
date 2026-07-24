import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../settings/settings_providers.dart';

/// Shows the "remove card?" confirmation when the
/// [AppSettings.confirmBeforeDelete] setting is on, returning whether the
/// removal should proceed. When the setting is off, returns `true` without
/// prompting.
///
/// Shared by every collection removal path — the list-row delete and
/// decrement-to-zero, and the detail screen's delete and decrement-to-zero — so
/// they all honour the one toggle and show one message.
Future<bool> confirmRemoveCard(BuildContext context, WidgetRef ref) async {
  final confirmRequired =
      ref.read(settingsControllerProvider).value?.confirmBeforeDelete ?? true;
  if (!confirmRequired) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.collectionDeleteDialogTitle),
      content: const Text(AppStrings.collectionDeleteDialogMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.collectionDeleteDialogCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.collectionDeleteDialogConfirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}
