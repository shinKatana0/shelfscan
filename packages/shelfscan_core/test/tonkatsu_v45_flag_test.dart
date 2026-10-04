import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final variant in <(String, List<String>, bool)>[
    ('default', const [], true),
    ('explicit false', const ['-DtonkatsuV45Export=false'], false),
    ('explicit true', const ['-DtonkatsuV45Export=true'], true),
  ]) {
    test('${variant.$1} selects the expected registry exporter', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        ...variant.$2,
        'run',
        'tool/tonkatsu_v45_flag_probe.dart',
        '${variant.$3}',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout,
          contains('tonkatsuV45Export=${variant.$3} cards='));
    });
  }
}
