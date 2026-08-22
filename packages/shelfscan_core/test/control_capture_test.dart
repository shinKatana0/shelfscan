/// The capture's key and its four verdicts (T-0131).
///
/// No photo, no Ollama, no network -- everything here is synthetic, because the
/// question is not "are the detections right" (the manifest answers that) but
/// "does a capture that cannot be checked get treated as good". That is the
/// case that bites: absent and stale announce themselves, unverifiable looks
/// exactly like fresh from the outside.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../tool/control_capture.dart';

/// A manifest block small enough to reason about, in the document's own shape.
const _section = {
  'photos': 'a.jpg, b.jpg',
  'sizes': '10, 20',
  'detections': '3',
  'per_photo': '2, 1',
  'hints_answered': '3',
  'hint_SWITCH': '2',
  'hint_PS5': '1',
  'empty_titles': '0',
  'unreadable': '0',
};

const _env = {
  'SHELFSCAN_OLLAMA_MODEL': 'qwen2.5vl:7b',
  'SHELFSCAN_OLLAMA_URL': 'http://localhost:11434',
  'OLLAMA_NUM_PARALLEL': '1',
};

CaptureKey _key() => wantedKey('CONTROL-TEST', _section, _env);

/// The published manifest's shape: labels and photo lists, and none of the
/// figures, which is what a clone holds.
const _published = '''
```control-set
[CONTROL-HIRES]
photos = a.jpg, b.jpg
```

```control-set
[CONTROL-LOWRES]
photos = c.jpg
```
''';

/// The same file with both control-set blocks hand-edited out.
const _promptOnly = '''
```control-set
[PROMPT]
fingerprint = 0000beef
```
''';

/// The working record's half, invented: it only has to exist and parse.
const _workingRecord = '''
```control-set
[CONTROL-HIRES]
sizes = 10, 20
```
''';


Map<String, dynamic> _detection(String photo, String title, String? hint) =>
    Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.disc,
      confidence: 1,
      sourcePhoto: photo,
    ).toJson();

