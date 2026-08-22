/// Vision provider for any endpoint speaking the OpenAI `/chat/completions`
/// shape with `image_url` content parts.
///
/// One class for the whole family on purpose (T-0006): Groq, OpenRouter,
/// Mistral, GitHub Models, Cerebras and Gemini's compatibility endpoint
/// differ only in base URL, model name and key, so six sibling classes would
/// be the same code six times. Anything that would need vendor branching in
/// here belongs in a provider of its own instead --
/// [AnthropicVisionProvider] is exactly that case, native Messages API.
///
/// Privacy (decision 0011): these are photographs of a private home, and free
/// tiers are commonly funded by training on what is submitted to them. This
/// provider is never a default anywhere; every caller selects it explicitly
/// and warns at the point of selection.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_timeout.dart';
import 'vision.dart';

/// Any fixed value would do; this one is the date the local provider's seed was
/// chosen (T-0053), reused so a local and a cloud run of the same photo differ
/// in the model rather than in the sampling.
const _defaultSeed = 20260814;

/// The output cap, under whichever name the endpoint takes (see [_adjustable]).
///
/// A cap, not a reservation: only generated tokens are billed. Measured live
/// against api.openai.com on `CONTROL-HIRES` `shelf-1.jpg`, 2026-08-15 --
/// `gpt-5.6-terra` answered in 2553 completion tokens of which **842 were
/// reasoning**, and `gpt-5.4-mini` answered `shelf-2.jpg` in 976 with 0. So a
/// reasoning model spent a third of its answer before it wrote a character,
/// and 4096 cleared the worst case measured then by 1.6x.
///
/// **4096 was inside the distribution, not above it (T-0120, 2026-08-16.)**
/// The same photo, `shelf-1.jpg`, through `gpt-5.5`, four live runs:
/// completion 3046 (1536 reasoning, `finish_reason: stop`), 4093 uncapped, and
/// **4096 twice with `finish_reason: length` and an empty `content`** -- the
/// model spent the whole budget reasoning and wrote nothing. Two photographs
/// of three were lost that way, as a bare `FormatException` on runs where the
/// request shape was already correct; since T-0111 that photo fails with a
/// sentence naming this cap instead. Reasoning spend is where the
/// variance lives, so the cap has to clear the tail rather than the mean:
/// 8192 is 2x the largest completed answer anyone here has measured.
///
/// Raising it is not a cost decision -- a cap is not a reservation, only
/// generated tokens are billed, and the four runs above show the model
/// stopping on its own well under either value. It is bounded by what the
/// model will accept: a cap above a model's own ceiling is refused outright,
/// this repository can reach one endpoint of the seven (T-0089), and such a
/// refusal now degrades to dropping the cap with a note rather than silently.
const _maxOutputTokens = 8192;

/// The fields this provider sends that a request can do without.
///
/// `model`, `messages` and the image are the request; everything here is a
/// preference, so an endpoint that refuses one of these can be obeyed rather
/// than argued with (see [_learnFrom]). A list of our own optional fields, not
/// a list of anyone's models -- that is the whole point of it.
const _adjustable = {
  'max_tokens',
  'max_completion_tokens',
  'temperature',
  'seed',
};

