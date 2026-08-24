/// The order the three vision backends are offered in (T-0343).
///
/// Local, then the OpenAI-compatible endpoint the user names, then Anthropic.
/// That is the owner's judgement about who uses this rather than a technical
/// ordering, so nothing in the code can be read back to derive it -- which is
/// the whole reason it is pinned here. Four surfaces have to agree: the enum
/// declaration, [ProviderPolicy.available], the settings sections and the scan
/// screen's toolbar switch.
///
/// The last test is the one that makes reordering safe at all: the stored
/// preference is the enum's NAME. Were it the index, the same edit would move
/// every user who had chosen Anthropic onto an endpoint they never named.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/settings_screen.dart';
import 'package:shelfscan_app/settings_store.dart';

import 'settings_store_test.dart' show RecordingStore;

const _order = [
  VisionBackend.local,
  VisionBackend.openAiCompatible,
  VisionBackend.cloud,
];

const _localSection = 'Local (Ollama)';
const _endpointSection = 'Endpoint (any OpenAI-compatible service)';
const _cloudSection = 'Cloud (Anthropic)';

SettingsStore _store() =>
    SettingsStore(secrets: RecordingStore(), prefs: RecordingStore());

void main() {
  tearDown(() => ProviderPolicy.debugLocalServerIsThisMachineOverride = null);

  test('the enum declares the order the user meets them in', () {
    expect(VisionBackend.values, _order);
  });

  test('the policy offers all three in that order, on both platforms', () {
    // Unconditional since T-0361: the phone offers local too, pointed at a
    // server on the network rather than at itself. Still asked of both
    // platforms, because the list stating the same thing twice is what this
    // test is for, and a platform filter returning here would be caught.
    for (final onThisMachine in [true, false]) {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
      expect(ProviderPolicy.available, _order,
          reason: 'onThisMachine=$onThisMachine');
    }
  });

  testWidgets('the settings sections are in that order', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(settings: ProviderSettings(), store: _store()),
    ));

    // Vertical position rather than tree order: the form is one scroll view,
    // every section is laid out whether or not it is on screen, and "above"
    // is what the reader actually experiences.
    double top(String section) => tester.getTopLeft(find.text(section)).dy;

    expect(top(_localSection), lessThan(top(_endpointSection)));
    expect(top(_endpointSection), lessThan(top(_cloudSection)));
  });

  test("the scan screen's switch takes its order from the policy", () {
    // Flattened, so a rewrap of the loop head does not fail this (T-0324).
    final source = File('lib/screens/scan_screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
      source,
      contains('for (final backend in ProviderPolicy.available)'),
      reason: 'the toolbar segments must be the policy list in order; a '
          'hand-written one is a second authority on it',
    );
  });

  test('the stored preference is the name, never the index', () async {
    for (final backend in VisionBackend.values) {
      final prefs = RecordingStore();
      await SettingsStore(secrets: RecordingStore(), prefs: prefs)
          .save(ProviderSettings(backend: backend));
      expect(prefs.values[SettingsStore.keyBackend], backend.name);
    }
  });

  test('a preference stored before the reorder still names the same provider',
      () async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    // The three strings a build shipped before this order existed wrote.
    const stored = {
      'local': VisionBackend.local,
      'cloud': VisionBackend.cloud,
      'openAiCompatible': VisionBackend.openAiCompatible,
    };
    for (final entry in stored.entries) {
      final prefs = RecordingStore()
        ..values[SettingsStore.keyBackend] = entry.key;
      final loaded =
          await SettingsStore(secrets: RecordingStore(), prefs: prefs).load();
      expect(loaded.backend, entry.value, reason: entry.key);
    }
  });
}
