/// Vision backend policy and wiring for the app.
///
/// Platform policy (product decision, not a technical constraint):
///   - Windows: user chooses local (Ollama) or a cloud endpoint.
///     Default: LOCAL -- a desktop next to the shelf can run its own model.
///   - Android: local is OFFERED and is never the default (T-0361);
///     [VisionBackend.cloud] is, by elimination rather than by preference --
///     a default that cannot work until an address is typed would be a
///     broken first launch, and an endpoint the user names is never a
///     default anywhere, so the cloud backend is what is left. The
///     phone runs no model of its own -- "on-device models are too weak for
///     spine OCR" is a measurement taken ON the phone, it stands unchanged,
///     and nothing here overturns it. What local means on this platform is
///     the other thing the word can mean: an Ollama the user names on their
///     own network -- the same model on the same desktop hardware that
///     already serves the desktop app, one hop away. Two claims about two
///     machines; neither settles the other, and no text in this file may
///     read as though the second retired the first.
///     Three consequences live here rather than on a screen. The address
///     cannot default, because loopback on a phone IS the phone, so it is a
///     [BackendCheck.blocker] until one is typed. A loopback address typed
///     anyway is refused at the tap rather than left to time out -- it is
///     the one wrong address that is knowably wrong. And local stops meaning
///     "nothing leaves the machine": here it carries a privacy warning of
///     its own, because the photographs cross the network in the clear
///     (T-0069's rule, that local was never a synonym for offline, is
///     visible on this platform rather than merely true). The platform half
///     of the cleartext question -- what Android would and would not let
///     this app express about it -- is argued in
///     `android/app/src/main/AndroidManifest.xml`.
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

/// Declaration order is the order the user meets them in: local, then the
/// endpoint they name, then Anthropic. The owner's call about who uses this,
/// and not a technical one (T-0343). [ProviderPolicy.available] repeats it for
/// the screens and `backend_order_test.dart` holds the two together.
///
/// Reordering is safe only because `SettingsStore` persists `backend.name` and
/// reads it back through a switch on those strings. By index the same edit
/// would move every stored preference to a different provider.
enum VisionBackend { local, openAiCompatible, cloud }

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
    this.tmdbToken = '',
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
  /// [ProviderSettings] nobody persisted.
  ///
  /// **Only where the local server can be this machine (T-0361).** The
  /// coercion needs somewhere to coerce to, and on a phone there is nowhere:
  /// [defaultOllamaUrl] is loopback, loopback is the phone, and the phone is
  /// the one machine on the network that is certainly not running Ollama.
  /// Substituting it would be inventing an address the user never chose --
  /// the same objection the secrets side makes below -- and would spend a
  /// scan's worth of timeout proving it. So blank stays blank there and
  /// [ProviderPolicy] answers for it with a blocker at the tap, which is why
  /// that check exists on this backend at all.
  ///
  /// Nothing on the secrets side does this: an invented default for a
  /// credential is a credential nobody chose, so there a blank still means
  /// "forget it" (`SecretStore.write`).
  String get ollamaUrl => _ollamaUrl;
  set ollamaUrl(String value) => _ollamaUrl = value.isNotEmpty
      ? value
      : (ProviderPolicy.localServerIsThisMachine ? defaultOllamaUrl : '');

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

  /// The TMDB **API Read Access Token**, and not the v3 `api_key` issued on
  /// the same page -- `tmdbTokenVariable` in `shelfscan_core` argues why, and
  /// the settings field says it where the paste happens, because the two look
  /// nothing alike and the wrong one answers 401.
  ///
  /// A secret like the four above it, and optional like the IGDB pair: what a
  /// blank one costs is a keyless film row.
  String tmdbToken;

  bool get hasTmdbToken => tmdbToken.isNotEmpty;

  /// Whether anything at all can be looked up, which is what decides a keyed
  /// run from a keyless one (T-0367). Not [hasIgdbCredentials]: a catalogue
  /// per kind means either credential keys a run, and the kinds the other one
  /// would have answered fall to [SkipResolver] the way an unregistered kind
  /// already did (T-0308). The CLI has read it this way since the film path
  /// existed -- `resolverFor` skips on an empty catalogue map, not on a
  /// missing Twitch application.
  bool get hasAnyCatalogue => hasIgdbCredentials || hasTmdbToken;
}

