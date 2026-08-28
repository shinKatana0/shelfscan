/// Vision provider backed by a local Ollama server.
///
/// Expect a lower hit rate than frontier cloud models on small spine
/// text and Japanese titles -- measure, don't assume (backlog T-0001).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_timeout.dart';
import '../unreachable.dart';
import 'vision.dart';

/// The local defaults, defined once for the whole repository (T-0087).
///
/// They live beside the provider because these two are the values a caller
/// that passes nothing actually gets; anywhere else is a copy that has to
/// agree. Since T-0082 they are also the *meaning* of a cleared Ollama field
/// in Settings, whose `hintText` is the string itself -- so a drifted copy
/// would change what clearing that field does and say so in the hint.
///
/// `documented_lists_test.dart` fails on a second literal in code and on
/// `.env.example` or README.md stating a default these no longer hold.
const defaultOllamaUrl = 'http://localhost:11434';
const defaultOllamaModel = 'qwen2.5vl:7b';

/// Any fixed value would do; this one is the date it was chosen (T-0053).
const _defaultSeed = 20260814;

/// The generation cap this request carries, and why the ceiling that bounds it
/// is [timeout] rather than the context window (T-0281).
///
/// Without one, this model repeats itself under greedy decoding and generates
/// until the context window is full. **Repetition is the mechanism; density is
/// one trigger for it and not the only one** (T-0427) -- a frame carrying no
/// more readable titles than one that scans cleanly reaches the same fixed
/// point if it also holds many narrow strips that look like a spine and carry
/// no title, because the model cannot tell one from the next. So this cap
/// bounds a loop whatever started it, and the branch below has to say which
/// one it was. Measured past the density ceiling on a synthetic 176-spine
/// frame, first ask: 27836 tokens after a 4932-token prefill -- `4932 + 27836
/// = 32768` exactly -- 296 s, and what comes back is not JSON, so the photo
/// yields nothing. `temperature` 0 is why nothing escapes: greedy decoding has
/// no draw to break a repetition fixed point with. The same frame and the same
/// first-ask sequence under this cap stops at 8192 tokens exactly with
/// `done_reason: length` in 93 s, which is the branch below -- the user
/// reaches [visionTruncatedFailure] and the advice that fits their frame three
/// times sooner.
///
///   floor    a frame that answers must not be cut off and called truncated.
///            Output is linear at ~48 tokens a row; T-0278's densest honest
///            rung generates 5504 (120 spines), and a synthetic 120-spine
///            frame here answered in 4690 with `done_reason: stop`. 4096 also
///            stops the loop, in 46 s, and is rejected because it sits under
///            both.
///   ceiling  the cap only helps if generation REACHES it inside [timeout].
///            Past that the call is aborted as a stall, the user is told the
///            server went quiet, and the advice that fits is never printed.
///            The cold-ask budget measured here is 8.6 s to load the model,
///            3.5 s to prefill and 103.8 generated tokens/s, so 120 s buys
///            about 11200 tokens: 12288 needs ~130 s and would never fire.
///
/// 8192 clears the honest maximum by half again and lands at 93 s of a 120 s
/// bound. Both bounds are throughput-dependent and the throughput is not:
/// T-0278 measured 24-105 tokens/s on one machine depending only on what else
/// was running, so under contention no cap is reachable and the stall message
/// is what the user gets. This value buys the uncontended case, which is the
/// ordinary one.
///
/// That it equals `_maxOutputTokens` in openai_compatible_vision.dart is two
/// arguments arriving at one number rather than a shared constant -- that one
/// clears a reasoning model's tail, this one clears a dense shelf -- so
/// neither moves the other.
const _numPredict = 8192;

/// Named because two of the messages below quote the route the 404 came from,
/// which is the whole evidence that a 404 is about the address and not the
/// model.
const _chatPath = '/api/chat';

