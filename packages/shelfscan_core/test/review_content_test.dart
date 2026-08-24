/// Guards `resolve` and `export` against presenting a hand-broken
/// `review.json` as a crash (T-0050).
///
/// T-0049 stopped at the path; a file that exists and holds something other
/// than a review document still died with an unhandled `FormatException` (not
/// JSON) or `TypeError` (JSON of the wrong shape) plus a Dart frame trace.
/// Manual add is a documented workflow, so both are inputs a user produces by
/// editing their own file, and the claims are T-0037's two halves again:
///   1. the wording, and that it distinguishes "not JSON" from "JSON of the
///      wrong shape" -- one is found with a line number, the other with a
///      field name;
///   2. the process really exits 2 and prints no Dart frames.
///
/// No subprocess here reaches a network: the IGDB variables are blanked, and
/// with T-0050 `resolve` reads the file before it builds anything, so every
/// broken-file case stops before an IGDB client or a vision provider exists.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show jsonErrorLocation, reviewParseError, reviewShapeError;
import 'cli_snapshot.dart';

/// The smallest document `scan` can write: one approved, resolved game.
Map<String, dynamic> _reviewFixture() => {
      'version': 1,
      'created': '2026-08-14T09:00:00.000000Z',
      'photos': ['shelf_b.jpg'],
      'games': [
        {
          'detection': {
            'raw_title': 'CROWN OF TIDEFALL',
            'platform_hint': 'PS5',
            'media_type': 'disc',
            'confidence': 1.0,
            'source_photo': 'shelf_b.jpg',
          },
          'best': {
            'igdb_id': 1100000048,
            'title': 'Crown of Tidefall',
            'platform_id': 167,
            'platform_name': 'PlayStation 5',
            'score': 1.0,
          },
          'candidates': const <Object>[],
          'status': 'approved',
        },
      ],
    };

/// The manual-add block exactly as the CLI usage text documents it: a title
/// and nothing else required.
const _handWrittenEntry = {
  'detection': {
    'raw_title': 'Nocturne 5 Gold',
    'platform_hint': 'PS4',
    'media_type': 'disc',
    'origin': 'manual',
  },
};

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('shelfscan_review_content_');
  // Same Windows errno 145 race the other two path suites document.
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });
  return dir;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// [contents] written to a review file in a fresh temp directory.
({String file, String dir}) _reviewFileHolding(String contents) {
  final dir = _tempDir();
  final file = _join(dir.path, 'collection.review.json');
  File(file).writeAsStringSync(contents);
  return (file: file, dir: dir.path);
}

