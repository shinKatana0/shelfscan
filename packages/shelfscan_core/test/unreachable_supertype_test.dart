import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _refused = http.ClientException('Connection refused');

void main() {
  group('one question, every provider', () {
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
  // this application (T-0354, T-0355, T-0357).
  //
  // Until T-0357 this group stood in for a shared constant: the sentence was
  // written out in three provider files, because `igdb.dart` deliberately
  // imports none of the vision vocabulary and `tmdb.dart` imports neither, and
  // this was the only thing holding the copies word for word.
  // `unreachable.dart` composes it once now, so what the group guards has
  // changed rather than gone. The sentence is still spelled out HERE, in a
  // file that imports none of it, so a reword of the shared clause fails these
  // tests and has to be meant. What is new is that the two parts supplied per
  // family -- the stage, and what a browser refusal usually is -- are pinned
  // per family, which three copies of one string could not check at all.
  group('the four families say the same thing about the outside', () {
    const browserCheck =
        'Open that address in a browser on this device: any answer at all, '
        'even an error page, means the host is reachable from here.';
    const atTheScan =
        'A browser refused the same way points outside this app rather than '
        'at the scan';
    const atTheLookup =
        'A browser refused the same way points outside this app rather than '
        'at the lookup';
    // Where the host is decides this half, and it is the half T-0357 refused
    // to carry across: a machine that cannot reach its own port is not offline
    // and rarely has a proxy in the way.
    const outOnTheInternet = ' -- usually this machine being offline, or a '
        'proxy or a firewall in the way.';
    const atALocalAddress = ' -- usually nothing listening on that port, or, '
        'for an address on another machine, a firewall or a server there that '
        'only listens to itself.';

    // Invented hosts throughout, except the two vendors' own published
    // addresses already in the tree and Ollama's own documented default
    // (`doc/conventions.md` 3b).
    final families = <String, ({UnreachableEndpoint error, String outward})>{
      'the vision endpoint the user typed': (
        error: VisionUnreachableException(_refused,
            service: 'the endpoint',
            endpoint: 'https://vision.example.test/v1',
            endpointIsUserSet: true),
        outward: '$atTheScan$outOnTheInternet',
      ),
      'a vision address fixed in the build': (
        error: VisionUnreachableException(_refused,
            service: 'Anthropic',
            endpoint: 'https://api.anthropic.com/v1/messages',
            endpointIsUserSet: false),
        outward: '$atTheScan$outOnTheInternet',
      ),
      'the IGDB search host': (
        error: IgdbUnreachableException(IgdbHost.igdb, _refused),
        outward: '$atTheLookup$outOnTheInternet',
      ),
      'the Twitch token host': (
        error: IgdbUnreachableException(IgdbHost.twitch, _refused),
        outward: '$atTheLookup$outOnTheInternet',
      ),
      'the TMDB search host': (
        error: TmdbUnreachableException('Connection refused'),
        outward: '$atTheLookup$outOnTheInternet',
      ),
      'the local Ollama server': (
        error: OllamaUnreachableException(
            'http://localhost:11434', 'Connection refused'),
        outward: '$atTheScan$atALocalAddress',
      ),
    };

    families.forEach((name, family) {
      test('$name names its host and the check to run on it', () {
        expect(family.error.message, contains(family.error.endpoint));
        expect(family.error.message, contains(browserCheck));
      });

      // The stage and the causes are arguments now, so a family handed the
      // wrong one reads as one voice and says something false. That is the
      // failure this pins and the three-copy version could not.
      test('$name points outward in the words its own stage earns', () {
        expect(family.error.message, contains(family.outward));
      });

      test('$name no longer carries the tail T-0354 replaced', () {
        expect(family.error.message,
            isNot(contains('check whether this machine is online')));
        expect(family.error.message,
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
          expect(family.error.message, isNot(contains(claim)), reason: claim);
        }
      });
    });

    // The difference the type's own header names as the reason each subclass
    // owns its remedy. A build-fixed address must not borrow the vision
    // family's settable-URL half: there is nothing there for the reader to
    // correct, and offering one sends them looking.
    test('an address fixed in the build never claims it can be changed', () {
      final fixed =
          families.values.where((f) => !f.error.endpointIsUserSet).toList();
      expect(fixed, hasLength(4));

      for (final family in fixed) {
        expect(family.error.message,
            contains('nothing to correct in your settings'));
        expect(family.error.message, isNot(contains('yours to set')));
        expect(family.error.message, isNot(contains('base URL')));
      }
    });

    // The complement, so the negatives above cannot be satisfied by deleting
    // the settable half everywhere. Each user-set family names its own address
    // as a thing to check in its own words -- vision as a Settings field, the
    // local server as an address that may be another machine.
    test('a user-set address is never told there is nothing to correct', () {
      final userSet =
          families.values.where((f) => f.error.endpointIsUserSet).toList();
      expect(userSet, hasLength(2));

      for (final family in userSet) {
        expect(family.error.message,
            isNot(contains('nothing to correct in your settings')));
      }

      expect(families['the vision endpoint the user typed']!.error.message,
          contains('yours to set'));
      expect(families['the local Ollama server']!.error.message,
          contains('check it is right and reachable from here'));
    });
  });
}
