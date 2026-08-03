import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../settings/settings_providers.dart';

/// Shows the "remove card?" confirmation, returning whether the removal should
/// proceed.
///
/// Shared by every collection removal path — the list-row delete and
/// decrement-to-zero, the detail screen's delete and decrement-to-zero, and the
/// multi-select delete — so they all honour one toggle and show one message.
/// One helper rather than a plural sibling: this is the single place
/// [AppSettings.confirmBeforeDelete] is read, and a copy is a second place to
/// forget it.
///
/// Passing [bulkCount] marks the multi-select path, which **always prompts,
/// whatever the setting says.** That toggle exists so a one-tap row delete
/// doesn't need a dialog, where a mis-tap costs a single card and the row is
/// trivially re-added. Removing a selection is a different act: it is
/// irreversible, it can take dozens of entries at once, and the gesture that
/// triggers it sits one tap from the gesture that selects. The wording still
/// follows the count, so removing a single selected card doesn't say "1
/// entries".
Future<bool> confirmRemoveCard(
  BuildContext context,
  WidgetRef ref, {
  int? bulkCount,
}) async {
  final confirmRequired =
      bulkCount != null ||
      (ref.read(settingsControllerProvider).value?.confirmBeforeDelete ?? true);
  if (!confirmRequired) return true;

  final plural = (bulkCount ?? 1) > 1;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        plural
            ? AppStrings.collectionDeleteManyDialogTitle
            : AppStrings.collectionDeleteDialogTitle,
      ),
      content: Text(
        plural
            ? '$bulkCount ${AppStrings.collectionDeleteManyDialogMessage}'
            : AppStrings.collectionDeleteDialogMessage,
      ),
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