class OllamaVisionProvider implements VisionProvider {
  /// Sampling is stated rather than inherited (T-0053). Ollama's documented
  /// default is temperature 0.8, but qwen2.5vl:7b's own Modelfile sets
  /// `temperature 0.0001`, so every figure this project recorded before this
  /// change was near-greedy by the model's accident and not by request -- a
  /// re-pull, a different tag or a different model moves it silently.
  ///
  /// [temperature] 0 buys repeatability, not quality, and the two were
  /// measured apart: against the pre-T-0053 request (no `options` at all) the
  /// detections come back identical on both control sets, same counts, same
  /// titles, same hints -- see the doc comment on [detectionPromptRules] for
  /// the repeat counts behind them.
  ///
  /// What that repeatability is, exactly (T-0086, 2026-08-15, `CONTROL-HIRES`
  /// against a server started for the measurement, `OLLAMA_NUM_PARALLEL=1`,
  /// its request log accounting for all 18 requests it served):
  ///
  ///   5 consecutive repeat runs      byte-identical documents
  ///   3 runs, prompt cache dropped   byte-identical to each other, and
  ///                                  differing from the five on about a third
  ///                                  of one photo's rows -- case, TM/(R), one
  ///                                  diacritic; no count, hint or item moved
  ///   3 runs under competing traffic byte-identical to the isolated five
  ///                                  (30 of 50 requests overlapped in time)
  ///   3 runs on a second server       both documents reproduced to the byte,
  ///     process, 3.5 h later          1 first ask and 2 repeats
  ///
  /// So a photo this server process has already answered comes back to the
  /// byte; a photo it has not is answered once and reproducibly in the other
  /// typography. llama-server logs `cached n_tokens = 4890` of 4891 on a
  /// repeat and 15 on a first ask, so the two are not the same arithmetic.
  ///
  /// **There is a third state, and it has no document (T-0106, 2026-08-15).**
  /// The cache matches a token PREFIX and the photo's tokens come first -- of
  /// the 4891 tokens a hi-res photo makes, the prompt text is the last 860 --
  /// so `cached n_tokens` also reads 4031-4885 when the same photo has been
  /// asked under a DIFFERENT prompt text, the image staying cached while the
  /// text is re-prefilled from where the two texts diverge. It holds several
  /// photos at once: three consecutive `CONTROL-HIRES` scans logged 4890 on all
  /// six asks of runs 2 and 3, and a scan of the set under a changed prompt put
  /// all three photos of the second pass at 4817. So an ordinary prompt A/B
  /// lands there, not just a single-photo alternation.
  ///
  /// In it the model answers 3 phantom `unreadable` entries for a photo whose
  /// hand-counted truth is none, two of them byte-identical, while every count
  /// on both control sets holds. Three on 18 of 34 asks and none on the other
  /// 16:
  /// 2 of 2 whole-set A/B runs; from `ollama stop`, 5 of 5, 3 of 3 and 2 of 2
  /// at three of the five divergence points tried and 0 of 3 at the other two,
  /// so where the change sits does not predict which; 4 of 14 on a server left
  /// running, where 13 of those 14 also read one bilingual spine without its
  /// non-English half, which [titleKey] does not fold. The one line that keeps
  /// a measurement out of it is `ollama stop` immediately before the run --
  /// doc/measurements.md, "A third cache state", carries the table and the
  /// recipe.
  ///
  /// Concurrency was the first suspect and it cannot bite at
  /// `OLLAMA_NUM_PARALLEL=1`, which is Ollama's default and what every run
  /// above used: overlapping requests queue rather than share a batch. Four
  /// runs on a server at `OLLAMA_NUM_PARALLEL=4` say what happens where they can: its
  /// two isolated runs agreed with each other and differed from the np=1
  /// document on 3 rows, one of them a title read without its first half --
  /// which [titleKey] does NOT fold -- and 1 of 2 runs under competing traffic
  /// moved one further row. The setting is not this repository's to set, which
  /// puts it in the same class as the Modelfile temperature above. Both
  /// callers do send local photos one at a time (`visionConcurrency` 1 for
  /// ollama in `bin/shelfscan.dart` and in the app's `ProviderPolicy`), so a
  /// single scan never overlaps itself whatever the server allows.
  ///
  /// [seed] is inert while [temperature] is 0 -- greedy decoding never draws,
  /// and seeds 1 / 12345 / 99 give byte-identical output. It is a constructor
  /// parameter rather than a bare constant anyway, because sampling is how a
  /// caller finds out how wide the distribution behind a single historical
  /// figure was, and that measurement needs the seed to move.
  OllamaVisionProvider({
    this.baseUrl = defaultOllamaUrl,
    this.model = defaultOllamaModel,
    this.temperature = 0,
    this.seed = _defaultSeed,
    this.timeout = visionCallTimeout,
    this.stallRemedy,
    http.Client? client,
  }) : _client = client;

