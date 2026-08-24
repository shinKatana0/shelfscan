/// Guards the two halves of T-0004: the alias table as injected data, and
/// IGDB `alternative_names` as the upstream source for the same problem.
///
/// The problem both attack: a regional title is not the canonical IGDB name,
/// so a shelf that is partly Japanese produces titles IGDB has never heard of
/// under that spelling. What is pinned here:
///   1. the table is *injected*, so growing it needs no Dart edit and no
///      `dart:io` inside `shelfscan_core` (ARCHITECTURE.md platform boundary);
///   2. a bad data file costs aliases, never the run;
///   3. an alternative name can win the match, and says so on the candidate.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart' show aliasFileName, findAliasFile, loadTitleAliases;

/// Canned IGDB responses, keyed by the search text the resolver sends.
///
/// `alternative_names` is an expanded sub-field, so IGDB returns it as a list
/// of objects and omits the key entirely for a game that has none.
const _igdbGames = <String, String>{
  'resident evil re:4': '''
[{"id": 1100000056, "name": "Resident Evil 4",
  "alternative_names": [{"name": "Biohazard RE:4"}, {"name": "BIO HAZARD RE:4"}],
  "platforms": [{"id": 167, "name": "PlayStation 5"}]}]''',
  'crown of tidefall': '''
[{"id": 1100000048, "name": "Crown of Tidefall",
  "platforms": [{"id": 167, "name": "PlayStation 5"}]}]''',
};

/// The same response set with every alternative name stripped -- the control
/// for "the alternative names are what produced the match".
String _withoutAlternativeNames(String body) {
  final games = (jsonDecode(body) as List<dynamic>)
      .map((g) => Map<String, dynamic>.from(g as Map<String, dynamic>)
        ..remove('alternative_names'))
      .toList();
  return jsonEncode(games);
}

({IgdbClient client, List<String> bodies}) _stubIgdb(
    {bool alternativeNames = true}) {
  final bodies = <String>[];
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    bodies.add(request.body);
    final query =
        RegExp(r'search "([^"]*)"').firstMatch(request.body)?.group(1) ?? '';
    final body = _igdbGames[query] ?? '[]';
    return http.Response(
        alternativeNames ? body : _withoutAlternativeNames(body), 200);
  });
  return (
    client:
        IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport),
    bodies: bodies,
  );
}

Detection _detection(String rawTitle, {String? hint}) => Detection(
      rawTitle: rawTitle,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: 'shelf_a.jpg',
      platformHint: hint,
    );

