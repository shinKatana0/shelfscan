/// Vision backend policy and wiring for the app.
///
/// Platform policy (product decision, not a technical constraint):
///   - Windows: user chooses local (Ollama) or a cloud endpoint.
///     Default: LOCAL -- a desktop next to the shelf can run its own model.
///   - Android: CLOUD ONLY. On-device models are too weak for spine OCR,
///     and pointing the phone at a home Ollama server is deferred
///     (revisit later as a backlog item if requested).
///   - "Cloud" is a choice of endpoint (T-0006): Anthropic's own API, or
///     any OpenAI-compatible one the user names. Neither is ever the
///     default where a local model can run, and both carry a privacy
///     warning wherever they can be selected -- differently worded, because
///     only the named-endpoint one risks a free tier training on what is
///     submitted to it. Screens render [BackendCheck.warning] and
///     [BackendCheck.advice]; the wording of both is here (T-0058, T-0070),
///     and the advice is the half that has to know which platform it is on.
///   - ONE control chooses it: the scan screen's switch, which answers with
///     [BackendCheck] at the tap and persists (T-0040, T-0076). The settings
///     screen had a second copy of the same button over the same stored
///     value, staged until Save -- so one preference had two meanings of a
///     tap, and the copy that could not state a blocker without telling the
///     reader to go to Settings from inside Settings was the one that went
///     (T-0115). Settings configures every backend and selects none.
///   - ONE reader per photo. `VisionWorker` takes an optional second one
///     and the app never supplies it (T-0061); the CLI's `--fallback`
///     does, and the CLI is the validation harness (ARCHITECTURE.md). It
///     was measured once, qwen2.5vl:7b primary + gemma3:12b second on the
///     three 4000x3000 control photos: 15 added rows for twice the wall
///     clock, and every one of them wrong -- most of them re-readings of
///     spines the primary had already read correctly, kept apart by one
///     character, the rest invented or welded out of two spines (T-0032).
///     An ANTHROPIC
///     second reader,
///     which is the only one this app could ever have built, is unmeasured
///     -- no cloud key was available -- and would cost two
///     calls per photo and upload every photo of a private home for a
///     merge whose one measurement lost. A user who wants Anthropic to
///     read the shelf selects it as the primary above: same upload, half
///     the calls, and a warning already attached.
///
/// Keep this the single place that knows the policy; screens ask it.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shelfscan_core/shelfscan_core.dart';

/// The app's Ollama defaults are the provider's, not a second pair that has to
/// agree with them (T-0087). Re-exported so the settings screen's `hintText` --
/// which since T-0082 is what a cleared field resolves to -- reaches them
/// through this file like every other piece of provider policy.
export 'package:shelfscan_core/shelfscan_core.dart'
    show defaultOllamaModel, defaultOllamaUrl;

enum VisionBackend { local, cloud, openAiCompatible }

/// Deliberately no default endpoint and no default model: a base URL the
/// app picked for the user would be an external service the user never
/// chose, which is exactly what the privacy decision forbids (decision 0011).
/// The hint text on the settings screen names examples instead.
const openAiEndpointExamples = 'e.g. https://api.groq.com/openai/v1, '
    'https://openrouter.ai/api/v1, '
    'https://generativelanguage.googleapis.com/v1beta/openai';

/// User-editable settings, edited on the settings screen and persisted by
/// `SettingsStore` (secrets in the OS keychain, the rest in preferences).
class ProviderSettings {
  ProviderSettings({
    VisionBackend? backend,
    this.anthropicApiKey = '',
    this.anthropicModel = '',
    String? ollamaUrl,
    String? ollamaModel,
    this.openAiBaseUrl = '',
    this.openAiModel = '',
    this.openAiApiKey = '',
    this.igdbClientId = '',
    this.igdbClientSecret = '',
  }) : backend = backend ?? ProviderPolicy.defaultBackend {
    this.ollamaUrl = ollamaUrl ?? '';
    this.ollamaModel = ollamaModel ?? '';
  }

  VisionBackend backend;
  String anthropicApiKey;

  /// Empty means the provider's own default -- see [ProviderPolicy.build] for
  /// what naming one costs.
  ///
  /// Current model ids are Anthropic's to publish and this repository holds no
  /// list of them: read them off the Models overview under
  /// platform.claude.com/docs, or `GET https://api.anthropic.com/v1/models`
  /// with the key above. A cloud model id is not a frozen artifact the way a
  /// pulled Ollama tag is -- Anthropic publishes retirement dates, so whatever
  /// this file named would eventually 404 with no way out (T-0067).
  String anthropicModel;

