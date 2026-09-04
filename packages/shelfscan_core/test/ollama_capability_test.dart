/// What the server says a model can do, and what this build does about it
/// (T-0464).
///
/// `OllamaVisionProvider` called `/api/chat` and nothing else, so a text-only
/// model failed once per photograph, late, with whatever the server happened
/// to say. Ollama answers both questions this needs on `/api/show`: a
/// top-level `capabilities` array carrying `vision` for a model an image may
/// be sent to, and `thinking` for one that reasons before it answers.
///
/// **The second is the discriminator and the model name is not.** The two
/// models this was reported on are both multimodal, so nothing keyed on
/// `vision` alone separates the one that answered from the one that spent the
/// whole output budget reasoning -- which is why there is no allowlist and no
/// blocklist of ids anywhere in this policy, and why the tests below use
/// invented ids for every case except the one the recommendation names.
///
/// The direction that matters most is the permissive one: an unknown
/// image-capable model, and everything the server did not say, must run.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// An id nothing here has ever heard of, which is the point of every test it
/// appears in.
const _unknownModel = 'nimbus-vision:7b';

const _url = 'http://ollama.test:11434';

/// Every request the probe made, so "exactly one, and to the manifest route"
/// is counted rather than read off the code.
final _requests = <http.BaseRequest>[];

http.Response _shows(List<Object?>? capabilities) => http.Response(
    jsonEncode({
      'details': {'family': 'invented'},
      if (capabilities != null) 'capabilities': capabilities,
    }),
    200,
    headers: {'content-type': 'application/json'});

Future<OllamaModelReport> _probe(
  Future<http.Response> Function(http.Request request) answer, {
  String model = _unknownModel,
  Duration timeout = const Duration(seconds: 5),
}) =>
    readOllamaModelReport(
      baseUrl: _url,
      model: model,
      timeout: timeout,
      client: MockClient((request) {
        _requests.add(request);
        return answer(request);
      }),
    );

OllamaModelReport _report(
        {OllamaCapability vision = OllamaCapability.present,
        OllamaCapability thinking = OllamaCapability.absent}) =>
    OllamaModelReport(vision: vision, thinking: thinking);

String? _refusalFor(OllamaModelReport report, {String model = _unknownModel}) =>
    ollamaModelRefusal(baseUrl: _url, model: model, report: report);

String? _warningFor(OllamaModelReport report, {String model = _unknownModel}) =>
    ollamaModelWarning(baseUrl: _url, model: model, report: report);

