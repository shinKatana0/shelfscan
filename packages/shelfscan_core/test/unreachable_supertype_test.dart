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
        TmdbUnreachableException('Connection refused'): (
          endpoint: 'api.themoviedb.org',
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

  // The half of `UnreachableEndpoint.message` that is not a per-subclass
  // remedy: name the endpoint, and point outward at a check that runs without
  // this application (T-0354, extended to the other two families by T-0355).
  //
  // These strings live once per provider file rather than once in
  // `unreachable.dart`, because `igdb.dart` deliberately imports none of the
  // vision vocabulary and `tmdb.dart` imports neither. This group is what
  // stands in for the shared constant: three copies that must stay word for
  // word, checked here rather than trusted.
  group('the three families say the same thing about the outside', () {
    const browserCheck =
        'Open that address in a browser on this device: any answer at all, '
        'even an error page, means the host is reachable from here.';
    const outward = 'points outside this app rather than at the';
    const causes = 'usually this machine being offline, or a proxy or a '
        'firewall in the way.';

    // Invented hosts throughout, except the two vendors' own published
    // addresses already in the tree (`doc/conventions.md` 3b).
    final families = <String, UnreachableEndpoint>{
      'the vision endpoint the user typed': VisionUnreachableException(_refused,
          service: 'the endpoint',
          endpoint: 'https://vision.example.test/v1',
          endpointIsUserSet: true),
      'a vision address fixed in the build': VisionUnreachableException(
          _refused,
          service: 'Anthropic',
          endpoint: 'https://api.anthropic.com/v1/messages',
          endpointIsUserSet: false),
      'the IGDB search host': IgdbUnreachableException(IgdbHost.igdb, _refused),
      'the Twitch token host':
          IgdbUnreachableException(IgdbHost.twitch, _refused),
      'the TMDB search host': TmdbUnreachableException('Connection refused'),
    };

    families.forEach((name, error) {
      test('$name names its host and the check to run on it', () {
        expect(error.message, contains(error.endpoint));
        expect(error.message, contains(browserCheck));
        expect(error.message, contains(outward));
        expect(error.message, contains(causes));
      });

      test('$name no longer carries the tail T-0354 replaced', () {
        expect(error.message,
            isNot(contains('check whether this machine is online')));
        expect(error.message,
            isNot(contains('proxy or firewall is refusing the connection')));
      });

      test('$name asserts no cause of its own', () {
        for (final claim in const [
          'is refusing',
          'is blocked',
          'is offline',
          'is down',
          'is unreachable',
        ]) {
          expect(error.message, isNot(contains(claim)), reason: claim);
        }
      });
    });

    // The difference the type's own header names as the reason each subclass
    // owns its remedy. A build-fixed address must not borrow the vision
    // family's settable-URL half: there is nothing there for the reader to
    // correct, and offering one sends them looking.
    test('an address fixed in the build never claims it can be changed', () {
      final fixed = families.values.where((e) => !e.endpointIsUserSet);
      expect(fixed, hasLength(4));

      for (final error in fixed) {
        expect(error.message, contains('nothing to correct in your settings'));
        expect(error.message, isNot(contains('yours to set')));
        expect(error.message, isNot(contains('base URL')));
      }
    });

    test('only the user-set family offers the address as a thing to check', () {
      final userSet = families.values.where((e) => e.endpointIsUserSet).single;

      expect(userSet.message, contains('yours to set'));
    });
  });
}