/// ## The request shape is learned from the endpoint, not from a table (T-0089)
///
/// This class used to send `max_tokens: 4096` unconditionally, and **every
/// GPT-5 model rejects that field** with HTTP 400 `Unsupported parameter:
/// 'max_tokens' is not supported with this model. Use 'max_completion_tokens'
/// instead.` -- so the provider was pinned to the previous generation on the
/// only endpoint this project has a key for. The same 400 arrives for
/// `temperature`, and that one is worse: measured live against api.openai.com
/// on 2026-08-15, `temperature: 0` is **refused by `gpt-5`, `gpt-5-mini`,
/// `gpt-5.5` and all three `gpt-5.6` models, and accepted by `gpt-5.1`,
/// `gpt-5.2`, `gpt-5.4`, `gpt-5.4-mini` and `gpt-5.4-nano`**. Acceptance is
/// not monotonic in the version number, so no table keyed on a model id or a
/// family prefix could be written correctly even for one day, let alone kept
/// correct -- which is the objection T-0067 made a priori for the Anthropic
/// side, here with the counter-example measured.
///
/// The rule instead: **send the shape this project wants; when a 400 names one
/// of [_adjustable], obey the endpoint and remember it for the rest of the
/// run.** It keys on what the authority said rather than on a snapshot of what
/// the authority was, so it cannot go stale, and it covers refusals nobody has
/// heard of yet -- the next incompatibility will not be this one.
///
/// **`max_tokens` is sent first on purpose.** Both orders work on OpenAI, but
/// the failure directions are not symmetric across the six other vendors this
/// one class points at: an endpoint that has not adopted the rename either
/// rejects `max_completion_tokens` loudly, in which case the rule handles it,
/// or **ignores an unknown field silently**, in which case the request has no
/// output cap and nothing ever says so. Starting from the field every endpoint
/// in this family has always taken means the only way to be wrong is the loud
/// one (decision 0012: a silent failure is worse than a loud one).
///
/// **What a correction costs**: one 400 per photo in flight, once per
/// correction per provider. The endpoint validates parameters before it looks
/// at the image, so the call is free in tokens; it is not free in the upload,
/// which is the whole photograph. Measured: 1.9 s for the refused call against
/// 6.8-25 s for the accepted one. On `gpt-5.5` at `visionConcurrency` 3 that
/// is two refusals for each of the first three photos and none afterwards; on
/// `gpt-4.1-mini` there are none at all, and that path is byte-for-byte the
/// request T-0090 measured.
///
/// Each attempt carries its own [timeout], so a corrected photo can cost up to
/// three budgets rather than one -- which does not re-open the hang T-0104
/// bounded, because a refusal is only ever reached by an endpoint that has
/// just answered in under two seconds.
///
/// ## The learned shape belongs to the endpoint, not to one call (T-0120)
///
/// One provider serves the whole vision stage, so at `visionConcurrency` 3 the
/// first three photos are in flight before any of them has learned anything
/// and every one of them gets the same 400 back. Judging that 400 against the
/// shape the provider holds *now*, rather than against the shape that call
/// actually sent, cost two photographs of three. Measured on the
/// scripted `gpt-5.5` sequence, three photos, before this task:
///
/// - all three send `{max_tokens, temperature, seed}`, all three are refused
///   `max_tokens`;
/// - the first records the rename and re-sends;
/// - the second re-reads its own 400 against the corrected shape, where
///   `max_tokens` no longer appears, matches the only field of [_adjustable]
///   left in both the message and that shape -- `max_completion_tokens` --
///   and records the endpoint as refusing the replacement it had just been
///   given. **The output cap is dropped from every later request with nothing
///   said**, which is the silent failure the send order exists to avoid;
/// - the third finds nothing it sent that it may adjust and dies as a real
///   400, and so does one of the two retries at the `temperature` step.
///
/// One photo of three, `refusedParameters` reading
/// `{max_tokens: max_completion_tokens, max_completion_tokens: null,
/// temperature: null}`, and the survivor sent uncapped. At concurrency 1 the
/// same script is clean -- two corrections, five calls, three photos -- which
/// is why the CLI never showed it.
///
/// **The rule.** A 400 is read against the fields that request carried, and a
/// correction another call has already made is not a failure of this one: the
/// call re-sends under the shape that is now known, silently, because the
/// endpoint has already been obeyed and told about once. A call fails only
/// when its own 400 names nothing it sent that this provider may adjust and no
/// correction landed while it was in flight.
///
/// **What it costs, and what the alternative cost.** Nothing is serialised, so
/// each photo in the first wave still pays its own refusals -- three uploads
/// per correction at concurrency 3, overlapped, ~1.9 s each. Holding the other
/// calls until the first has a shape known to be accepted would save those
/// uploads, but "accepted" is only knowable from a completed vision call
/// (6.8-51 s), so it would add that wait to every run of every model,
/// including the ones that are never refused anything. Bytes in the rare case
/// against latency in all of them.
///
/// No lock: one isolate runs all of this, so the hazard is interleaving at the
/// `await` in [analyze] and not a data race, and [_refused] only ever grows.
class OpenAiCompatibleVisionProvider implements VisionProvider {
  /// Sampling is stated rather than inherited (T-0057), following
  /// [OllamaVisionProvider] and T-0053. This shape takes both knobs, so unlike
  /// [AnthropicVisionProvider] repeatability is at least *expressible* here --
  /// and only expressible. `seed` is best-effort by definition in the OpenAI
  /// shape, and this one class points at Groq, OpenRouter, Mistral, GitHub
  /// Models, Cerebras and Gemini's compatibility endpoint: six implementations
  /// of the field with no shared guarantee behind it. **Not one of those six
  /// has ever been called from this repository** -- api.openai.com is the only
  /// endpoint this shape has been measured against (T-0090, T-0089), and there
  /// the seed is best-effort in practice as well as in the documentation: the
  /// same photograph gives a stable `items` array and an unstable `unreadable`
  /// one across repeats. Until the recipe on [AnthropicVisionProvider] has been
  /// run against the endpoint you are actually using, "repeatable" here means
  /// "asked for", not "shown".
  ///
  /// [temperature] 0 carries the argument stated on [AnthropicVisionProvider]:
  /// every rule in [detectionPromptRules] was measured under near-greedy
  /// decoding on a LOCAL 7B, and at 0.8 that model invented titles and echoed
  /// the [detectionJsonSchema] example text as a `platform_hint` value. What a
  /// cloud model does at either temperature is unmeasured.
  ///
  /// [seed] is inert while [temperature] is 0 on any endpoint that decodes
  /// greedily -- which is exactly the first thing worth testing, because an
  /// endpoint that answers differently across seeds at temperature 0 is
  /// telling you its 0 is not greedy.
  ///
  /// Both are nullable so an endpoint that rejects a field it does not know is
  /// one `null` away from working rather than one fork away. A null is a run
  /// at that endpoint's own undisclosed default -- the state this task exists
  /// to end -- so say so in the run notes when you use it.
  ///
  /// [onRequestAdjusted] is told, once per correction, whenever the endpoint
  /// refuses one of [_adjustable] and this class obeys it (T-0089). A shell
  /// that ignores it runs at a sampling nobody stated, which is the one thing
  /// this provider is not allowed to do quietly.
  OpenAiCompatibleVisionProvider({
    required String baseUrl,
    required this.model,
    required this.apiKey,
    this.temperature = 0,
    this.seed = _defaultSeed,
    this.timeout = visionCallTimeout,
    this.stallRemedy,
    this.onRequestAdjusted,
    http.Client? client,
  })  : baseUrl = _trimSlashes(baseUrl),
        _client = client;