  final String baseUrl;
  final String model;
  final double temperature;
  final int seed;

  /// See [visionCallTimeout] for what the default rests on, including the one
  /// measured local model this aborts.
  final Duration timeout;

  /// What a shell that can change [timeout] tells the user to do about a stall
  /// (T-0152). Null on a shell that cannot, which is the app: the diagnosis is
  /// this package's and true everywhere, the remedy is the CLI's.
  final String? stallRemedy;
  final http.Client? _client;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    final http.Response response;
    try {
      response = await boundedPost(
        (client) => client.post(
          Uri.parse('$baseUrl$_chatPath'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'stream': false,
            'format': 'json',
            'options': {
              'temperature': temperature,
              'seed': seed,
              'num_predict': _numPredict,
            },
            'messages': [
              {
                'role': 'user',
                'content': detectionPrompt,
                'images': [base64Encode(photo.bytes)],
              },
            ],
          }),
        ),
        reusing: _client,
        within: timeout,
        onTimeout: (waited) => OllamaUnreachableException.timedOut(
            baseUrl, waited,
            stallRemedy: stallRemedy),
      );
    } on http.ClientException catch (e) {
      // e.message, not '$e': the toString carries an ephemeral local port and
      // the request URI, and the reason is the only part that helps.
      throw OllamaUnreachableException(baseUrl, e.message);
    }

    if (response.statusCode != 200) {
      throw ollamaFailure(
        baseUrl: baseUrl,
        model: model,
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final answer = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (answer['message'] as Map<String, dynamic>?)?['content'] as String?;
    // Reached routinely, not hypothetically: once this model is looping it
    // runs to [_numPredict] every time (T-0281), which is why the cap is named
    // here rather than passed as null. An Ollama old enough to omit
    // `done_reason` still falls through to the parse.
    if (answer['done_reason'] == 'length') {
      throw visionTruncatedFailure(
        service: 'Ollama at $baseUrl',
        model: model,
        cap: _numPredict,
        answer: content ?? '',
        body: response.body,
        hasKey: false,
      );
    }
    // The same hole as the cloud pair (T-0142): this server answers 200 with an
    // empty `content` and a `done_reason` of its own -- `load` and `unload` are
    // the documented ones -- and the parse then blamed the JSON for it. No
    // content filter here, so the reason is only ever named, never explained.
    if (content == null || content.trim().isEmpty) {
      throw visionEmptyAnswerFailure(
        service: 'Ollama at $baseUrl',
        model: model,
        reason: answer['done_reason']?.toString(),
        body: response.body,
        hasKey: false,
      );
    }
    return parsePhotoAnalysisAnswer(content, photo.name,
        service: 'Ollama at $baseUrl', model: model, hasKey: false);
  }
}

// --------------------------------------------------------------------- //

/// Nothing answered at the configured address -- no HTTP status was ever
/// reached, which is why this is not a [VisionApiException] (T-0097).
///
/// The one failure the default Windows path invites by construction: this
/// provider is the default there, and the server it needs is a separate
/// program the user has to have started, with nothing to configure first.
///
/// [timedOut] joins it rather than getting a type of its own (T-0104): a server
/// that accepted the connection and then went quiet leaves the caller with the
/// same nothing -- no status, no body, the same address to check. The retry
/// arithmetic is on [VisionUnreachableException]; it is the same here, and
/// worse in one respect, because a local scan sends its photos one at a time.
class OllamaUnreachableException extends UnreachableEndpoint {
  OllamaUnreachableException(this.baseUrl, this.reason)
      : waited = null,
        stallRemedy = null;

  /// Nothing arrived inside the budget, so there is no socket [reason]: no
  /// error was reported, which is the complaint.
  OllamaUnreachableException.timedOut(this.baseUrl, Duration this.waited,
      {this.stallRemedy})
      : reason = '';

  /// Named for the caller that types it, and kept under that name because it is
  /// the whole of this provider's configuration.
  final String baseUrl;

  @override
  String get endpoint => baseUrl;

