import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/shared/widgets/card_thumbnail.dart';

void main() {
  testWidgets('renders a placeholder when localImagePath is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CardThumbnail(localImagePath: null)),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  // Real file I/O and `Image.file`'s real codec both need a real event loop:
  // done in the fake-async test body they hang the test at teardown. Wrap in
  // runAsync and advance with real-delay pumps. See
  // `.claude/skills/flutter-test-troubleshooting.md`.
  testWidgets('renders Image.file for a real local file', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('card_thumbnail_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/card.jpg');
      // A minimal valid JPEG isn't needed — Image.file only needs the file to
      // exist for this widget to attempt decoding; a decode error still
      // renders (errorBuilder only triggers if desired, but the presence of
      // an Image widget is what's under test here).
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

      await tester.pumpWidget(
        MaterialApp(home: CardThumbnail(localImagePath: file.path)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });
  });

  testWidgets(
    'falls back to the placeholder when the file path is missing',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CardThumbnail(localImagePath: '/nonexistent/path.jpg'),
          ),
        );
        // Let Image.file's real file-read fail so errorBuilder swaps in the
        // placeholder.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }

        expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      });
    },
  );
}