void main() {
  setUp(_requests.clear);

  group('the request is a manifest read and nothing else', () {
    test('one POST, to /api/show, naming the model and nothing more', () async {
      await _probe((_) async => _shows(['completion', 'vision']));

      expect(_requests, hasLength(1));
      final sent = _requests.single as http.Request;
      expect(sent.method, 'POST');
      expect(sent.url.toString(), '$_url/api/show');
      expect(jsonDecode(sent.body), {'model': _unknownModel});
    });

    test('it never reaches a route that would move a model', () async {
      await _probe((_) async => _shows(['completion', 'vision']));

      // The three that download, generate or unload. A probe is not allowed to
      // cost model time and is not allowed to install anything.
      final paths = _requests.map((request) => request.url.path).toList();
      for (final route in const ['/api/pull', '/api/generate', '/api/chat']) {
        expect(paths, isNot(contains(route)));
      }
    });
  });

  group('what the server said', () {
    test('vision and nothing else', () async {
      final report = await _probe((_) async => _shows(['completion',
        'vision']));

      expect(report.vision, OllamaCapability.present);
      expect(report.thinking, OllamaCapability.absent);
    });

    test('vision and thinking', () async {
      final report = await _probe(
          (_) async => _shows(['completion', 'vision', 'tools', 'thinking']));

      expect(report.vision, OllamaCapability.present);
      expect(report.thinking, OllamaCapability.present);
    });

    test('a model with no vision at all', () async {
      final report =
          await _probe((_) async => _shows(['completion', 'tools']));

      expect(report.vision, OllamaCapability.absent);
    });
  });

  group('and every way it said nothing', () {
    test('an Ollama with no capabilities key', () async {
      final report = await _probe((_) async => _shows(null));

      expect(report.vision, OllamaCapability.unknown);
      expect(report.thinking, OllamaCapability.unknown);
    });

    test('a 404 on the route', () async {
      final report = await _probe((_) async =>
          http.Response(jsonEncode({'error': 'not found'}), 404));

      expect(report.vision, OllamaCapability.unknown);
    });

    test('a server nothing answered at', () async {
      final report = await _probe(
          (_) async => throw http.ClientException('Connection refused'));

      expect(report.vision, OllamaCapability.unknown);
    });

    test('a body that is not JSON at all', () async {
      final report = await _probe((_) async => http.Response('404 page not '
          'found', 200));

      expect(report.vision, OllamaCapability.unknown);
    });

    test('a body that decodes to the wrong shape', () async {
      final report =
          await _probe((_) async => http.Response(jsonEncode(['vision']), 200));

      expect(report.vision, OllamaCapability.unknown);
    });

    test('capabilities that is not a list', () async {
      final report = await _probe((_) async =>
          http.Response(jsonEncode({'capabilities': 'vision'}), 200));

      expect(report.vision, OllamaCapability.unknown);
    });

    test('an EMPTY capabilities array is silence, not a model that can do '
        'nothing', () async {
      // Every model this server describes carries at least `completion`, so an
      // empty list is a shape nothing here has seen -- and refusing a run on a
      // shape nobody has measured is the one direction this policy must not
      // fail in.
      final report = await _probe((_) async => _shows(const []));

      expect(report.vision, OllamaCapability.unknown);
      expect(_refusalFor(report), isNull);
    });

    test('a server that accepted the connection and went quiet', () async {
      final report = await _probe(
        (_) async {
          await Completer<void>().future;
          throw StateError('unreachable');
        },
        timeout: const Duration(milliseconds: 50),
      );

      expect(report.vision, OllamaCapability.unknown);
    });
  });

  group('the policy, and it is the whole of it', () {
    test('vision absent is the one thing that stops a run', () {
      final refusal = _refusalFor(_report(vision: OllamaCapability.absent));

      expect(refusal, isNotNull);
      expect(refusal, contains('has no vision capability'));
      expect(refusal, contains(_unknownModel));
      expect(refusal, contains(_url));
      // What ShelfScan needs, and what this model cannot do.
      expect(refusal, contains('needs an image-capable model'));
      expect(refusal, contains('cannot be sent an image'));
      // And it does not change the model for anyone.
      expect(_warningFor(_report(vision: OllamaCapability.absent)), isNull);
    });

    test('vision and thinking runs, and warns', () {
      final report = _report(thinking: OllamaCapability.present);

      expect(_refusalFor(report), isNull);
      final warning = _warningFor(report);
      expect(warning, isNotNull);
      expect(warning, contains('reasons before it answers'));
      expect(warning, contains('one concise structured answer'));
      expect(warning, contains('scan is going ahead'));
      expect(warning, contains(testedOllamaInstructModel));
    });

    test('vision and no thinking runs with no warning of any kind', () {
      final report = _report();

      expect(_refusalFor(report), isNull);
      expect(_warningFor(report), isNull);
    });

    test('an answer that was never given blocks and warns nothing', () {
      const report = OllamaModelReport.unanswered();

      expect(_refusalFor(report), isNull);
      expect(_warningFor(report), isNull);
    });

    test('a partial answer is not read as a whole one', () {
      // `thinking` unknown beside `vision` present is what an older Ollama
      // publishing a shorter list would look like. Warning there would be a
      // claim the server never made.
      expect(
          _warningFor(_report(thinking: OllamaCapability.unknown)), isNull);
      expect(_refusalFor(_report(vision: OllamaCapability.unknown)), isNull);
    });
  });

  group('no id decides anything', () {
    test('the verdict is a function of the capabilities, never of the name',
        () {
      // Whatever a family name suggests, the same report gets the same
      // verdict. This is the property an allowlist or a blocklist would break,
      // and it is asserted rather than argued because the defect this task was
      // reported against is exactly a name that looked capable and was.
      for (final id in const [
        _unknownModel,
        testedOllamaInstructModel,
        'qwen-invented:1b',
        'llama-invented:1b',
        'llava-invented:1b',
        'something-nobody-has-published:70b',
      ]) {
        expect(_refusalFor(_report(vision: OllamaCapability.absent), model: id),
            isNotNull,
            reason: id);
        expect(_refusalFor(_report(), model: id), isNull, reason: id);
        expect(
            _warningFor(_report(thinking: OllamaCapability.present), model: id),
            isNotNull,
            reason: id);
        expect(_warningFor(_report(), model: id), isNull, reason: id);
      }
    });
  });

  group('what a user choosing a model is told', () {
    test('it says what a good fit is without naming a default', () {
      expect(ollamaModelAdvice, contains('image-capable'));
      expect(ollamaModelAdvice, contains('one concise structured answer'));
      expect(ollamaModelAdvice, contains(testedOllamaInstructModel));
      expect(ollamaModelAdvice, contains('tested here'));
      // Other models work, and this one is not claimed to be the only or the
      // better one.
      expect(ollamaModelAdvice, contains('not validated here'));
      expect(ollamaModelAdvice.toLowerCase(), isNot(contains('default')));
      expect(ollamaModelAdvice.toLowerCase(), isNot(contains('better')));
      expect(ollamaModelAdvice.toLowerCase(), isNot(contains('recommended')));
      expect(ollamaModelAdvice.toLowerCase(), isNot(contains('only')));
    });

    test('the evidence is quoted at exactly the size it is', () {
      final warning = _warningFor(_report(thinking: OllamaCapability.present))!;

      expect(warning,
          contains('all three photographs of the run this was reported on'));
      // And nothing else off that run reaches a sentence a stranger reads: no
      // detection count, no title, no ratio, no claim of superiority.
      for (final claim in const [
        '%',
        'detection',
        'spine',
        'better',
        'best',
        'only supported',
      ]) {
        expect(warning.toLowerCase(), isNot(contains(claim)), reason: claim);
      }
    });

    test('the other two sentences quote no run at all', () {
      for (final text in [
        ollamaModelAdvice,
        _refusalFor(_report(vision: OllamaCapability.absent))!,
      ]) {
        expect(text, isNot(contains('three')), reason: text);
        expect(text, isNot(contains('photographs of')), reason: text);
      }
    });
  });
}