ProcessResult _runCli(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      // Blanked so a machine that has IGDB credentials cannot turn any case
      // here into a live API call.
      environment: const {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

List<String> _lines(Object? stderrText) =>
    const LineSplitter().convert(stderrText as String);

/// The [ReviewFormatException] [source] produces, or a failure if it parses.
ReviewFormatException _shapeErrorOf(Object? source) {
  try {
    ReviewDocument.parse(source is String ? source : jsonEncode(source));
  } on ReviewFormatException catch (e) {
    return e;
  }
  fail('expected a ReviewFormatException, got a document');
}

void main() {
  setUpAll(cliSnapshot);

  group('ReviewDocument.parse', () {
    test('unparseable text is a FormatException, not a shape error', () {
      expect(() => ReviewDocument.parse('not json at all'),
          throwsA(isA<FormatException>()));
      expect(() => ReviewDocument.parse('not json at all'),
          isNot(throwsA(isA<ReviewFormatException>())));
    });

    test('a valid document round-trips', () {
      final doc = ReviewDocument.parse(jsonEncode(_reviewFixture()));
      expect(doc.version, 1);
      expect(doc.games, hasLength(1));
      expect(doc.games.single.best?.externalId, 'igdb:1100000048');
    });

    test('a hand-added entry with only a title parses', () {
      final json = _reviewFixture();
      (json['games'] as List<Object?>).add(_handWrittenEntry);
      final doc = ReviewDocument.parse(jsonEncode(json));
      expect(doc.games, hasLength(2));
      final manual = doc.games.last.detection;
      expect(manual.rawTitle, 'Nocturne 5 Gold');
      expect(manual.isManual, isTrue);
      expect(manual.sourcePhoto, isEmpty);
      expect(doc.games.last.candidates, isEmpty);
    });

    test('a titleless row still heals into unreadable (T-0035)', () {
      final json = _reviewFixture();
      (json['games'] as List<Object?>).add({
        'detection': {'raw_title': '   ', 'source_photo': 'shelf_b.jpg'},
      });
      final doc = ReviewDocument.parse(jsonEncode(json));
      // Healed, not rejected: the row is dropped from games and the fact that
      // something was there survives in unreadable.
      expect(doc.games, hasLength(1));
      expect(doc.unreadable, hasLength(1));
      expect(doc.unreadable.single.sourcePhoto, 'shelf_b.jpg');
      expect(doc.unreadable.single.reason, contains('empty title'));
    });

    test('each wrong shape names the field and what it should be', () {
      final cases = <String, ({Object? document, String path, String must})>{
        'the whole file is a list': (
          document: [1, 2, 3],
          path: '',
          must: 'the top level of the file is a list',
        ),
        'version is missing': (
          document: _reviewFixture()..remove('version'),
          path: 'version',
          must: 'is missing',
        ),
        'version is text': (
          document: _reviewFixture()..['version'] = '1',
          path: 'version',
          must: 'is a string',
        ),
        'created is missing': (
          document: _reviewFixture()..remove('created'),
          path: 'created',
          must: 'is missing',
        ),
        'photos is not a list': (
          document: _reviewFixture()..['photos'] = 'shelf_b.jpg',
          path: 'photos',
          must: 'is a string',
        ),
        'a photo name is a number': (
          document: _reviewFixture()..['photos'] = [7],
          path: 'photos[0]',
          must: 'a photo file name',
        ),
        'games is missing': (
          document: _reviewFixture()..remove('games'),
          path: 'games',
          must: 'a list of game entries',
        ),
        'games is an object': (
          document: _reviewFixture()..['games'] = <String, Object?>{},
          path: 'games',
          must: 'is an object',
        ),
        'a game entry is a string': (
          document: _reviewFixture()..['games'] = ['Crown of Tidefall'],
          path: 'games[0]',
          must: 'an object with a "detection"',
        ),
        'a game entry has no detection': (
          document: _reviewFixture()..['games'] = [<String, Object?>{}],
          path: 'games[0].detection',
          must: 'an object with a "raw_title"',
        ),
        'a candidate is missing its id': (
          document: _reviewFixture()
            ..['games'] = [
              {
                'detection': {'raw_title': 'A'},
                'candidates': [
                  {
                    'title': 'A',
                    'platform_id': 1,
                    'platform_name': 'x',
                    'score': 1.0
                  },
                ],
              },
            ],
          path: 'games[0].candidates[0].external_id',
          must: "a catalogue's id for this entry, as catalogue:id",
        ),
        'confidence is text': (
          document: _reviewFixture()
            ..['games'] = [
              {
                'detection': {'raw_title': 'A', 'confidence': 'high'},
              },
            ],
          path: 'games[0].detection.confidence',
          must: 'a number between 0 and 1',
        ),
        'unreadable is not a list': (
          document: _reviewFixture()..['unreadable'] = 3,
          path: 'unreadable',
          must: 'a list of unread-spine reports',
        ),
      };

      cases.forEach((name, expected) {
        final error = _shapeErrorOf(expected.document);
        expect(error.path, expected.path, reason: name);
        expect(error.toString(), contains(expected.must), reason: name);
        // The whole point of the type: every message says what belongs
        // there, never only that something is invalid.
        expect(
            error.toString(),
            contains(
                expected.path.isEmpty ? 'a review document is' : 'it must be '),
            reason: name);
      });
    });

    test('the first problem in document order is the one reported', () {
      final broken = _reviewFixture()
        ..remove('version')
        ..remove('games');
      expect(_shapeErrorOf(broken).path, 'version');
    });

    test('optional fields absent are still not a shape error', () {
      final minimal = {
        'version': 1,
        'created': '2026-08-14T09:00:00.000000Z',
        'photos': <String>[],
        'games': [_handWrittenEntry],
      };
      expect(ReviewDocument.parse(jsonEncode(minimal)).games, hasLength(1));
    });
  });

  group('the messages', () {
    test('the parse error names the absolute path and the line', () {
      final broken = _reviewFileHolding('{\n  "version": 1,\n  oops\n}');
      final error = () {
        try {
          ReviewDocument.parse(File(broken.file).readAsStringSync());
        } on FormatException catch (e) {
          return e;
        }
        fail('expected a FormatException');
      }();
      final message = reviewParseError(broken.file, error);
      expect(message, startsWith('Not a review file: ${broken.file}'));
      expect(message, contains('is not JSON'));
      expect(message, contains('at line 3, column 3'));
      expect(message, isNot(contains('\n')));
    });

    test('a relative path is answered with where it actually pointed', () {
      final message = reviewParseError(
          'sub/../broken.review.json', const FormatException('nope'));
      expect(message, isNot(contains('..')));
      expect(message,
          contains(_join(Directory.current.path, 'broken.review.json')));
    });

    test('a FormatException with no position drops the location clause', () {
      expect(jsonErrorLocation(const FormatException('nope')), isEmpty);
      expect(reviewParseError('x.json', const FormatException('nope')),
          contains('is not JSON -- nope. '));
    });

    test('the shape error is worded as a different problem', () {
      final shape = reviewShapeError(
          'x.json', _shapeErrorOf(_reviewFixture()..remove('games')));
      final parse = reviewParseError('x.json', const FormatException('nope'));
      expect(shape, contains('is JSON but not a review document'));
      expect(shape, contains('games is missing'));
      expect(parse, contains('is not JSON'));
      expect(shape, isNot(contains('is not JSON')));
      expect(shape, isNot(contains('\n')));
    });
  });

  group('the CLI process', () {
    test('has bin/shelfscan.dart under the working directory', () {
      expect(File('bin/shelfscan.dart').existsSync(), isTrue,
          reason: 'run `dart test` from packages/shelfscan_core');
    });

    /// The same two broken files put through both commands, because the
    /// defect was that each command decoded on its own.
    List<({String label, List<String> args, String file})> cases() {
      final unparseable = _reviewFileHolding('not json at all').file;
      final wrongShape =
          _reviewFileHolding(jsonEncode({'version': 1, 'created': 'x'})).file;
      return [
        for (final (label, file) in [
          ('unparseable', unparseable),
          ('wrong shape', wrongShape),
        ]) ...[
          (label: 'resolve/$label', args: ['resolve', file], file: file),
          (
            label: 'export/$label',
            args: ['export', file, '--target', 'csv', '-o', 'out.csv'],
            file: file
          ),
        ],
      ];
    }

    test('every broken file is one stderr line and exit 2', () {
      for (final c in cases()) {
        final result = _runCli(c.args);
        expect(result.exitCode, 2, reason: c.label);
        expect(result.stderr, contains('Not a review file: ${c.file}'),
            reason: c.label);
        expect(_lines(result.stderr), hasLength(1), reason: c.label);
      }
    });

    test('unparseable and wrong-shape are told apart, with detail', () {
      for (final c in cases()) {
        final stderrText = _runCli(c.args).stderr as String;
        if (c.label.endsWith('unparseable')) {
          expect(stderrText, contains('is not JSON'), reason: c.label);
          expect(stderrText, contains('at line 1, column 1'), reason: c.label);
        } else {
          expect(stderrText, contains('is JSON but not a review document'),
              reason: c.label);
          expect(stderrText, contains('photos is missing'), reason: c.label);
        }
      }
    });

    test('prints no Dart frames for any of the four', () {
      for (final c in cases()) {
        final stderrText = _runCli(c.args).stderr as String;
        expect(stderrText, isNot(contains('Unhandled exception')),
            reason: c.label);
        expect(stderrText, isNot(contains('#0')), reason: c.label);
        expect(stderrText, isNot(contains('FormatException')), reason: c.label);
        expect(stderrText, isNot(contains('TypeError')), reason: c.label);
      }
    });

    test('resolve reports the file before it asks for IGDB credentials', () {
      // Without this order a broken file sends the user off to register a
      // Twitch application to be told, on their return, what was wrong.
      final broken = _reviewFileHolding('not json at all').file;
      final result = _runCli(['resolve', broken]);
      expect(result.stderr, isNot(contains('needs IGDB credentials')));
      expect(result.stderr, contains('is not JSON'));
    });

    test('a hand-edited but valid review file still exports', () {
      final json = _reviewFixture();
      (json['games'] as List<Object?>).add(_handWrittenEntry);
      final review =
          _reviewFileHolding(const JsonEncoder.withIndent('  ').convert(json));
      final out = _join(review.dir, 'shelf.csv');
      final result =
          _runCli(['export', review.file, '--target', 'csv', '-o', out]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Exported 1 of 1 approved game(s)'));
      expect(
          File(out).readAsStringSync(),
          'title,platform,media_type,external_id,source_photo\r\n'
          'Crown of Tidefall,PlayStation 5,disc,igdb:1100000048,shelf_b.jpg\r\n');
    });
  });

  group('the type name is not part of the format', () {
    /// The exact bytes a scan wrote while the type was `UnreadableSpine`,
    /// key order included. T-0154 renamed it to `UnreadSpineReport`; a file
    /// written before that has to come back out unchanged, which is what
    /// makes the rename an internal one.
    const beforeTheRename =
        '{"version":1,"created":"2026-08-14T09:00:00.000000Z",'
        '"photos":["shelf_b.jpg"],"games":[],'
        '"unreadable":[{"source_photo":"shelf_b.jpg","script":"japanese",'
        '"reason":"characters too small to resolve"}],'
        '"failed_photos":[],"not_looked_at_photos":[]}';

    test('a document written before the rename round-trips byte for byte', () {
      final doc = ReviewDocument.parse(beforeTheRename);
      expect(doc.version, 1);
      expect(doc.unreadable, hasLength(1));
      expect(jsonEncode(doc.toJson()), beforeTheRename);
    });

    test('nothing a scan writes spells either type name', () {
      final written = jsonEncode(ReviewDocument(
        version: 1,
        created: '2026-08-14T09:00:00.000000Z',
        photos: const ['shelf_b.jpg'],
        games: [],
        unreadable: [
          UnreadSpineReport(
              sourcePhoto: 'shelf_b.jpg', script: SpineScript.japanese),
        ],
      ).toJson());
      expect(written, isNot(contains('UnreadSpineReport')));
      expect(written, isNot(contains('UnreadableSpine')));
      expect(
          ((jsonDecode(written) as Map<String, dynamic>)['unreadable']
                  as List<dynamic>)
              .single,
          {
            'source_photo': 'shelf_b.jpg',
            'script': 'japanese',
            'reason': null,
          });
    });
  });
}
