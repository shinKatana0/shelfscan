import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';

import 'tonkatsu_v45_sample.dart' as sample;

void main(List<String> args) {
  if (args.length != 1 || (args.single != 'true' && args.single != 'false')) {
    throw ArgumentError('Expected one boolean argument');
  }
  final expected = args.single == 'true';
  final exporter = exporters['tonkatsu-cards']!() as TonkatsuCardsExporter;
  if (tonkatsuV45Export != expected || exporter.v45Export != expected) {
    throw StateError('Feature flag and registry disagree with $expected');
  }

  final cards = jsonDecode(exporter.export(sample.tonkatsuV45SampleDocument()))
      as List<dynamic>;
  if (cards.length != (expected ? 5 : 2)) {
    throw StateError('Unexpected card selection for $expected');
  }
  print('tonkatsuV45Export=$tonkatsuV45Export cards=${cards.length}');
}
