/// Which failures blame something the user set, and the guard that stops a new
/// one from arriving without an answer (T-0169).
///
/// The defect: `_settingsCanFix` in the app read the answer off the HTTP status,
/// and four sentences landed in one day that a status cannot separate -- three
/// of them end on the model id and the fourth says the model id is fine, all
/// four carrying 200, and one of them not a `VisionApiException` at all. The
/// answer now travels on the failure, written by whoever wrote the sentence.
///
/// The table below is the whole of that decision, one row per builder, and the
/// last test makes it impossible to add a builder without adding a row.
library;

import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// One record written out until the budget was gone: the loop road (T-0427).
///
/// Invented, like every fixture here, and the repetition is the whole of it --
/// what `answerRepeatsItself` reads is exact repetition of a whole record.
const _record = '{"raw_title":"Silt Harbour","platform_hint":"SWITCH",'
    '"media_type":"cartridge","confidence":0.9}';
final _looping = '{"items":[${List.filled(40, _record).join(',')}';

/// The answer each builder gives, per input that changes it.
///
/// Built by calling the real builders, never by constructing the exception by
/// hand: what is pinned is the answer a provider actually throws.
final _answered = <String, Map<String, ({Object failure, bool? userSet})>>{
  // Plumbing shared by the cloud and local vocabularies: it decides nothing and
  // carries what its caller decided. The retryable branch answers nothing at
  // all, which is the whole reason 429 and 5xx need no status test anywhere.
  'visionFailure': {
    'passes true through': (
      failure: visionFailure(
          message: 'x',
          statusCode: 404,
          body: '',
          retryable: false,
          causeIsUserSet: true),
      userSet: true,
    ),
    'passes false through': (
      failure: visionFailure(
          message: 'x',
          statusCode: 400,
          body: '',
          retryable: false,
          causeIsUserSet: false),
      userSet: false,
    ),
    'a retryable failure is not a UserSetCause': (
      failure: visionFailure(
          message: 'x',
          statusCode: 429,
          body: '',
          retryable: true,
          causeIsUserSet: true),
      userSet: null,
    ),
  },
  'visionApiFailure': {
    'a rejected key is the key they configured': (
      failure: _api(401),
      userSet: true,
    ),
    // T-0435: the 403 sentence names the key among several causes rather
    // than as the fault, and every one of them is a Settings field.
    'a refusal still points at the key field': (
      failure: _api(403),
      userSet: true,
    ),
    'an unknown model id is theirs to type (T-0067)': (
      failure: _api(404),
      userSet: true,
    ),
    // "a parameter or the model id", and only one of the two is theirs.
    'a refused request names one field of two': (
      failure: _api(400),
      userSet: false,
    ),
    'an unmapped status names no field': (failure: _api(418), userSet: false),
    'a rate limit answers nothing': (
      failure: _api(429, retryable: true),
      userSet: null,
    ),
  },
  // T-0111, and one builder with both answers since T-0465. On two of the three
  // roads the sentence names the key, the model id and the photo file as all
  // fine and the cap is a constant neither surface exposes. On the third it
  // says the opposite -- no evidence about the photograph, and a vision
  // instruct model as the thing to reach for -- so that row answers true, for
  // the reason `visionWrongShapeFailure`'s second row answers false.
  'visionTruncatedFailure': {
    'the output cap is not a Settings field': (
      failure: visionTruncatedFailure(
          service: 'Anthropic',
          model: 'claude-x',
          cap: 4096,
          answer: '{"items":[',
          body: '{}'),
      userSet: false,
    ),
    'nor is a frame the model enumerated without end': (
      failure: visionTruncatedFailure(
          service: 'Ollama',
          model: 'qwen2.5vl:7b',
          cap: 8192,
          answer: _looping,
          body: '{}',
          hasKey: false),
      userSet: false,
    ),
    'but a completion that wrote nothing is the model id (T-0465)': (
      failure: visionTruncatedFailure(
          service: 'Ollama',
          model: 'qwen2.5vl:7b',
          cap: null,
          answer: '',
          body: '{}',
          hasKey: false),
      userSet: true,
    ),
  },
  // T-0142. Both branches end on the model id and the backend.
  'visionEmptyAnswerFailure': {
    'no text at all: try another model id or backend': (
      failure: visionEmptyAnswerFailure(
          service: 'Anthropic', model: 'claude-x', reason: 'stop', body: '{}'),
      userSet: true,
    ),
    'a refused photograph: a different reader is the remedy': (
      failure: visionEmptyAnswerFailure(
          service: 'Anthropic',
          model: 'claude-x',
          reason: 'content_filter',
          body: '{}'),
      userSet: true,
    ),
  },
  // T-0164, and the one that reached the app as a type it could not classify.
  'visionNotJsonFailure': {
    'prose instead of JSON: the model id is the thing to change': (
      failure: visionNotJsonFailure(
          service: 'Ollama', model: 'llama-x', answer: 'Sure! Here you go:'),
      userSet: true,
    ),
  },
  // T-0167, and the second row T-0428.
  'visionWrongShapeFailure': {
    'JSON of the wrong shape: the model id again': (
      failure: visionWrongShapeFailure(
          service: 'Ollama',
          model: 'llama-x',
          problem: 'items is a String; it must be a list',
          answer: '{"items":"Vex"}'),
      userSet: true,
    ),
    // One builder, both answers, decided on the document and not on the
    // status: a looping frame is the photograph's to fix and the sentence says
    // so, and offering Settings behind it would take back what it said.
    'a repetition loop is not the model id': (
      failure: visionWrongShapeFailure(
          service: 'Ollama',
          model: 'llama-x',
          problem: 'the answer is a list; it must be an object',
          answer: '[]',
          document: List.filled(40, {'raw_title': 'Copper Vellum'})),
      userSet: false,
    ),
  },
  'ollamaFailure': {
    'a model that is not pulled is the model id they typed': (
      failure: _ollama(404, body: '{"error":"model \'qwen\' not found"}'),
      userSet: true,
    ),
    'an address that is not an Ollama root is the URL they typed': (
      failure: _ollama(404, body: '404 page not found'),
      userSet: true,
    ),
    'a photo the server could not decode is not a field': (
      failure: _ollama(400),
      userSet: false,
    ),
    // A keyless server has no vocabulary for these; they fall to the bare
    // "refused the request" line, which names nothing. The cloud allowlist used
    // to offer the route for them anyway.
    'a status this vocabulary does not know names nothing': (
      failure: _ollama(401),
      userSet: false,
    ),
    'a dying model runner answers nothing': (
      failure: _ollama(500),
      userSet: null,
    ),
  },
};

