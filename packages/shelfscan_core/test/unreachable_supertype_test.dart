import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _refused = http.ClientException('Connection refused');

void main() {
  group('one question, three providers', () {
    test('every unreachable class answers it', () {
      final cases = <UnreachableEndpoint, ({String endpoint, bool userSet})>{
        OllamaUnreachableException('http://localhost:11434', 'x'): (
          endpoint: 'http://localhost:11434',
          userSet: true,
        ),
        VisionUnreachableException(_refused,
            service: 'Groq',
            endpoint: 'https://api.groq.com/openai/v1',
            endpointIsUserSet: true): (
          endpoint: 'https://api.groq.com/openai/v1',
          userSet: true,
        ),
        VisionUnreachableException(_refused,
            service: 'Anthropic',
            endpoint: 'https://api.anthropic.com/v1/messages',
            endpointIsUserSet: false): (
          endpoint: 'https://api.anthropic.com/v1/messages',
          userSet: false,
        ),
        IgdbUnreachableException(IgdbHost.twitch, _refused): (
          endpoint: IgdbHost.twitch.endpoint,
          userSet: false,
        ),
        IgdbUnreachableException(IgdbHost.igdb, _refused): (
          endpoint: IgdbHost.igdb.endpoint,
          userSet: false,
        ),
      };

      cases.forEach((error, expected) {
        expect(error.endpoint, expected.endpoint);
        expect(error.endpointIsUserSet, expected.userSet);
        expect(error.toString(), error.message,
            reason: 'the inherited toString is the message, as all three had');
      });
    });

    test('the timed-out forms are the same type, not a fourth', () {
      expect(
          OllamaUnreachableException.timedOut(
              'http://localhost:11434', const Duration(seconds: 120)),
          isA<UnreachableEndpoint>());
      expect(
          VisionUnreachableException.timedOut(
              service: 'Groq',
              endpoint: 'https://api.groq.com/openai/v1',
              endpointIsUserSet: true,
              waited: const Duration(seconds: 120)),
          isA<UnreachableEndpoint>());
    });

    // The defect T-0105 was filed for: a new provider's class added beside the
    // others, inheriting nothing, and falling silently to `false` in the app's
    // `_settingsCanFix`. IgdbTimeoutException is the one deliberate exclusion --
    // it is a stall on a stage that carries no address the user can set, and
    // T-0104 gave it its own class rather than one of these (see the report).
    test('a new unreachable class cannot skip the supertype', () {
      final offenders = <String>[];
      final declaration =
          RegExp(r'^class (\w*Unreachable\w*) (extends|implements) (\w+)', multiLine: true);
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final m in declaration.allMatches(file.readAsStringSync())) {
          if (m.group(3) != 'UnreachableEndpoint') {
            offenders.add('${file.path}: ${m.group(1)} ${m.group(2)} '
                '${m.group(3)}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'an unreachable class outside UnreachableEndpoint is the '
              'silent fall-through T-0105 removed');
    });
  });
}