  /// Blank is the default, not a value (T-0082). The settings field's
  /// `hintText` IS the default, which is the Material affordance for "clear
  /// this and you get that" -- so the gesture the UI invites was the one that
  /// stored `''`, handed `OllamaVisionProvider` an empty base URL and failed
  /// minutes into a scan with `Cannot reach Ollama at  -- nothing answered
  /// there.`.
  ///
  /// Enforced on the field rather than in [SettingsStore] or in
  /// [ProviderPolicy.build]: the settings screen edits this object in place and
  /// the scan screen goes on scanning with the same instance, so a store-side
  /// rule would only heal at the next launch. Here it holds for the session
  /// that cleared the field, for a `''` stored before this change, and for a
  /// [ProviderSettings] nobody persisted -- and it is why [ProviderPolicy]
  /// needs no blank check of its own.
  ///
  /// Nothing on the secrets side does this: an invented default for a
  /// credential is a credential nobody chose, so there a blank still means
  /// "forget it" (`SecretStore.write`).
  String get ollamaUrl => _ollamaUrl;
  set ollamaUrl(String value) =>
      _ollamaUrl = value.isEmpty ? defaultOllamaUrl : value;

  String get ollamaModel => _ollamaModel;
  set ollamaModel(String value) =>
      _ollamaModel = value.isEmpty ? defaultOllamaModel : value;

  late String _ollamaUrl;
  late String _ollamaModel;

  /// The user's own OpenAI-compatible endpoint, model and key (T-0006).
  /// All three are empty until typed: BYOK, and nothing external is
  /// preconfigured.
  String openAiBaseUrl;
  String openAiModel;
  String openAiApiKey;

  /// Half a credential pair each, so both are treated as secrets.
  /// BYOK (decision 0011): the user registers their own Twitch application.
  String igdbClientId;
  String igdbClientSecret;

  /// IGDB is optional at runtime; without both halves the resolve stage is
  /// skipped entirely rather than called with empty credentials.
  bool get hasIgdbCredentials =>
      igdbClientId.isNotEmpty && igdbClientSecret.isNotEmpty;

}

/// The two named things a run can do with the titles it reads (T-0230).
///
/// Keyless was reachable before this by leaving the two IGDB fields blank,
/// which is a state to fall into rather than a mode to pick -- and the CLI
/// and README had named it a path ("Path A -- keyless") for as long as the
/// app had not. Naming it here rather than on a screen keeps it beside the
/// backend choice, which is the other thing a run is asked before it starts.
///
/// Two values and not three: "IGDB asked for but not configured" is not a
/// third mode, it is [TitleMatching.igdb] degrading, and [MatchingCheck] is
/// where that is said.
enum TitleMatching { igdb, keyless }

/// Shared for [VisionBackendLabel]'s reason: the scan screen's control and
/// the settings screen's sentence about it must call the mode one thing.
extension TitleMatchingLabel on TitleMatching {
  String get label => switch (this) {
        TitleMatching.igdb => 'Match with IGDB',
        TitleMatching.keyless => 'Keyless',
      };
}

/// What a keyless run's rows will be, said where the mode is picked rather
/// than in a README -- the rule decision 0011 set for the privacy warning,
/// applied to the other thing a person cannot find out afterwards.
///
/// Three things this may not say, and an earlier draft of it said two.
/// It may not promise keyless *detection*: reading the photographs still
/// costs a vision backend, and on a phone that backend is a cloud one
/// (T-0229 asks whether the other half can go too). It may not restate
/// `canExport` -- that a row with a raw title reaches csv is the exporter's
/// rule, and a second copy of it rots, which `review_screen.dart` already
/// warns about. And it names the export that does work, not only the one
/// that does not: the point of the mode is that there is a way through it.
const keylessConsequence =
    'No IGDB lookup: every row keeps the title the model read. No cover art '
    'and no platform id, and the Tonkatsu .xcoll export carries none of '
    'these rows -- CSV carries them all. Reading the photos still takes a '
    'vision backend.';

const igdbConsequence =
    'Titles are looked up on IGDB, which is what .xcoll carries: the ids a '
    'catalog app turns into cover art and platform names.';