  /// Always the user's: it is a Settings field, and a cleared one resolves to
  /// [defaultOllamaUrl] rather than to nothing (T-0082). A LAN address typed
  /// once and forgotten fails exactly like a server that was never started, so
  /// the route into Settings is worth offering even where `ollama serve` is the
  /// likelier remedy (T-0102).
  @override
  bool get endpointIsUserSet => true;

  /// How long the call was given, or null when it failed rather than stalled.
  final Duration? waited;

  /// The socket's own reason, kept off [message] for the same rule the cloud
  /// bodies follow. Measured on Windows: `http.ClientException.message` is
  /// short and useful (`Failed host lookup: '...'`) but comes back in the OS
  /// display language, so it can never be the sentence a user is expected to
  /// read.
  final String reason;

  /// The shell's half of the stall sentence, or null where the shell has no
  /// control to name (T-0152).
  final String? stallRemedy;

  /// Said first, because this is the sentence a downloaded build fails on and
  /// the reader has no way to tell the two apart (T-0453). Ollama is not
  /// bundled with anything here and never has been -- not with the app, not
  /// with the CLI -- so on a machine that has only just unzipped one, nothing
  /// answering at the default address is the expected state rather than a
  /// broken install. Naming which of the two programs is missing is the whole
  /// of the difference between "this needs a separate download" and "what I
  /// downloaded does not work".
  ///
  /// It does not say how to install it: the address may be another machine
  /// (the phone case, and the LAN case on the desktop), and an instruction to
  /// install something *here* would be wrong in exactly the case the next
  /// sentence covers. Where the shell knows it is talking about this machine
  /// it says so on its own screen instead -- the app's Settings note.
  static const _separateProgram =
      'Ollama is a separate program and shelfscan does not include or install '
      'it.';

  @override
  String get message => waited == null
      ? 'Cannot reach Ollama at $baseUrl -- nothing answered there. '
          '$_separateProgram Start the '
          'server with: ollama serve. If that address is another machine, check '
          'it is right and reachable from here. $_outwardCheck ($reason)'
      : timedOutMessage(
          service: 'Ollama',
          endpoint: baseUrl,
          waited: waited!,
          advice: _stalledOllama,
          remedy: stallRemedy,
        );
}

/// The outward check the other three families carry (T-0354, T-0355), with
/// both of its arguments decided here rather than carried across (T-0357).
///
/// `the scan` is the same stage `vision.dart` names -- this provider does that
/// work. The second half is not the same, and it is the half that must not be
/// copied: a host out on the internet can be cut off by this machine being
/// offline or by a proxy, and none of that describes an address on this
/// machine or the next desk. A proxy or a firewall between a machine and
/// itself is a rarer story than one between a machine and the internet, so
/// what a browser refused at a local address actually leaves is that nothing
/// is listening there.
///
/// **Why the check is added to a family whose remedy already looks complete.**
/// It is worth more here than anywhere else: a local address either answers or
/// does not, with no route in between to take the blame, so the browser
/// settles it outright. `even an error page` is a broadening rather than a
/// correction in this one case -- an Ollama root answers a GET with friendly
/// text, and the clause only says that an unfriendly answer would count too.
///
/// It does not repeat `ollama serve`, which the sentence has already named:
/// what it adds is the way to find out whether starting the server is the
/// remedy at all.
final _outwardCheck = checkOutsideThisApp(
  stage: 'the scan',
  usually: 'nothing listening on that port, or, for an address on another '
      'machine, a firewall or a server there that only listens to itself',
);

/// Why this one does not repeat `ollama serve`: a server that is not running
/// refuses the connection and is the message above. This is a server that IS
/// running and is not answering, and the two remedies are not the same one.
///
/// It ends on the diagnosis and never on a control: "legitimately takes
/// minutes" is the case a longer budget serves, but only a shell knows whether
/// its user can set one (T-0152), so the next clause is [stallRemedy]'s.
const _stalledOllama =
    'A model runner that has wedged stalls exactly like this. qwen2.5vl:7b '
    'answers a 4000x3000 photo in about 25 s when it is healthy, so check the '
    'server is alive (ollama ps) before assuming the model is merely slow -- '
    'though a model too large for the machine is the one case measured here '
    'that legitimately takes minutes.';