/// The two named things a run can do with the titles it reads (T-0230).
///
/// Keyless was reachable before this by leaving the two IGDB fields blank,
/// which is a state to fall into rather than a mode to pick -- and the CLI
/// and README had named it a path ("Path A -- keyless") for as long as the
/// app had not. Naming it here rather than on a screen keeps it beside the
/// backend choice, which is the other thing a run is asked before it starts.
///
/// Two values and not three: "matching asked for but nothing configured" is
/// not a third mode, it is [TitleMatching.matched] degrading, and
/// [MatchingCheck] is where that is said.
///
/// **This is what the person ASKED for, and never what the run can reach
/// (T-0367).** The two were one thing while IGDB was the only catalogue, and
/// fusing them is what left a stored TMDB token idle. What is reachable is
/// [ProviderSettings.hasAnyCatalogue], derived per kind; what is wanted is
/// this, and it stays a choice: keyless costs no privacy and risks nothing,
/// so a person holding every credential may still pick it and be obeyed.
enum TitleMatching { matched, keyless }

/// Shared for [VisionBackendLabel]'s reason: the scan screen's control and
/// the settings screen's sentence about it must call the mode one thing.
///
/// [TitleMatching.matched] was labelled "Match with IGDB" until T-0367, and
/// the catalogue came out of the label rather than out of the sentence below
/// it: with a TMDB token and no Twitch application the label named the one
/// catalogue this run cannot reach. The label is the choice; which catalogues
/// answer it is [MatchingCheck.consequence]'s to say, once, from the
/// credentials actually stored.
extension TitleMatchingLabel on TitleMatching {
  String get label => switch (this) {
        TitleMatching.matched => 'Match',
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

/// What a matched run does, one sentence per stored combination (T-0367).
///
/// One of these three replaces the single `igdbConsequence`, which said
/// "titles are looked up on IGDB" of every keyed run and was already wrong
/// with a token stored -- film rows go to TMDB. There is no composed sentence
/// and deliberately so: three fixed strings can each be read as English and
/// checked against the code, while a builder that concatenates clauses is how
/// a screen turns into a status board.
///
/// **The kind that is NOT looked up is named, and the CLI is why.** Its
/// `_makeResolver` prints the film clause only on a run that can be surprised
/// by it, and says in place that repeating it per catalogue with nothing
/// configured would be noise. That is exactly the split below:
/// [noCatalogueNote] enumerates nothing, and these three name the other kind
/// in four words.
/// What a keyless row then costs is not restated here -- Settings says it
/// where the credential is typed, and the review screen says it per row.
const igdbOnlyConsequence =
    'Games are looked up on IGDB, which is what .xcoll carries: the ids a '
    'catalog app turns into cover art and platform names. Films are not '
    'looked up.';

/// No platform names in this one: a `.xcoll` movie item carries no
/// `platform_id` at all, which is [WorkKind.movie]'s doc comment and the
/// exporter's `_PlatformId.absent`.
const tmdbOnlyConsequence =
    'Films are looked up on TMDB, which is what .xcoll carries: the ids a '
    'catalog app turns into cover art. Games are not looked up.';

const bothCataloguesConsequence =
    'Games are looked up on IGDB and films on TMDB. Those ids are what .xcoll '
    'carries: a catalog app turns them into cover art and metadata.';

/// Asked for, and nothing registered to answer it. Phrased as the two ways
/// forward rather than as a fault: one of them is to scan now, which is the
/// whole of T-0230.
///
/// **It names Twitch and not TMDB, and that is the decision rather than an
/// omission (T-0367).** This is the only sentence a person with no credential
/// at all ever sees on this control, and it is the common path; listing both
/// catalogues at somebody who has neither is the status board the scan screen
/// must not become. The screen that does enumerate them is Settings, which is
/// where this sentence sends them.
String get noCatalogueNote =>
    'No Twitch application is registered yet, so this run would be keyless '
    'anyway. Add the IGDB client id and secret in Settings, or choose '
    '${TitleMatching.keyless.label} and scan now.';

/// The four credential combinations, enumerated once so no screen has to
/// (T-0367). The fourth arm is [noCatalogueNote] rather than a fourth string:
/// asking to match with nothing stored is the degrade [MatchingCheck] reports
/// as `unconfigured`, not a keyed run with an empty catalogue map.
String matchedConsequence(ProviderSettings settings) =>
    switch ((settings.hasIgdbCredentials, settings.hasTmdbToken)) {
      (true, true) => bothCataloguesConsequence,
      (true, false) => igdbOnlyConsequence,
      (false, true) => tmdbOnlyConsequence,
      (false, false) => noCatalogueNote,
    };

/// What a matching choice means for this run, answered from
/// [ProviderSettings] alone -- no network, no provider, no I/O, so a screen
/// says it at the moment of the tap. The shape and the reason are
/// [BackendCheck]'s (T-0040).
///
/// No `blocker` here, and that difference is the point: an unconfigured
/// backend fails a scan, while no catalogue at all degrades it to a keyless
/// one. So [matching] is what a scan started now would really do, and
/// [unconfigured] is why it can differ from what was asked for -- the two
/// facts T-0367 pulled apart, held here in one object rather than fused into
/// one field.
class MatchingCheck {
  const MatchingCheck({
    required this.matching,
    required this.consequence,
    this.unconfigured = false,
  });

  final TitleMatching matching;

  /// What the rows of this run will be, in the words the choice is made with.
  final String consequence;

  /// [TitleMatching.matched] was asked for and there is no catalogue to ask,
  /// so this run is keyless without having been chosen as one.
  final bool unconfigured;

  bool get keyless => matching == TitleMatching.keyless;
}

/// Shared so the settings screen and the scan screen's quick switch cannot
/// end up calling the same backend two different things.
extension VisionBackendLabel on VisionBackend {
  String get label => switch (this) {
        VisionBackend.local => 'Local',
        VisionBackend.openAiCompatible => 'Endpoint',
        VisionBackend.cloud => 'Cloud',
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

/// Local's own warning, on a platform where local is another machine
/// (T-0361). It exists because the first sentence of the other two is true
/// here as well, and a backend that says nothing would be read as saying
/// nothing happens -- which is exactly the conflation T-0069 corrected in the
/// README ("images never leave the machine") and PROJECT.md now forbids.
///
/// The second sentence is the one an auditor is owed and it is not softened:
/// Ollama speaks plain HTTP and this app does not wrap it in anything, so the
/// photographs cross the local network unencrypted and unauthenticated. What
/// is bounded is the destination, not the exposure -- see the manifest for
/// why no Android setting changes either half.
const lanPrivacyWarning =
    'Your photos leave this device: each one is uploaded in full to the '
    'Ollama server you name, over plain HTTP, so anything on that network can '
    'read them on the way. They do not reach the internet.';

/// What to do about the warning above, on the platform actually running it.
///
/// A separate string rather than a fourth sentence appended to the risk: the
/// risk is the same everywhere and its wording is measured (T-0040, T-0058),
/// while the way out is not. The sentence T-0058 dropped -- "Check that
/// service's data policy before scanning, or use Local" -- is restored here
/// where the local server can be this machine, and was FALSE where it could
/// not be, because Android then had no local backend at all (T-0070).
///
/// **T-0361 changed which half is false, not the shape.** Local is now
/// offered everywhere, so it is nameable on both branches; what a phone
/// cannot claim is the *destination*. "Keep them on this machine" is the
/// desktop's sentence and stays there. The phone's version says where they go
/// instead, because on that platform local is another machine and the
/// difference between "off this device" and "off the internet" is the whole
/// of what the user is choosing (T-0069).
///
/// Null for [VisionBackend.local] only where nothing leaves; on a phone that
/// backend has [lanPrivacyWarning] and gets an action like the other two.
/// Non-null in exactly the cases [BackendCheck.warning] is -- one invariant,
/// two branches, and `scan_backend_switch_test.dart` holds it.
String? privacyAdvice(VisionBackend backend,
    {required bool localServerIsThisMachine}) {
  final local = VisionBackend.local.label;
  return switch (backend) {
    VisionBackend.local => localServerIsThisMachine
        ? null
        : 'Run the scan on the desktop hosting that server, and the photos '
            'stay on one machine.',
    VisionBackend.openAiCompatible => localServerIsThisMachine
        ? "Check that service's data policy before you scan, or switch to "
            '$local to keep them on this machine.'
        : "Check that service's data policy before you scan, or switch to "
            '$local, which sends them to a server on your own network '
            'instead of to the internet.',
    VisionBackend.cloud => localServerIsThisMachine
        ? 'Switch to $local to keep them on this machine.'
        : 'This device cannot read the photos itself, but $local sends them '
            'to a server on your own network instead of to the internet.',
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

  /// The backend a scan would really use, which since T-0361 is simply the
  /// one chosen: no platform refuses any of the three any more, so the
  /// substitution this field used to be able to report cannot happen.
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
  static bool? debugLocalServerIsThisMachineOverride;

  /// Whether the machine running this app is one that could be hosting the
  /// Ollama server itself.
  ///
  /// It was `localAllowed` until T-0361, and the rename is the change: local
  /// is allowed everywhere now, so a getter answering "is local offered?"
  /// would answer `true` and decide nothing. What still divides the two
  /// platforms is whether "local" and "this device" are the same address --
  /// and that governs the default backend, whether a blank URL has anything
  /// to mean, whether loopback is a usable answer, and which privacy claim
  /// is honest. All four are questions about the machine, not about the list
  /// of backends, which is why they now ask one.
  static bool get localServerIsThisMachine =>
      debugLocalServerIsThisMachineOverride ?? !Platform.isAndroid;

  /// Never [VisionBackend.openAiCompatible]: an external endpoint is only
  /// ever reached because the user named one (decision 0011). And never
  /// [VisionBackend.local] on a phone, though it is selectable there
  /// (T-0361): a default that cannot work until an address is typed is a
  /// broken first launch, and the owner's provider order is not this task's
  /// to move -- offering an option is not preferring it.
  static VisionBackend get defaultBackend =>
      localServerIsThisMachine ? VisionBackend.local : VisionBackend.cloud;

  /// Both screens render this list in order, so it carries [VisionBackend]'s
  /// declaration order and a test fails if the two drift apart.
  ///
  /// Unconditional since T-0361. Nothing is filtered by platform any more,
  /// and the reason it is still a list rather than `VisionBackend.values` is
  /// that the two are separately readable: the enum declares an order for a
  /// stated reason (T-0343) and this states that the screens get all of it.
  static List<VisionBackend> get available => const [
        VisionBackend.local,
        VisionBackend.openAiCompatible,
        VisionBackend.cloud,
      ];

  /// Everything the UI can know about the current choice without spending
  /// anything (T-0040). Reads only [settings]; see [BackendCheck].
  /// The stored preference is used as it stands. There used to be a downgrade
  /// here for a `local` preference restored from a desktop backup onto a
  /// phone; T-0361 removed it, because that preference is now honourable and
  /// silently answering a different question than the one asked is the defect
  /// class this project names loudest. What the restored settings really
  /// carry onto a phone is the desktop's loopback URL, and that is refused by
  /// name in [_missing] instead -- a blocker the user can read, in place of a
  /// substitution they could not.
  static BackendCheck check(ProviderSettings settings) {
    final backend = settings.backend;
    final onThisMachine = localServerIsThisMachine;
    return BackendCheck(
      backend: backend,
      blocker: _missing(backend, settings),
      warning: switch (backend) {
        VisionBackend.local => onThisMachine ? null : lanPrivacyWarning,
        VisionBackend.openAiCompatible => endpointPrivacyWarning,
        VisionBackend.cloud => cloudPrivacyWarning,
      },
      advice: privacyAdvice(backend, localServerIsThisMachine: onThisMachine),
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
    // The asked-for half is answered above and the reachable half below, and
    // the order is the point: a chosen keyless run is obeyed before any
    // credential is consulted, so storing a token can never overrule it.
    final consequence = matchedConsequence(settings);
    if (!settings.hasAnyCatalogue) {
      return MatchingCheck(
        matching: TitleMatching.keyless,
        consequence: consequence,
        unconfigured: true,
      );
    }
    return MatchingCheck(
      matching: TitleMatching.matched,
      consequence: consequence,
    );
  }

  /// Sole source of both the tap-time answer and the [build] failure, so
  /// the early message and the late one cannot drift apart.
  static String? _missing(VisionBackend backend, ProviderSettings settings) {
    switch (backend) {
      case VisionBackend.local:
        // On a desktop this still returns null for the T-0082 reason: local
        // needs a URL and a model and no key, and neither can be blank
        // because the field coerces a cleared one to the built-in default.
        //
        // On a phone there is no default to coerce to, so both branches below
        // are reachable and neither is a network question -- which this
        // function is still forbidden to ask. Both are properties of the
        // string itself, and both replace the same failure: a wrong address
        // is not refused by anything, it is a 120-second timeout per photo
        // that reads as a hang. These are the two cases where the answer is
        // knowable at the tap, so they are given at the tap.
        if (!localServerIsThisMachine) {
          if (settings.ollamaUrl.isEmpty) {
            return 'Local needs the address of an Ollama server on your '
                'network -- add it in Settings, as http://ADDRESS:PORT. This '
                'device is not it: nothing here runs a vision model.';
          }
          if (_addressesThisDevice(settings.ollamaUrl)) {
            return 'Local needs the address of an Ollama server on your '
                'network. ${settings.ollamaUrl} is this device, which runs no '
                'vision model -- give the address of the machine that does.';
          }
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
      case VisionBackend.cloud:
        if (settings.anthropicApiKey.isEmpty) {
          return 'Cloud recognition needs an Anthropic API key -- add it in '
              'Settings.';
        }
        return null;
    }
  }

  /// Whether [url] names the device this app is running on, whatever may be
  /// listening there (T-0361).
  ///
  /// Deliberately not a validity check on anything else. Whether some other
  /// address answers is a network question and [_missing] may not ask one;
  /// these are the forms whose answer needs no asking, and they are the forms
  /// a person actually types -- including the one a settings backup restored
  /// from the desktop brings with it, which is the case that made this worth
  /// having. A name beginning `127.` is an address rather than a host in
  /// every practical case, so the prefix is taken as one.
  ///
  /// `Uri.parse` strips the brackets from an IPv6 authority, so
  /// `http://[::1]:11434` reaches here as `::1`. A string that does not parse
  /// has no host, is claimed to be nothing, and fails later as the parse
  /// failure it is.
  static bool _addressesThisDevice(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' ||
        host == '::1' ||
        host == '0.0.0.0' ||
        host.startsWith('127.');
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
    final backend = settings.backend;
    final missing = _missing(backend, settings);
    if (missing != null) throw StateError(missing);

    switch (backend) {
      case VisionBackend.local:
        return OllamaVisionProvider(
          baseUrl: settings.ollamaUrl,
          model: settings.ollamaModel,
        );
      case VisionBackend.openAiCompatible:
        return OpenAiCompatibleVisionProvider(
          baseUrl: settings.openAiBaseUrl,
          model: settings.openAiModel,
          apiKey: settings.openAiApiKey,
          onRequestAdjusted: onRequestAdjusted,
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
    }
  }

  /// Resolver for a scan. Mirrors the CLI, and since T-0367 in the one place
  /// it did not: a credential -- either credential -- keys the stage, and it
  /// is skipped only when there is no catalogue to ask. [SkipResolver] is the
  /// shared implementation of that behaviour (shelfscan_core), and
  /// `resolverFor` in `bin/shelfscan.dart` is the same rule written as
  /// `catalogues.isEmpty`.
  ///
  /// [aliases] is the table loaded from the bundled asset (see
  /// `title_aliases.dart`); omitting it leaves the resolver on its built-in
  /// fallback.
  ///
  /// [matching] is the mode the user picked (T-0230), and it defaults to
  /// [TitleMatching.matched] so a caller that never asks keeps the credential
  /// rule it always had. The two ways of arriving at a keyless run are
  /// answered by [checkMatching] rather than tested again here: one rule,
  /// one author, and the screen showing the sentence is reading it from the
  /// same call.
  ///
  /// **A keyed run returns a [CatalogueRouter] and not a bare
  /// [ResolverWorker] (T-0308), and a kind with no catalogue on it falls to
  /// [SkipResolver].** That is the owner's decision: a row of a kind this app
  /// cannot look up is keyless -- the title as detected, CSV yes, `.xcoll`
  /// no -- exactly as every row is in a run with no credentials at all. What
  /// it replaces is the reason the router's fallback is required rather than
  /// defaulted: one IGDB resolver for every row searched a film in the games
  /// catalogue.
  ///
  /// **Each kind is registered only when its own credential is stored
  /// (T-0363, T-0367), and either one on its own is enough to key the run.**
  /// The credentials are [ProviderSettings] fields rather than parameters of
  /// this method: T-0308 refused to add one while nothing could reach it, and
  /// what changed is that Settings now holds both, so they arrive the way
  /// every other credential here does. A token alone therefore resolves films
  /// and leaves games keyless, which is the owner's case -- *someone might be
  /// sorting only films, without games* -- and is what the CLI has always
  /// done.
  ///
  /// **The token registers the two animation kinds a person can answer as
  /// well, each on the TMDB endpoint it belongs to (T-0369), and the CLI's
  /// `resolverFor` registers exactly the same four.** An animated film is a
  /// film and an animated series is television, which TMDB separates by
  /// endpoint -- so [WorkKind.animationFilm] joins [WorkKind.movie] on the
  /// film search and [WorkKind.animationSeries] goes to the series one.
  /// [WorkKind.animation], whose film-or-series question nobody has answered,
  /// is registered nowhere: there is no endpoint for *one of the two*, and a
  /// search that picked would answer half of those rows with an id for the
  /// other sort of thing.
  ///
  /// **[WorkKind.anime] is registered nowhere in any configuration, and no
  /// credential this screen collects would change that (T-0456).** Upstream
  /// files anime on AniList or Kitsu and `animation` on TMDB -- two types, not
  /// two words -- so the TMDB token buys that kind nothing, and a row of it
  /// stays keyless: the title as read, CSV yes, `.xcoll` no.
  ///
  /// No kind is named at this site. `registrationsOf` reads the kinds off the
  /// catalogue, so which endpoint answers which kind is stated once, on
  /// `TmdbResolverWorker`, rather than once per shell.
  ///
  /// **The catalogue has answered, and never to this shell.** The CLI's film
  /// path was run against the live service once, on three public films on one
  /// evening (`doc/measurements.md`, "TMDB's `year` filters"). Read the limits
  /// under that section before quoting it: three titles are not a match rate,
  /// no live answer there was separated by a release year, and the run says
  /// nothing whatever about this shell, which had no token to register until
  /// now. What this field buys a user is that same route, travelled by them
  /// first.
  ///
  /// **And the series endpoint has been called by nobody at all**, in either
  /// shell. The film path at least ran once; `/3/search/tv` is code written
  /// against TMDB's published API and exercised only against a fake -- which
  /// is exactly how the film path's own `year` comment came to be false
  /// (T-0336). What a live run must show is in `doc/reports/T-0369.md`.
  static ResolverWorker buildResolver(
    ProviderSettings settings, {
    Map<String, String>? aliases,
    TitleMatching matching = TitleMatching.matched,
  }) {
    // Both gates, in the order they are asked. [checkMatching] answers the
    // chosen mode and the empty-catalogue case together, so what is left below
    // is one conditional per credential and a map that cannot come out empty.
    if (checkMatching(settings, matching).keyless) return SkipResolver();
    final tmdb =
        settings.hasTmdbToken ? TmdbClient(token: settings.tmdbToken) : null;
    return CatalogueRouter(
      catalogues: {
        if (settings.hasIgdbCredentials)
          ...registrationsOf(ResolverWorker(
            IgdbClient(
              clientId: settings.igdbClientId,
              clientSecret: settings.igdbClientSecret,
            ),
            aliases: aliases,
          )),
        if (tmdb != null) ...registrationsOf(TmdbResolverWorker.movies(tmdb)),
        if (tmdb != null) ...registrationsOf(TmdbResolverWorker.series(tmdb)),
      },
      fallback: SkipResolver(),
    );
  }

  /// Concurrency differs: a local model processes images sequentially.
  static int visionConcurrency(VisionBackend backend) =>
      backend == VisionBackend.local ? 1 : 3;
}
