import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/app_settings.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';
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
Future<List<YgoCard>> addCardSearchResults(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final query = ref.watch(addCardQueryControllerProvider);
  if (query.isEmpty) return [];
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.searchByName(query);
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

  AddCardSelection _initial() => AddCardSelection(
    condition: _settings.defaultCondition,
    edition: _settings.defaultEdition,
    language: _settings.language,
  );

  @override
  AddCardSelection build() => _initial();

  /// Selects a card and fetches its printings. The printing step is skipped
  /// (straight to condition, `printing` left null) when none are found —
  /// consistent with existing null-printing collection entries.
  Future<void> selectCard(YgoCard card) async {
    state = AddCardSelection(
      card: card,
      step: AddCardStep.printing,
      condition: state.condition,
      edition: state.edition,
      language: state.language,
      quantity: state.quantity,
    );

    final repository = await ref.read(cardRepositoryProvider.future);
    final printings = await repository.getPrintingsForPasscode(
      card.passcode,
    );
    // The user may have navigated back to search and picked a different
    // card while this fetch was in flight — drop a stale response.
    if (state.card?.passcode != card.passcode) return;

    state = AddCardSelection(
      card: state.card,
      printings: printings,
      step: printings.isEmpty ? AddCardStep.condition : AddCardStep.printing,
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
