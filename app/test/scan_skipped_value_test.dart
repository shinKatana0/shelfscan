/// The banners are decided by a value, not by a sentence (T-0145).
///
/// T-0140 split "could not be scanned" from "was not looked at" by matching
/// core's warning line -- `startsWith('Stopped before <name>:')` -- and putting
/// anything unrecognised in the failed list. That made the wording of one
/// sentence in `orchestrator.dart` load-bearing for the app, and made any OTHER
/// warning opening the same way able to move a photo between the two banners.
///
/// Rewording core's sentence from a test is not possible without editing core,
/// which the brief rules out; the equivalent and stronger proof is a decoy. The
/// fake provider writes a sentence of exactly the shape the old parse looked
/// for, about a photo it is wrong about. Under the parse it decided the banner;
/// under `ReviewDocument.failedPhotos` / `notLookedAtPhotos` it is ignored.
///
/// These drive the real [Orchestrator], so the values under test are the ones
/// core actually writes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeInputPicker;
import 'settings_store_test.dart' show RecordingStore;

/// Emits [decoy] into the screen's own warning list on its first call, then
/// behaves like a provider that fails [fails], holds [gates] and reads one row
/// off everything else. [empty] reads a photo and finds nothing on it.
class _DecoyVision implements VisionProvider {
  _DecoyVision({
    required this.decoy,
    required this.onNote,
    this.gates = const {},
    this.fails = const {},
    this.empty = const {},
  });

  final String decoy;
  final void Function(String note) onNote;
  final Map<String, Completer<void>> gates;
  final Set<String> fails;
  final Set<String> empty;
  final asked = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    if (asked.isEmpty) onNote(decoy);
    asked.add(photo.name);
    if (fails.contains(photo.name)) {
      throw Exception('Ollama 500: model runner has unexpectedly stopped');
    }
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        if (!empty.contains(photo.name))
          Detection(
            rawTitle: 'DUSKHOLLOW ${photo.name}',
            mediaType: MediaType.disc,
            confidence: 1.0,
            sourcePhoto: photo.name,
          ),
      ],
      unreadable: const [],
    );
  }
}

final _stopControl = find.byKey(const Key('scan-stop'));
final _failedBanner = find.byKey(const Key('failed-photos-banner'));
final _stoppedBanner = find.byKey(const Key('stopped-photos-banner'));

Finder _inBanner(Finder banner, String text) =>
    find.descendant(of: banner, matching: find.text(text));

String _decoyFor(String photo) =>
    'Stopped before $photo: it was not looked at.';

/// Local runs one photo at a time (ProviderPolicy.visionConcurrency), so the
/// photos are sent in order and exactly one is in flight when a stop lands.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<String> photos,
  required _DecoyVision Function(void Function(String) onNote) build,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      picker: FakeInputPicker(photos),
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProviderBuilder: build,
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
}

void main() {
  testWidgets('a decoy stop line does not move a failed photo', (tester) async {
    late _DecoyVision vision;
    final gate = Completer<void>();
    await _pumpScreen(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
      build: (onNote) => vision = _DecoyVision(
        // The photo this names really failed. The old parse read the sentence
        // first, so it called shelf1 "not looked at".
        decoy: _decoyFor('shelf1.jpg'),
        onNote: onNote,
        gates: {'shelf2.jpg': gate},
        fails: {'shelf1.jpg'},
      ),
    );
    // Pump first and count after: the pool reaches the first photo's own await
    // inside the tap, so `asked` grows before any frame exists to stop from.
    for (var i = 0; i < 50; i++) {
      await tester.pump();
      if (vision.asked.length >= 2) break;
    }
    expect(vision.asked.length, 2, reason: 'the stop has to land mid-run');
    await tester.tap(_stopControl);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resume-review-button')));
    await tester.pumpAndSettle();

    expect(vision.asked, ['shelf1.jpg', 'shelf2.jpg'],
        reason: 'shelf3.jpg was never sent');
    // The decoy is on screen as a warning; it just decides nothing.
    expect(
      _inBanner(_failedBanner, '1 of 3 photos could not be scanned'),
      findsOneWidget,
    );
    expect(_inBanner(_failedBanner, 'shelf1.jpg -- nothing from it is in '
        'this list.'), findsOneWidget);
    expect(
      _inBanner(_stoppedBanner, '1 of 3 photos was not looked at'),
      findsOneWidget,
    );
    expect(
      _inBanner(_stoppedBanner, 'The scan was stopped before shelf3.jpg -- '
          'nothing from it is in this list.'),
      findsOneWidget,
    );
    expect(_inBanner(_stoppedBanner, 'The scan was stopped before shelf1.jpg '
        '-- nothing from it is in this list.'), findsNothing);
  });

  testWidgets('a photo that was read and held nothing is in neither banner',
      (tester) async {
    // No stop and no failure at all: shelf1 was read and the model found
    // nothing on it, which is an answer (decision 0012) and not a loss. The old
    // parse saw an empty contribution plus a warning naming the photo and
    // banished it to the stopped banner.
    await _pumpScreen(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      build: (onNote) => _DecoyVision(
        decoy: _decoyFor('shelf1.jpg'),
        onNote: onNote,
        empty: {'shelf1.jpg'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DUSKHOLLOW shelf2.jpg'), findsOneWidget,
        reason: 'the review screen opened on a run that was not stopped');
    expect(_failedBanner, findsNothing);
    expect(_stoppedBanner, findsNothing);
    expect(find.textContaining('was not looked at'), findsNothing);
  });
}