void main() {
  group('parseTitleAliases', () {
    test('reads a flat object', () {
      expect(parseTitleAliases('{"biohazard": "resident evil"}'),
          {'biohazard': 'resident evil'});
    });

    test('lower-cases both sides, so the file may be written as printed', () {
      // The resolver matches on a lower-cased title; a file spelled the way a
      // spine reads must not silently stop matching because of that.
      expect(parseTitleAliases('{"BIO HAZARD": "Resident Evil"}'),
          {'bio hazard': 'resident evil'});
    });

    test('rejects anything that is not a string-to-string object', () {
      for (final bad in [
        '[]',
        '"biohazard"',
        '{"biohazard": 4}',
        '{"biohazard": null}',
        '{"": "resident evil"}',
        '{"biohazard": "  "}',
      ]) {
        expect(() => parseTitleAliases(bad), throwsFormatException,
            reason: bad);
      }
      expect(() => parseTitleAliases('not json'), throwsFormatException);
    });
  });

  group('the table is injected, not compiled in', () {
    Future<String> queryFor(String rawTitle,
        {Map<String, String>? aliases}) async {
      final igdb = _stubIgdb();
      await ResolverWorker(igdb.client, aliases: aliases)
          .process(_detection(rawTitle));
      // First and not only: the stub answers with zero rows, which since
      // T-0065 is followed by shortened retries.
      return RegExp(r'search "([^"]*)"').firstMatch(igdb.bodies.first)!.group(1)!;
    }

    test('an alias the source has never heard of still rewrites the query',
        () async {
      expect(
        await queryFor('Yozakura Kaimei 4',
            aliases: {'yozakura kaimei': 'vermeil harker ace advocate'}),
        'vermeil harker ace advocate 4',
      );
    });

    test('an injected table replaces the built-in one entirely', () async {
      // Otherwise a data file could only ever add, and an alias measured to
      // be harmful could not be taken back out without a code change.
      expect(await queryFor('Biohazard 4', aliases: const {}), 'biohazard 4');
    });

    test('no table injected -> the built-in fallback', () async {
      expect(await queryFor('Biohazard 4'), 'resident evil 4');
    });
  });

  group('the CLI loads the data file', () {
    late Directory temp;
    late List<String> warnings;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('shelfscan_aliases');
      warnings = [];
    });
    tearDown(() => temp.deleteSync(recursive: true));

    File aliasFile(String contents) {
      final file = File('${temp.path}/aliases.json')
        ..writeAsStringSync(contents);
      return file;
    }

    Map<String, String> load(String? path) =>
        loadTitleAliases(path, onWarning: warnings.add);

    test('a valid file wins over the built-in table', () {
      final file = aliasFile('{"yozakura kaimei": "vermeil harker"}');

      expect(load(file.path), {'yozakura kaimei': 'vermeil harker'});
      expect(warnings, isEmpty);
    });

    test('a missing file warns and falls back', () {
      expect(load('${temp.path}/nope.json'), builtinTitleAliases);
      expect(warnings.single, contains('nope.json'));
    });

    test('a malformed file warns and falls back, it does not throw', () {
      // The realistic failure: a human hand-edits the table and leaves a
      // trailing comma. Losing the aliases costs match rate on regional
      // titles; losing the run costs the whole scan.
      final file = aliasFile('{"biohazard": "resident evil",}');

      expect(load(file.path), builtinTitleAliases);
      expect(warnings.single, contains(file.path));
    });

    test('the committed data file parses', () {
      // The file the CLI and the app both ship; a typo in it would otherwise
      // only surface as a silent fallback at runtime.
      final file = findAliasFile(Directory.current);
      expect(file, isNotNull, reason: 'expected $aliasFileName above cwd');
      expect(parseTitleAliases(file!.readAsStringSync()), isNotEmpty);
    });

    test('the default lookup walks up to the repository root', () {
      // The CLI is run from the repository root and from
      // packages/shelfscan_core; one fixed relative path serves only one.
      final nested = Directory('${temp.path}/a/b')..createSync(recursive: true);
      final planted = File('${temp.path}/$aliasFileName');
      planted.parent.createSync(recursive: true);
      planted.writeAsStringSync('{"rockman": "mega man"}');

      expect(findAliasFile(nested)?.readAsStringSync(),
          '{"rockman": "mega man"}');
    });
  });

  group('IGDB alternative names', () {
    test('the search asks for them', () async {
      final igdb = _stubIgdb();
      await igdb.client.search('crown of tidefall');
      expect(igdb.bodies.single, contains('alternative_names.name'));
    });

    test('a game without any is carried as an empty list, not a crash',
        () async {
      final hits = await _stubIgdb().client.search('crown of tidefall');
      expect(hits.single.alternativeNames, isEmpty);
    });

    test('a regional raw title auto-matches the canonical game', () async {
      final igdb = _stubIgdb();

      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('Biohazard RE:4', hint: 'PS5'));

      final best = resolved.best;
      expect(best, isNotNull);
      // Canonical, because that is what gets exported and what the target app
      // shows -- the alternative name only explains the match.
      expect(best!.title, 'Resident Evil 4');
      expect(best.externalId, 'igdb:1100000056');
      expect(best.matchedAlternativeName, 'Biohazard RE:4');
      expect(best.score, 1.0);
    });

    test('and it is the alternative names that did it', () async {
      // Same detection, same alias rewrite, same hit -- only the alternative
      // names removed. The canonical name alone scores 0.83 against
      // "resident evil re:4", below the 0.85 auto-match threshold: found, but
      // left for the human.
      final igdb = _stubIgdb(alternativeNames: false);

      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('Biohazard RE:4', hint: 'PS5'));

      expect(resolved.best, isNull);
      expect(resolved.candidates.single.score, lessThan(minAutoScore));
      expect(resolved.candidates.single.matchedAlternativeName, isNull);
    });

    test('a canonical match records no alternative name', () async {
      final resolved = await ResolverWorker(_stubIgdb().client)
          .process(_detection('Crown of Tidefall', hint: 'PS5'));

      expect(resolved.best?.score, 1.0);
      expect(resolved.best?.matchedAlternativeName, isNull);
    });
  });

  group('review.json compatibility', () {
    test('a candidate written before this field existed still parses', () {
      final candidate = Candidate.fromJson({
        'igdb_id': 1100000048,
        'title': 'Crown of Tidefall',
        'platform_id': 167,
        'platform_name': 'PlayStation 5',
        'score': 1.0,
      });

      expect(candidate.matchedAlternativeName, isNull);
    });

    test('and one written with it round-trips', () {
      final candidate = Candidate(
        externalId: 'igdb:1100000056',
        title: 'Resident Evil 4',
        platformId: 167,
        platformName: 'PlayStation 5',
        score: 1.0,
        matchedAlternativeName: 'Biohazard RE:4',
      );

      expect(Candidate.fromJson(candidate.toJson()).matchedAlternativeName,
          'Biohazard RE:4');
    });
  });
}