/// The statuses worth another attempt: Ollama's own overload answer, and the
/// three a crashed or dying model runner comes back with (doc/measurements.md
/// records `qwen2.5vl:32b` losing a whole photo to a retried 500 for want of
/// VRAM).
const _retryableStatuses = {429, 500, 502, 503};

/// The exception for a non-2xx answer from Ollama.
///
/// **Only 404 blames something the user set** (T-0169), and both of its
/// branches do: the model that is not pulled is the model id they typed, and
/// the address that is not an Ollama root is the URL they typed. 400 is about
/// the photo the server could not decode, and every other status is the bare
/// "refused the request" line that names nothing at all -- including 401 and
/// 403, which a keyless server has no vocabulary for and which the app used to
/// offer the route for on the cloud allowlist alone.
Exception ollamaFailure({
  required String baseUrl,
  required String model,
  required int statusCode,
  required String body,
}) =>
    visionFailure(
      message: ollamaFailureMessage(
          baseUrl: baseUrl,
          model: model,
          statusCode: statusCode,
          body: body),
      statusCode: statusCode,
      body: body,
      retryable: _retryableStatuses.contains(statusCode),
      causeIsUserSet: statusCode == 404,
    );

/// What [statusCode] means for the person running a local server.
///
/// Deliberately NOT a translation of [visionApiMessage] (T-0097). The cloud
/// vocabulary is built around a key and a model id typed into a settings
/// field; here there is no key at all, the two things that actually break are
/// a server that was never started and a model that was never pulled, and both
/// have a one-line remedy worth naming. Only 400 and the retryable statuses
/// mean anything close to the same thing on both sides.
///
/// Bodies measured against the local server, Ollama 0.32.9, 2026-08-15, one
/// call each:
///   - 404, model not pulled: `{"error":"model 'x' not found"}` -- it echoes
///     the model back, which is what tells this apart from the case below.
///   - 404, address that is not an Ollama root: `404 page not found`, plain
///     text, from Ollama's own router with [_chatPath] appended to it.
///   - 400, 8 bytes of fake JPEG: a whole JSON document encoded as a STRING
///     inside `error`, unwrapped by [providerDetail], leaving `Failed to load
///     image or audio file`. That is the HEIC case T-0025/T-0031 measured and
///     it is about the photo, not the model.
///   - 400, malformed request: `{"error":"json: cannot unmarshal string into
///     Go struct field ChatRequest.messages of type []api.Message"}`.
/// Nothing here echoes a credential the way an OpenAI 401 body does (T-0072),
/// because a keyless server has none to echo -- the quoting caution that rule
/// came from still applies to every branch, which is why the body is quoted
/// through [providerDetail] and never appended whole.
String ollamaFailureMessage({
  required String baseUrl,
  required String model,
  required int statusCode,
  required String body,
}) {
  final detail = providerDetail(body);
  final said = detail == null ? '' : ' Ollama said: $detail';
  final serverSaid = detail == null ? '' : ' The server said: $detail';
  return switch (statusCode) {
    404 when model.isNotEmpty && body.contains(model) =>
      'Ollama at $baseUrl has no model "$model" (HTTP 404) -- it is not '
          'pulled on that server. Pull it with: ollama pull $model.$said',
    404 => 'Ollama at $baseUrl answered HTTP 404 for $_chatPath, so nothing '
        'at that address is serving the Ollama API. Check the URL -- it is '
        'the server\'s root, with no path after the port.$serverSaid',
    400 => 'Ollama rejected the request for model "$model" (HTTP 400) -- the '
        'request itself, not the model id. A photo it could not decode is '
        'the commonest cause.$said',
    429 => 'Ollama at $baseUrl is refusing new requests as too many (HTTP '
        '429) and the retries did not clear it. Wait, or scan fewer photos '
        'at once.$said',
    >= 500 => 'Ollama failed on its side for model "$model" (HTTP '
        '$statusCode) and the retries did not clear it. A model runner that '
        'dies mid-photo answers exactly like this; the one case measured here '
        'was a model too large for the machine\'s VRAM.$said',
    _ => 'Ollama at $baseUrl refused the request for model "$model" (HTTP '
        '$statusCode).$said',
  };
}