/// Asked for, and not registered for. Phrased as the two ways forward rather
/// than as a fault: one of them is to scan now, which is the whole of T-0230.
String get igdbUnconfiguredNote =>
    'No Twitch application is registered yet, so this run would be keyless '
    'anyway. Add the IGDB client id and secret in Settings, or choose '
    '${TitleMatching.keyless.label} and scan now.';

/// What a matching choice means for this run, answered from
/// [ProviderSettings] alone -- no network, no provider, no I/O, so a screen
/// says it at the moment of the tap. The shape and the reason are
/// [BackendCheck]'s (T-0040).
///
/// No `blocker` here, and that difference is the point: an unconfigured
/// backend fails a scan, while unconfigured IGDB degrades it to a keyless
/// one. So [matching] is what a scan started now would really do, and
/// [unconfigured] is why it can differ from what was asked for.
class MatchingCheck {
  const MatchingCheck({
    required this.matching,
    required this.consequence,
    this.unconfigured = false,
  });

  final TitleMatching matching;

  /// What the rows of this run will be, in the words the choice is made with.
  final String consequence;

  /// [TitleMatching.igdb] was asked for and there is nothing to authenticate
  /// with, so this run is keyless without having been chosen as one.
  final bool unconfigured;

  bool get keyless => matching == TitleMatching.keyless;
}

/// Shared so the settings screen and the scan screen's quick switch cannot
/// end up calling the same backend two different things.
extension VisionBackendLabel on VisionBackend {
  String get label => switch (this) {
        VisionBackend.local => 'Local',
        VisionBackend.cloud => 'Cloud',
        VisionBackend.openAiCompatible => 'Endpoint',
      };
}

/// The free-tier sentence is only on the endpoint branch: it is the reason
/// that branch needs a warning at all, and it is not true of a paid
/// Anthropic account. What is true of both is the first sentence.
const cloudPrivacyWarning =
    'Your photos leave this machine: each one is uploaded in full to '
    'Anthropic.';
const endpointPrivacyWarning =
    'Your photos leave this machine: each one is uploaded in full to the '
    'endpoint you name. Free tiers are commonly funded by training on what '
    'is submitted to them, and these are pictures of your home.';

/// What to do about the warning above, on the platform actually running it.
///
/// A separate string rather than a fourth sentence appended to the risk: the
/// risk is the same everywhere and its wording is measured (T-0040, T-0058),
/// while the way out is not. The sentence T-0058 dropped -- "Check that
/// service's data policy before scanning, or use Local" -- is restored here
/// where [localAllowed], and is FALSE where it is not: Android has no local
/// backend in [ProviderPolicy.available] at all, so the only actions left
/// there are the endpoint's own data policy, Anthropic's paid API, and not
/// adding the photo (T-0070).
///
/// Null for [VisionBackend.local], which has nothing to warn about; that ties
/// it to [BackendCheck.warning], which is null in exactly the same case.
String? privacyAdvice(VisionBackend backend, {required bool localAllowed}) {
  final local = VisionBackend.local.label;
  final cloud = VisionBackend.cloud.label;
  return switch (backend) {
    VisionBackend.local => null,
    VisionBackend.cloud => localAllowed
        ? 'Switch to $local to keep them on this machine.'
        : 'This device cannot run a vision model itself, so the only photos '
            'that stay off the network are the ones you leave out of the scan.',
    VisionBackend.openAiCompatible => localAllowed
        ? "Check that service's data policy before you scan, or switch to "
            '$local to keep them on this machine.'
        : "Check that service's data policy before you scan, or use $cloud -- "
            'a paid Anthropic API rather than a free tier.',
  };
}

/// What choosing a backend means, answered from a [ProviderSettings] alone
/// (T-0040): no network call, no provider construction, no I/O of any kind,
/// so a screen can say it at the moment of the tap instead of when the run
/// dies.
class BackendCheck {
  const BackendCheck({
    required this.backend,
    this.blocker,
    this.warning,
    this.advice,
  });

  /// The backend a scan would really use -- see [ProviderPolicy.effective].
  final VisionBackend backend;

  /// Why a scan started now would fail, in the very words that failure
  /// uses, or null if nothing is missing.
  final String? blocker;

  /// What the choice costs even when it works.
  final String? warning;

  /// What the user can do about [warning] on this platform, or null whenever
  /// [warning] is (T-0070). Never a [blocker]'s fix: that one is a way to
  /// make the chosen backend work, this one is the alternative to choosing
  /// it at all.
  final String? advice;