  /// Everything up to and including the version segment, e.g.
  /// `https://api.groq.com/openai/v1`. Vendors document it with and without
  /// a trailing slash, so both forms are accepted.
  final String baseUrl;
  final String model;
  final String apiKey;
  final double? temperature;
  final int? seed;

  /// See [visionCallTimeout] for what the default rests on.
  final Duration timeout;

  /// What a shell that can change [timeout] tells the user to do about a stall
  /// (T-0152). Null on a shell that cannot, which is the app.
  final String? stallRemedy;

  /// Told what this endpoint refused and what was sent instead.
  final void Function(String note)? onRequestAdjusted;

  final http.Client? _client;

  /// What this endpoint has refused so far: the field it named, mapped to the
  /// replacement name it gave, or null when it named none and the field is
  /// dropped. Learned from its own 400s, kept for the life of this provider so
  /// the correction is paid for once.
  final Map<String, String?> _refused = {};

  /// What the endpoint has been observed to refuse, for a shell that wants to
  /// report the shape a run actually used.
  Map<String, String?> get refusedParameters => Map.unmodifiable(_refused);

  static String _trimSlashes(String url) {
    var end = url.length;
    while (end > 0 && url[end - 1] == '/') {
      end--;
    }
    return url.substring(0, end);
  }

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    while (true) {
      // Both snapshots are of the request about to go out, and both are read
      // again only after it has answered: in between, other photos correct the
      // shape (T-0120).
      final shape = _preferences();
      final knownBefore = _refused.length;
      final response = await _post(photo, shape);
      if (response.statusCode == 400) {
        final note = _learnFrom(response.body, shape.keys.toSet());
        if (note != null) {
          onRequestAdjusted?.call(note);
          continue;
        }
        // Terminates: a retry here needs a correction that was not there when
        // this request left, [_refused] never shrinks, and [_adjustable] is
        // four fields long.
        if (_refused.length != knownBefore) continue;
      }
      return _read(response, photo, shape);
    }
  }

  /// The [_adjustable] half of the request, under the names this endpoint has
  /// been found to accept.
  Map<String, Object?> _preferences() {
    final fields = <String, Object?>{
      'max_tokens': _maxOutputTokens,
      if (temperature != null) 'temperature': temperature,
      if (seed != null) 'seed': seed,
    };
    for (final MapEntry(key: refused, value: replacement) in _refused.entries) {
      final value = fields.remove(refused);
      if (value != null && replacement != null) fields[replacement] = value;
    }
    return fields;
  }

  Map<String, Object?> _requestBody(
          PhotoInput photo, Map<String, Object?> preferences) =>
      {
        'model': model,
        ...preferences,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': detectionPrompt},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${photo.mimeType ?? 'image/jpeg'};base64,'
                      '${base64Encode(photo.bytes)}',
                },
              },
            ],
          }
        ],
        // No `response_format: json_object`: support for it varies across this
        // family, and asking for it is what would force the vendor branching
        // this one class exists to avoid. Fences are handled on the parse side
        // for every provider anyway (T-0013).
      };

  Future<http.Response> _post(
      PhotoInput photo, Map<String, Object?> preferences) async {
    try {
      return await boundedPost(
        (client) => client.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode(_requestBody(photo, preferences)),
        ),
        reusing: _client,
        within: timeout,
        onTimeout: (waited) => VisionUnreachableException.timedOut(
          service: 'the endpoint',
          endpoint: baseUrl,
          endpointIsUserSet: true,
          waited: waited,
          stallRemedy: stallRemedy,
        ),
      );
    } on http.ClientException catch (e) {
      throw VisionUnreachableException(
        e,
        service: 'the endpoint',
        // [baseUrl], not the /chat/completions URL the request went to: the
        // base URL is the string the user typed and the one they can fix.
        endpoint: baseUrl,
        endpointIsUserSet: true,
      );
    }
  }

  /// [sent] is the shape this response answered, for the same reason
  /// [_learnFrom] takes it: the cap named in a truncation message has to be the
  /// one that request carried, and a concurrent photo may have moved the
  /// provider's since (T-0120).
  PhotoAnalysis _read(
      http.Response response, PhotoInput photo, Map<String, Object?> sent) {
    final status = response.statusCode;
    if (status != 200) {
      throw visionApiFailure(
        service: baseUrl,
        model: model,
        statusCode: status,
        body: response.body,
        retryable: status == 429 || status >= 500,
      );
    }

    final choices = (jsonDecode(response.body) as Map<String, dynamic>)
        ['choices'] as List<dynamic>?;
    // An absent or empty `choices` is a 200 that carries no answer like any
    // other, and reaching `.first` for it threw a bare StateError (T-0142).
    final choice = choices == null || choices.isEmpty
        ? const <String, dynamic>{}
        : choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>?;
    final text = message?['content'] as String?;
    // Read before the content, because T-0120 measured the truncation that
    // arrives with `content` EMPTY -- the whole budget spent on reasoning
    // tokens, 4096 of them, twice in four runs of one photo. A cast of that to
    // String is the one thing this branch must beat (T-0111).
    if (choice['finish_reason'] == 'length') {
      throw visionTruncatedFailure(
        service: baseUrl,
        model: model,
        cap: _capIn(sent),
        answer: text ?? '',
        body: response.body,
      );
    }
    // `content` is documented null for a refusal, for a tool-only answer and
    // for `finish_reason: content_filter`; casting it `as String` named a Dart
    // type and nothing about the run (T-0142).
    if (text == null || text.trim().isEmpty) {
      throw visionEmptyAnswerFailure(
        service: baseUrl,
        model: model,
        reason: choice['finish_reason']?.toString(),
        refusal: message?['refusal']?.toString(),
        body: response.body,
      );
    }
    return parsePhotoAnalysisAnswer(text, photo.name,
        service: baseUrl, model: model);
  }

  /// The output cap in a request shape, or null when nothing in it carries one.
  ///
  /// By exclusion rather than by name: the cap travels under whatever name the
  /// endpoint offered instead of `max_tokens` (T-0089), and the other two
  /// fields [_preferences] can build are the two named here.
  static int? _capIn(Map<String, Object?> sent) {
    for (final MapEntry(:key, :value) in sent.entries) {
      if (key != 'temperature' && key != 'seed') return value as int?;
    }
    return null;
  }

  /// Reads a 400 for a field this request sent that this endpoint will not
  /// take, records the correction, and returns the sentence describing it --
  /// or null when there is nothing new to learn, which is either a 400 about
  /// something else or one another call has already answered. [analyze] tells
  /// those two apart.
  ///
  /// [sent] is the shape of the request that drew this 400, passed in rather
  /// than recomputed: recomputing reads a shape that concurrent photos may
  /// have moved, and a 400 matched against a shape that request never carried
  /// is how the endpoint came to be recorded as refusing its own replacement
  /// (T-0120).
  ///
  /// Every branch here terminates: a correction is recorded only for a field
  /// the request just carried, a field is corrected at most once, and a
  /// replacement that has already been refused degrades to dropping the field.
  String? _learnFrom(String body, Set<String> sent) {
    final error = _errorObject(body);
    if (error == null) return null;
    final message = error['message'] as String? ?? '';

    // `param` is the endpoint's own structured answer and is believed first;
    // the message scan is for the vendors in this family that answer with
    // prose and no `param` at all.
    final named = error['param'] as String?;
    final field = _adjustable.contains(named) && sent.contains(named)
        ? named!
        : _adjustable.firstWhere(
            (f) => sent.contains(f) && message.contains("'$f'"),
            orElse: () => '');
    if (field.isEmpty || _refused.containsKey(field)) return null;

    final offered =
        RegExp("[Uu]se '([A-Za-z0-9_]+)' instead").firstMatch(message);
    var replacement = offered?.group(1);
    if (replacement == field || _refused.containsKey(replacement)) {
      replacement = null;
    }
    _refused[field] = replacement;
    return _adjustmentNote(field, replacement, message);
  }

  static Map<String, dynamic>? _errorObject(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final error = decoded['error'];
    return error is Map<String, dynamic> ? error : null;
  }

  /// The field whose refusal ended the output cap, or null while a cap is still
  /// going out under some name.
  ///
  /// The cap has two names and the consequence belongs to neither of them: it
  /// belongs to the state "nothing carries the cap any more" (T-0139). The cap
  /// leaves as `max_tokens` and moves to whatever name the endpoint offered
  /// instead, so this walks that chain -- a refusal that renamed it kept it, and
  /// only the refusal that ends the chain loses it. Keying on the field name
  /// alone would miss T-0120's state, where the name that goes uncapped is
  /// `max_completion_tokens`, the replacement.
  ///
  /// Terminates: a replacement already in [_refused] is discarded in
  /// [_learnFrom], so the chain never revisits a name.
  String? _droppedCapField() {
    var field = 'max_tokens';
    while (_refused[field] != null) {
      field = _refused[field]!;
    }
    return _refused.containsKey(field) ? field : null;
  }

  String _adjustmentNote(String field, String? replacement, String said) {
    final what = replacement == null
        ? 'without it'
        : 'under the name it gave instead, "$replacement"';
    final consequence = switch (field) {
      // The one drop that changes what was measured rather than only what was
      // asked for, so it does not get to be a footnote (doc/measurements.md: a
      // prompt measured at another temperature is a measurement of a different
      // system).
      'temperature' when replacement == null =>
        ' Sampling for the rest of this run is this endpoint\'s own, not '
            'temperature $temperature -- record that with any numbers taken '
            'from it.',
      'seed' when replacement == null =>
        ' Repeats are no longer even asked to be repeatable on this endpoint.',
      // The one drop that costs money. T-0089's send order exists to keep a run
      // from reaching this state silently, and the note is the last thing
      // between the user and it.
      _ when field == _droppedCapField() =>
        ' Nothing caps what this endpoint may generate for the rest of this '
            'run -- on a reasoning model that is unbounded output, and '
            'unbounded billing with it.',
      _ => '',
    };
    return '$baseUrl will not take "$field" for model "$model". That photo was '
        're-sent $what, and the rest of this run follows. It said: $said'
        '$consequence';
  }
}