Map<String, dynamic> _capture(CaptureKey key) => {
      'format': captureFormat,
      'key': key.toJson(),
      'captured': '2026-08-16T00:00:00.000Z',
      'detections': [
        _detection('a.jpg', 'One', 'SWITCH'),
        _detection('a.jpg', 'Two', 'SWITCH'),
        _detection('b.jpg', 'Three', 'PS5'),
      ],
      'unreadable': <Object>[],
    };

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shelfscan-capture-test');
    path = '${dir.path}/capture.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void write(Object? body) =>
      File(path).writeAsStringSync(body is String ? body : jsonEncode(body));

  group('the key', () {
    test('names the file after everything that decides the answer', () {
      expect(_key().fileName,
          'CONTROL-TEST.${promptFingerprint(detectionPrompt)}'
          '.qwen2.5vl-7b.np1.json');
    });

    test('records OLLAMA_NUM_PARALLEL as unset when the client cannot see it',
        () {
      expect(wantedKey('CONTROL-TEST', _section, const {}).numParallel,
          'unset');
    });

    test('carries the manifest photos with their byte sizes', () {
      expect(_key().photos, {'a.jpg': 10, 'b.jpg': 20});
    });
  });

  group('a capture', () {
    test('is FRESH when the key and every counted figure agree', () {
      write(_capture(_key()));
      final check = checkCapture(path, _key(), _section);
      expect(check.verdict, Verdict.fresh, reason: check.reason);
      expect(check.usable, isTrue);
    });

    test('is ABSENT when there is no file', () {
      expect(checkCapture('${dir.path}/nothing.json', _key(), _section).verdict,
          Verdict.absent);
    });

    test('is STALE when the prompt fingerprint moved', () {
      final old = _capture(_key());
      (old['key'] as Map)['prompt_fingerprint'] = 'deadbeef';
      write(old);
      final check = checkCapture(path, _key(), _section);
      expect(check.verdict, Verdict.stale);
      expect(check.reason, contains('prompt_fingerprint'));
    });

    test('is STALE when the model or the server parallelism moved', () {
      for (final field in ['model', 'ollama_num_parallel', 'ollama_url']) {
        final other = _capture(_key());
        (other['key'] as Map)[field] = 'something else';
        write(other);
        final check = checkCapture(path, _key(), _section);
        expect(check.verdict, Verdict.stale, reason: field);
        expect(check.reason, contains(field));
      }
    });

    test('is STALE when a control photo was re-cropped', () {
      final other = _capture(_key());
      (other['key'] as Map)['photos'] = {'a.jpg': 11, 'b.jpg': 20};
      write(other);
      expect(checkCapture(path, _key(), _section).verdict, Verdict.stale);
    });

    // The truncated-write case: it parses, the key is intact, and only the
    // manifest catches it. Checked on every status call for that reason.
    test('is STALE when the body no longer reproduces the manifest', () {
      final short = _capture(_key());
      (short['detections'] as List).removeLast();
      write(short);
      final check = checkCapture(path, _key(), _section);
      expect(check.verdict, Verdict.stale);
      expect(check.reason, contains('2 detections'));
    });

    test('is STALE when unreadable moved, naming the cache state', () {
      final phantom = _capture(_key());
      phantom['unreadable'] = [
        UnreadSpineReport(sourcePhoto: 'a.jpg', script: SpineScript.japanese)
            .toJson(),
      ];
      write(phantom);
      expect(checkCapture(path, _key(), _section).reason, contains('T-0106'));
    });

    test('is UNVERIFIABLE, never fresh, when it cannot be checked', () {
      final incomplete = _capture(_key());
      (incomplete['key'] as Map).remove('model');
      final unreadableBody = _capture(_key());
      unreadableBody['detections'] = [
        {'platform_hint': 'SWITCH'},
      ];
      final cases = <String, Object>{
        'not JSON at all': '{ truncated',
        'a JSON array': <Object>[],
        'an unknown format': {..._capture(_key()), 'format': captureFormat + 1},
        'a key missing a field': incomplete,
        'a body that does not read back': unreadableBody,
      };
      cases.forEach((name, body) {
        write(body);
        final check = checkCapture(path, _key(), _section);
        expect(check.verdict, Verdict.unverifiable, reason: name);
        expect(check.usable, isFalse, reason: name);
      });
    });
  });

  group('writeAtomically', () {
    test('leaves no partial file behind and no temp file after it', () {
      writeAtomically(path, '{"format": 1}');
      expect(File(path).readAsStringSync(), '{"format": 1}');
      expect(
          dir.listSync().map((e) => e.path.endsWith('.tmp')), isNot(contains(true)));
    });

    test('creates the capture directory on first use', () {
      final nested = '${dir.path}/a/b/capture.json';
      writeAtomically(nested, 'x');
      expect(File(nested).existsSync(), isTrue);
    });
  });

  group('a checkout without the working record', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('shelfscan-clone-test');
      File('${root.path}/$manifestPath')
        ..createSync(recursive: true)
        ..writeAsStringSync(_published);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('says which document holds the figures and that it is elsewhere', () {
      expect(figuresNotHere(root), contains(controlSetPath));
    });

    test('answers a named verdict, not a stack trace (T-0261)', () {
      final lines = notHereReport([hiRes, lowRes], figuresNotHere(root)!);
      expect(lines.first, startsWith('$hiRes: UNVERIFIABLE -- '));
      expect(lines[1], startsWith('$lowRes: UNVERIFIABLE -- '));
      // The line that makes it actionable: there is a check a clone CAN run.
      expect(lines.last, contains('dart test'));
    });

    test('exits with the documented code, whichever command asked', () async {
      for (final command in ['where', 'status', 'capture', 'replay']) {
        expect(
            await run([command, 'all'],
                from: root,
                environment: {'SHELFSCAN_CAPTURE_DIR': '${root.path}/here'}),
            notHereExit,
            reason: command);
      }
    });

    test('reads them again where the record is beside the photographs', () {
      File('${root.path}/$controlSetPath').writeAsStringSync(_workingRecord);
      expect(figuresNotHere(root), isNull);
    });
  });

  group('a manifest missing a block', () {
    test('names the block and the file it is missing from (T-0232)', () {
      expect(blockMissing(const {}, hiRes), contains('[$hiRes]'));
      expect(blockMissing(const {}, hiRes), contains(manifestPath));
      expect(
          blockMissing(const {
            hiRes: {'photos': 'a.jpg'}
          }, hiRes),
          isNull);
    });

    test('is a named exit rather than a null check', () async {
      final root = Directory.systemTemp.createTempSync('shelfscan-block-test');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/$manifestPath')
        ..createSync(recursive: true)
        ..writeAsStringSync(_promptOnly);
      expect(
          await run(['status', hiRes],
              from: root,
              environment: {'SHELFSCAN_CAPTURE_DIR': '${root.path}/here'}),
          2);
    });
  });

  group('the capture directory', () {
    test('is outside the repository and per-user', () {
      expect(captureDir(const {'LOCALAPPDATA': r'C:\Users\x\AppData\Local'}),
          'C:/Users/x/AppData/Local/shelfscan/control-capture');
      expect(captureDir(const {'HOME': '/home/x'}),
          '/home/x/.cache/shelfscan/control-capture');
      expect(captureDir(const {'SHELFSCAN_CAPTURE_DIR': '/elsewhere'}),
          '/elsewhere');
    });

    test('refuses to guess when it has nothing to go on', () {
      expect(() => captureDir(const {}), throwsStateError);
    });
  });
}