  bool get canRun => blocker == null;

  bool get hasNotice => blocker != null || warning != null;
}

class ProviderPolicy {
  /// Test seam for the Android branch: widget tests run on the host, so
  /// `Platform.isAndroid` can never be true there. Production code never
  /// assigns this -- it only ever changes what platform we pretend to be,
  /// never the policy itself.
  @visibleForTesting
  static bool? debugLocalAllowedOverride;

  static bool get localAllowed =>
      debugLocalAllowedOverride ?? !Platform.isAndroid;

  /// Never [VisionBackend.openAiCompatible]: an external endpoint is only
  /// ever reached because the user named one (decision 0011).
  static VisionBackend get defaultBackend =>
      localAllowed ? VisionBackend.local : VisionBackend.cloud;

  static List<VisionBackend> get available => [
        if (localAllowed) VisionBackend.local,
        VisionBackend.cloud,
        VisionBackend.openAiCompatible,
      ];

  /// Defense in depth: never run a backend this platform disallows even if
  /// the stored settings ask for one -- e.g. preferences restored from a
  /// desktop backup onto a phone.
  static VisionBackend effective(ProviderSettings settings) =>
      (settings.backend == VisionBackend.local && !localAllowed)
          ? VisionBackend.cloud
          : settings.backend;

  /// Everything the UI can know about the current choice without spending
  /// anything (T-0040). Reads only [settings]; see [BackendCheck].
  static BackendCheck check(ProviderSettings settings) {
    final backend = effective(settings);
    return BackendCheck(
      backend: backend,
      blocker: _missing(backend, settings),
      warning: switch (backend) {
        VisionBackend.local => null,
        VisionBackend.cloud => cloudPrivacyWarning,
        VisionBackend.openAiCompatible => endpointPrivacyWarning,
      },
      advice: privacyAdvice(backend, localAllowed: localAllowed),
    );
  }

  /// What [chosen] costs and whether this run can honour it (T-0230). Sole
  /// author of both answers, so the sentence a screen prints and the resolver
  /// [buildResolver] hands the pipeline are decided in one place.
  static MatchingCheck checkMatching(
      ProviderSettings settings, TitleMatching chosen) {
    if (chosen == TitleMatching.keyless) {
      return const MatchingCheck(
        matching: TitleMatching.keyless,
        consequence: keylessConsequence,
      );
    }
    if (!settings.hasIgdbCredentials) {
      return MatchingCheck(
        matching: TitleMatching.keyless,
        consequence: igdbUnconfiguredNote,
        unconfigured: true,
      );
    }
    return const MatchingCheck(
      matching: TitleMatching.igdb,
      consequence: igdbConsequence,
    );
  }

  /// Sole source of both the tap-time answer and the [build] failure, so
  /// the early message and the late one cannot drift apart.
  static String? _missing(VisionBackend backend, ProviderSettings settings) {
    switch (backend) {
      case VisionBackend.local:
        // The one backend that can always run, and since T-0082 that is a
        // property rather than an assumption: local needs a URL and a model
        // and no key, and neither of those two can be blank -- see
        // [ProviderSettings.ollamaUrl]. A blank check here would be dead code
        // stating the opposite rule to the one the field enforces, and
        // reachability is a network question this function is forbidden to ask.
        return null;
      case VisionBackend.cloud:
        if (settings.anthropicApiKey.isEmpty) {
          return 'Cloud recognition needs an Anthropic API key -- add it in '
              'Settings.';
        }
        return null;
      case VisionBackend.openAiCompatible:
        // Each half named separately: "check your settings" for three
        // fields is a worse error than saying which one is blank.
        if (settings.openAiBaseUrl.isEmpty) {
          return 'This backend needs the API endpoint of the service you '
              'want to use -- add it in Settings.';
        }
        if (settings.openAiModel.isEmpty) {
          return 'This backend needs a model name -- add it in Settings.';
        }
        if (settings.openAiApiKey.isEmpty) {
          return 'This backend needs your own API key for '
              '${settings.openAiBaseUrl} -- add it in Settings.';
        }
        return null;
    }
  }