/// Builders whose product cannot reach the one caller, with the reason.
///
/// `_settingsCanFix` classifies `ScanFailedException.failures`, which are the
/// vision stage's per-photo errors. A resolve-stage failure degrades to an
/// unresolved row and never arrives (T-0105 records the same about
/// `IgdbUnreachableException`). If that ever changes, this entry moves into the
/// table above rather than staying here.
const _cannotReachTheCaller = {'igdbFailure'};

Exception _api(int status, {bool retryable = false}) => visionApiFailure(
      service: 'Anthropic',
      model: 'claude-x',
      statusCode: status,
      body: '{"error":{"message":"nope"}}',
      retryable: retryable,
    );

Exception _ollama(int status, {String body = '{"error":"nope"}'}) =>
    ollamaFailure(
      baseUrl: 'http://localhost:11434',
      model: 'qwen',
      statusCode: status,
      body: body,
    );

void main() {
  group('the failure answers, not the status', () {
    _answered.forEach((builder, cases) {
      cases.forEach((what, expected) {
        test('$builder: $what', () {
          if (expected.userSet == null) {
            expect(expected.failure, isNot(isA<UserSetCause>()));
            return;
          }
          expect(expected.failure, isA<UserSetCause>());
          expect((expected.failure as UserSetCause).causeIsUserSet,
              expected.userSet);
        });
      });
    });

    test('one status, both answers -- which is why the status cannot decide',
        () {
      final byStatus = <int, Set<bool>>{};
      for (final cases in _answered.values) {
        for (final expected in cases.values) {
          if (expected.failure case VisionApiException(
                :final statusCode,
                :final causeIsUserSet
              )) {
            (byStatus[statusCode] ??= {}).add(causeIsUserSet);
          }
        }
      }

      expect(byStatus[200], {true, false},
          reason: 'the four 200-shape sentences disagree, so no expression '
              'over statusCode could have produced this column');
      expect(byStatus[404], {true},
          reason: 'and the statuses that do agree still agree');
    });
  });

  // T-0465. The table above pins the answers; this pins what the defect
  // actually was, which no value in that table can express: a flag decided by
  // one reading of the answer sitting under a sentence decided by another. So
  // each case asserts the sentence it got FIRST -- a fixture that stopped
  // taking its road would otherwise flip this group green for the wrong
  // reason -- and only then what the flag says about it.
  group('the Settings answer agrees with the sentence it sits under', () {
    final roads = <String, ({String answer, String conclusion, bool userSet})>{
      'silent': (
        answer: '',
        conclusion: 'Nothing here is evidence about the photograph',
        userSet: true,
      ),
      'loop': (
        answer: _looping,
        conclusion: 'it enumerates them without end',
        userSet: false,
      ),
      'density': (
        answer: '{"items":[',
        conclusion: 'there was more on that shelf than one answer can hold',
        userSet: false,
      ),
    };

    roads.forEach((road, expected) {
      test('the $road road', () {
        final failure = visionTruncatedFailure(
            service: 'Ollama',
            model: 'qwen2.5vl:7b',
            cap: 8192,
            answer: expected.answer,
            body: '{}') as VisionApiException;

        expect(failure.message, contains(expected.conclusion),
            reason: 'this fixture no longer takes the $road road, so the flag '
                'below is being checked against a sentence it is not under');
        expect(failure.causeIsUserSet, expected.userSet,
            reason: 'the $road sentence and the Open settings button under it '
                'disagree');
      });
    });
  });

  group('T-0164 keeps its pinned type', () {
    final notJson = visionNotJsonFailure(
        service: 'Ollama', model: 'llama-x', answer: 'Sure! Here you go:');

    test('a subclass, so T-0013 and T-0083 still match it', () {
      expect(notJson, isA<FormatException>());
      expect(notJson, isA<VisionNotJsonException>());
    });

    test('and the prefix is unmoved: dart:core writes the literal', () {
      expect(notJson.toString(), startsWith('FormatException: '));
      expect(notJson.toString(), contains('llama-x'));
    });
  });

  // The defect this task was filed for, made permanent: a fifth sentence added
  // beside the four, carrying no answer, and falling silently to `false` in the
  // app. Four landed in one day; there will be a fifth. Same shape as
  // `unreachable_supertype_test.dart`'s scan of `lib/`.
  test('a new failure builder cannot skip the question', () {
    final declaration = RegExp(
        r'^(?:Exception|FormatException) (\w+Failure)\(',
        multiLine: true);
    final found = <String, String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in declaration.allMatches(file.readAsStringSync())) {
        found[m.group(1)!] = file.path;
      }
    }

    final unanswered = found.keys
        .where((name) =>
            !_answered.containsKey(name) &&
            !_cannotReachTheCaller.contains(name))
        .map((name) => '${found[name]}: $name')
        .toList();

    expect(unanswered, isEmpty,
        reason: 'a failure builder with no row above is one whose sentence '
            'nobody decided the Settings route for -- add a row, or name it in '
            '_cannotReachTheCaller with the reason');
    expect(found.keys, containsAll(_answered.keys),
        reason: 'a row above for a builder that no longer exists');
  });
}
