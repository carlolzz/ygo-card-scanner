import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/app_settings.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_search_hit.dart';
import '../../models/collection_entry.dart';
import '../../models/fast_log_field.dart';
import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../collection/collection_providers.dart';
import '../settings/settings_providers.dart';

part 'add_card_providers.g.dart';

enum AddCardStep { search, printing, condition }

class AddCardSelection {
  const AddCardSelection({
    this.card,
    this.printings = const [],
    this.printing,
    this.step = AddCardStep.search,
    this.condition = CardCondition.nearMint,
    this.edition = CardEdition.unlimited,
    this.language = 'EN',
    this.quantity = 1,
  });

  final YgoCard? card;
  final List<Printing> printings;
  final Printing? printing;
  final AddCardStep step;
  final CardCondition condition;
  final CardEdition edition;
  final String language;
  final int quantity;
}

@riverpod
class AddCardQueryController extends _$AddCardQueryController {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

@riverpod
Future<List<CardSearchHit>> addCardSearchResults(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final query = ref.watch(addCardQueryControllerProvider);
  if (query.isEmpty) return [];
  // `watch`: the language is part of the query, unlike the defaults this
  // wizard's selection controller reads once at build.
  final language = ref.watch(searchLanguageProvider);
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.search(query, language: language);
}

@riverpod
class AddCardSelectionController extends _$AddCardSelectionController {
  /// The user's configured defaults, read once when this controller is built.
  ///
  /// `ref.read`, not `watch`: changing a default mid-wizard must not reset the
  /// card the user is part-way through logging. The new value takes effect the
  /// next time the screen is opened (this controller is autoDispose). The
  /// `?? const AppSettings()` fallback is for widget tests that pump this
  /// screen without a resolved settings load — `App` gates on it in production.
  late final AppSettings _settings =
      ref.read(settingsControllerProvider).value ?? const AppSettings();

  /// Which per-card details the wizard should still show a control for, and
  /// whether Fast log is suppressing anything at all.
  ///
  /// Passthroughs of the rule on [AppSettings], shared verbatim with the scan
  /// review gate so a card logged either way is asked the same questions. They
  /// read the same [_settings] snapshot [_initial] seeds from, which is why
  /// they live here rather than being watched in the widget.
  Set<FastLogField> get askedFields => _settings.fastLogAskedFields;
  bool get fastLogActive => _settings.fastLogActive;

  AddCardSelection _initial() => AddCardSelection(
    condition: _settings.defaultCondition,
    edition: _settings.defaultEdition,
    language: _settings.language,
  );

  @override
  AddCardSelection build() => _initial();

  /// Selects a card and fetches its printings, then goes to the printing step —
  /// unless there is no choice to make there:
  ///
  /// - **no printings**: straight to condition with `printing` left null,
  ///   consistent with existing null-printing collection entries;
  /// - **exactly one**: straight to condition with that printing already
  ///   picked. A step offering a single option is a decision with one answer,
  ///   and the alternative (leaving it to the Skip button) silently logs a card
  ///   with no set when there was only one it could have come from. The choice
  ///   stays visible and reversible: `_ConditionStep` prints the set under the
  ///   card name, and the back button routes to the printing step whenever
  ///   `printings` is non-empty.
  ///
  /// Under Fast log the printing step is skipped in **every** case, including
  /// several printings, where the card is logged without one. The auto-pick is
  /// then still visible (that same set line) but no longer reversible in place,
  /// since the back button cannot route to a step that is not offered; it stays
  /// correctable from the collection detail screen's edit sheet.
  Future<void> selectCard(YgoCard card) async {
    state = AddCardSelection(
      card: card,
      // Stay on the search list for the round trip rather than jumping to the
      // condition step, which under Fast log is where this would otherwise
      // land. That step carries a live Save button, and showing it before
      // `preferredPrinting` has been applied is a real race on a cold sqflite
      // isolate: Fast log is precisely the mode that encourages tapping a
      // result and then Save immediately, and losing it logs `printingId` null.
      step: fastLogActive ? AddCardStep.search : AddCardStep.printing,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );

    final repository = await ref.read(cardRepositoryProvider.future);
    final printings = await repository.getPrintingsForPasscode(card.passcode);
    // The user may have navigated back to search and picked a different
    // card while this fetch was in flight — drop a stale response.
    if (state.card?.passcode != card.passcode) return;

    // Shared with the scan review gate, so a card logged either way lands on the
    // same set. Skipping straight to the condition step is safe because the step
    // stays reachable: `AddCardScreen`'s back button routes to `backToPrinting`
    // whenever `printings` is non-empty, and `_ConditionStep` prints the chosen
    // set under the card name — so the pick is both visible and reversible.
    final preferred = preferredPrinting(printings);
    state = AddCardSelection(
      card: state.card,
      printings: printings,
      printing: preferred,
      step: fastLogActive || printings.isEmpty || preferred != null
          ? AddCardStep.condition
          : AddCardStep.printing,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  void selectPrinting(Printing printing) {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: printing,
      step: AddCardStep.condition,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  void skipPrinting() {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      step: AddCardStep.condition,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  void setCondition(CardCondition condition) {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: state.printing,
      step: state.step,
      condition: condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  void setEdition(CardEdition edition) {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: state.printing,
      step: state.step,
      condition: state.condition,
      edition: edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  void setLanguage(String language) {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: state.printing,
      step: state.step,
      condition: state.condition,
      edition: state.edition,
      language: language,
      quantity: state.quantity,
    );
  }

  void setQuantity(int quantity) {
    if (quantity < 1) return;
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: state.printing,
      step: state.step,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: quantity,
    );
  }

  void backToSearch() {
    state = _initial();
  }

  void backToPrinting() {
    state = AddCardSelection(
      card: state.card,
      printings: state.printings,
      printing: state.printing,
      step: AddCardStep.printing,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );
  }

  Future<void> save() async {
    final card = state.card;
    if (card == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.addOrIncrement(
      CollectionEntry(
        passcode: card.passcode,
        printingId: state.printing?.id,
        condition: state.condition,
        edition: state.edition,
        language: state.language,
        quantity: state.quantity,
        createdAt: now,
        updatedAt: now,
      ),
    );
    ref.invalidate(collectionEntriesProvider);
    // A card logged against a printing can introduce a rarity the collection
    // did not hold before, which the collection filter row offers as a chip.
    ref.invalidate(collectionFilterOptionsProvider);
    // Back to search for the next card — with the defaults restored, not the
    // grade the user happened to pick for the card they just saved.
    state = _initial();
  }
}