  /// Build the provider for the chosen backend, or throw a friendly
  /// message the UI can show as-is.
  ///
  /// [onRequestAdjusted] is where an endpoint's refusal of one of the
  /// preference fields is reported, once per correction (T-0110). Only the
  /// endpoint backend can produce one: it is the only one that learns its
  /// request shape from 400s. A shell that passes nothing runs whatever the
  /// endpoint decided to give it and cannot say so afterwards -- which for a
  /// dropped `temperature` means every number from that run is a measurement
  /// of a different system (doc/measurements.md).
  static VisionProvider build(
    ProviderSettings settings, {
    void Function(String note)? onRequestAdjusted,
  }) {
    final backend = effective(settings);
    final missing = _missing(backend, settings);
    if (missing != null) throw StateError(missing);

    switch (backend) {
      case VisionBackend.local:
        return OllamaVisionProvider(
          baseUrl: settings.ollamaUrl,
          model: settings.ollamaModel,
        );
      case VisionBackend.cloud:
        // A model the USER named is sent without a temperature; the default is
        // sent with the 0 it was argued for (T-0057). `temperature` is
        // model-gated on this API -- Claude Opus 4.7 and later, Sonnet 5 and
        // Fable 5 return 400 for a request carrying one -- and that 400,
        // arriving several minutes into a scan, reads as a broken key.
        //
        // Which families accept sampling is deliberately NOT written down: a
        // table of model ids ages exactly the way the pinned default did, and
        // one that has gone stale fails the same way it was meant to prevent.
        // So the rule is about who chose the id rather than which id it is.
        // The price is that a named model's sampling is Anthropic's rather
        // than this project's; the settings screen says so where the id is
        // typed, because an unrecorded sampling state is what T-0053 exists
        // to end.
        return settings.anthropicModel.isEmpty
            ? AnthropicVisionProvider(apiKey: settings.anthropicApiKey)
            : AnthropicVisionProvider(
                apiKey: settings.anthropicApiKey,
                model: settings.anthropicModel,
                temperature: null,
              );
      case VisionBackend.openAiCompatible:
        return OpenAiCompatibleVisionProvider(
          baseUrl: settings.openAiBaseUrl,
          model: settings.openAiModel,
          apiKey: settings.openAiApiKey,
          onRequestAdjusted: onRequestAdjusted,
        );
    }
  }

  /// Resolver for a scan. Mirrors the CLI: no IGDB credentials means the
  /// stage is skipped, not attempted with empty ones. [SkipResolver] is
  /// the shared implementation of that behaviour (shelfscan_core).
  ///
  /// [aliases] is the table loaded from the bundled asset (see
  /// `title_aliases.dart`); omitting it leaves the resolver on its built-in
  /// fallback.
  ///
  /// [matching] is the mode the user picked (T-0230), and it defaults to
  /// [TitleMatching.igdb] so a caller that never asks keeps the credential
  /// rule it always had. The two ways of arriving at a keyless run are
  /// answered by [checkMatching] rather than tested again here: one rule,
  /// one author, and the screen showing the sentence is reading it from the
  /// same call.
  ///
  /// **A keyed run returns a [CatalogueRouter] and not a bare
  /// [ResolverWorker] (T-0308), and only [WorkKind.game] is registered on
  /// it.** Everything else falls to [SkipResolver], which is the owner's
  /// decision: a row of a kind this app cannot look up is keyless -- the
  /// title as detected, CSV yes, `.xcoll` no -- exactly as every row is in a
  /// run with no credentials at all. What it replaces is the reason the
  /// router's fallback is required rather than defaulted: one IGDB resolver
  /// for every row searched a film in the games catalogue.
  ///
  /// **There is no TMDB entry here and there cannot be one yet.** The CLI
  /// takes that token from the environment; this shell keeps credentials in
  /// the OS keychain (decision 0011) and Settings has no field for a third
  /// one. Adding it is user-facing and is its own task, so the film kind
  /// reaches [SkipResolver] on every path through this app.
  static ResolverWorker buildResolver(
    ProviderSettings settings, {
    Map<String, String>? aliases,
    TitleMatching matching = TitleMatching.igdb,
  }) {
    if (checkMatching(settings, matching).keyless) return SkipResolver();
    return CatalogueRouter(
      catalogues: {
        WorkKind.game: ResolverWorker(
          IgdbClient(
            clientId: settings.igdbClientId,
            clientSecret: settings.igdbClientSecret,
          ),
          aliases: aliases,
        ),
      },
      fallback: SkipResolver(),
    );
  }

  /// Concurrency differs: a local model processes images sequentially.
  static int visionConcurrency(VisionBackend backend) =>
      backend == VisionBackend.local ? 1 : 3;
}
