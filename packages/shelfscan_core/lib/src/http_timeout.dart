/// The one place an outbound request in this package is bounded (T-0104).
///
/// Nothing here used to set a timeout at all, and `package:http` sets none of
/// its own: measured on loopback, package:http 1.6.0, a `ServerSocket` that
/// accepts the connection and never writes a byte leaves `Client.post` pending
/// for as long as anyone waits. The CLI sat at `vision` and the app at
/// `Scanning` with no warning, no summary line and no failure -- the silent
/// class decision 0012 names.
///
/// Two measurements shaped this file rather than the value in it.
///
/// **The bound goes on `post()`, not on a `BaseClient.send()` wrapper.** One
/// wrapper in one place was the tidier design and it does not work:
/// `Client.post` is `Response.fromStream(await send(request))`, so `send`
/// returns the moment the headers arrive and the body is read afterwards.
/// Against a loopback server that writes a complete header block with a
/// `content-length` and then nothing (200 ms, then silence), a 3 s bound on
/// `send()` never fired and the call was still pending when an 8 s cap ended
/// the probe; the same bound on `post()` fired at 3.00 s. A stalled endpoint
/// that has already answered `HTTP/1.1 200 OK` is exactly what a proxy or a
/// half-dead model runner produces, so that is not the rare half of the case.
///
/// **A timeout alone does not end the process, and that is the same defect
/// again.** `Future.timeout` abandons the wait, not the socket, and a pending
/// connection keeps the Dart VM alive: a child process that caught its
/// timeout and returned from `main` at 11 ms was still running when the
/// measurement was cut off at 146 s. Only `Client.close()` releases it -- the
/// same child, closing, exited 0. So [boundedPost] owns the client for the
/// duration of one call and closes it, and the CLI's partial-failure path
/// (one photo stalls, two are read, the review file is written, `main`
/// returns without `exit`) ends at the prompt instead of hanging there.
///
/// The client is per call rather than per provider because closing is the only
/// lever and it is not selective. Measured on the same loopback socket: three
/// concurrent posts on one client, closed after 2 s, all three came back
/// `ClientException: Connection closed before full header was received`, and a
/// fourth started after the close got `Client is already closed`. Vision runs
/// at `visionConcurrency` 3 and resolve at 4, so releasing one stalled photo's
/// socket on a shared client would kill the photos in flight beside it and
/// report them under the wrong sentence. The price is connection reuse: one
/// extra handshake per call, against a vision read measured at 25-35 s
/// (nothing), and against an IGDB search measured in milliseconds -- unmeasured
/// there, because those credentials are the user's (BYOK, decision 0011),
/// though that run's wall clock is floor-bound by the 4 rps limiter -- nearly
/// all of it -- rather than by per-request latency.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// What one vision call is given before it is called stalled.
///
/// 120 s is ~3.5x the slowest legitimate vision read this project has ever
/// measured -- 34.5 s for one 4000x3000 photo against `gpt-4.1-mini` (T-0090)
/// -- and ~5x the local `qwen2.5vl:7b` read of the same photo (~25 s; its
/// three-photo scans run 55-84 s at `visionConcurrency` 1). It is not a
/// round number pulled from the air and it is not the tightest defensible one
/// either: the bound has to be loose enough that a slow answer is never called
/// a stall, and the failure it exists to end costs the user nothing but time
/// once it is bounded at all.
///
/// The ceiling is the other half. A three-photo local scan sends its photos one
/// at a time, so a wedged server is reported after 3 x 120 s = 6 minutes; the
/// point of a bound is lost if the report arrives long enough after the hang to
/// be mistaken for one.
///
/// One measured configuration this aborts, and it is not a guess: `qwen2.5vl:32b`
/// on this hardware took 727 s for two photos (~360 s each) because 29 GB of
/// weights and context do not fit in 24 GB of VRAM. doc/measurements.md
/// measured that model and rejected it -- the same run lost a third photo
/// to a retried 500 -- but a user who points `SHELFSCAN_OLLAMA_MODEL` at
/// something that large gets this timeout rather than an answer. Each
/// provider takes the value as a constructor parameter for exactly that case,
/// and the CLI is the shell that exposes it (T-0108); the app does not, which
/// is why [timedOutMessage] takes the remedy from the shell rather than
/// naming a control here.
///
/// **A dense photo is not a second such configuration, and that was measured
/// rather than assumed (T-0278).** Past a density ceiling `qwen2.5vl:7b`
/// repeats itself under greedy decoding until the server's context window is
/// full, so the extra minutes a raised bound buys contain no title the first
/// seconds had not already produced -- on the synthetic frame that reproduces
/// it, 27,836 generated tokens carry 20 distinct titles and 29 copies of them.
/// A user who raises this for that photo waits longer for the same nothing.
///
/// Two numbers from the same measurement, for anyone tempted to tune this:
/// the densest frame that still answers honestly generates ~5,500 tokens, and
/// generation on one machine ran 24-28 tokens/s with another process busy
/// against 91-102 tokens/s quiet. So this bound admits ~3,000 tokens or
/// ~12,000 depending on what else is running, which is a four-fold spread no
/// single value tunes -- the argument for leaving it where it is and telling
/// the user about the shelf instead. doc/measurements.md, "The 7B's density
/// ceiling".
const visionCallTimeout = Duration(seconds: 120);

/// What one IGDB request is given.
///
/// Two orders of magnitude above the measurement rather than three-and-a-half,
/// because this path has no slow-model case in it: a search answers in
/// milliseconds, and T-0064's live runs put one search per row inside a wall
/// clock the client's own 4 rps limiter accounts for nearly all of.
/// Nothing legitimate here takes seconds, so a tight bound costs nothing and
/// catches a stall while the run is still worth saving.
const igdbCallTimeout = Duration(seconds: 20);

/// Sends one request under [within] and leaves no connection behind it.
///
/// [reusing] is the client the caller was given, or null when it makes its own
/// -- an injected client belongs to whoever injected it and is never closed
/// here. See the library comment for why the owned one is per call.
Future<http.Response> boundedPost(
  Future<http.Response> Function(http.Client client) post, {
  required http.Client? reusing,
  required Duration within,
  required Exception Function(Duration waited) onTimeout,
}) async {
  final client = reusing ?? http.Client();
  try {
    return await post(client)
        .timeout(within, onTimeout: () => throw onTimeout(within));
  } finally {
    if (reusing == null) client.close();
  }
}

/// The one sentence frame for a request that ran out of time.
///
/// Shared for the reason `detectionPromptRules` is: the three paths that say
/// this each carry their own [advice] and would otherwise carry their own
/// version of the frame too (T-0105 is that drift, already realised once).
///
/// "not even a refusal" is the clause that keeps this apart from T-0097's and
/// T-0103's sentences, which are what an endpoint that refuses or does not
/// resolve says. It is also the honest limit of what one bound can know: a
/// connection that never completed the handshake and a connection that
/// completed and went quiet arrive here identically, and separating them needs
/// a connect timeout, which needs `dart:io` (see the library comment on
/// `vision.dart`'s [VisionUnreachableException] and ARCHITECTURE.md's
/// boundary). So this sentence claims only that nothing came back -- never
/// that the endpoint accepted anything.
///
/// [advice] is the diagnosis, which this package measured and owns; [remedy] is
/// the shell's, and is null on every caller that has no control to name
/// (T-0152). Joining the two here rather than at the three call sites is what
/// keeps "diagnosis, then remedy" true of all of them at once, and leaves each
/// provider passing a value rather than composing a sentence.
String timedOutMessage({
  required String service,
  required String endpoint,
  required Duration waited,
  required String advice,
  String? remedy,
}) =>
    'Timed out after ${waited.inSeconds} s waiting for $service at $endpoint '
    '-- nothing came back, not even a refusal. $advice'
    '${remedy == null ? '' : ' $remedy'}';
