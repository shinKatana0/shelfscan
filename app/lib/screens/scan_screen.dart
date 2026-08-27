/// Scan screen: pick photos -> run the pipeline -> open review.
///
/// Credentials are never hardcoded here: they arrive with [ProviderSettings],
/// loaded at startup from the OS keychain / preferences (see settings_store).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import '../galaxy_db.dart';
import '../heic_wic.dart';
import '../input_picker.dart';
import '../media_folders.dart';
import '../photo_files.dart';
import '../provider_config.dart';
import '../settings_store.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

/// One name for the third input: the control that adds it, the row it becomes,
/// its remove tooltip and every refusal about it, so what the user pressed and
/// what answered are named identically. GOG rather than "library" -- this
/// reads one vendor's local database, and a user with no Galaxy should see
/// that without pressing it.
const _libraryLabel = 'GOG library';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.settings,
    this.store = const SettingsStore(),
    this.picker = const PlatformInputPicker(),
    this.aliases,
    this.debugVisionProvider,
    this.debugVisionProviderBuilder,
    this.debugHeicDecoder,
    this.debugFolderReader,
    this.debugLibraryReader,
    this.debugOperatingSystem,
  });

  /// Loaded once at startup and edited by the settings screen in place.
  final ProviderSettings settings;
  final SettingsStore store;

  /// Where the photographs and the media folder come from -- the real file
  /// dialogs in production, a fake in a widget test.
  final InputPicker picker;

  /// Regional-title aliases from the bundled data file, handed to the
  /// resolver. Null leaves it on the built-in fallback.
  final Map<String, String>? aliases;

  /// Test seam: a vision provider to run instead of the one the platform
  /// policy would build, so a widget test can make a specific photo fail.
  /// Null in production, where [ProviderPolicy] stays the only source of a
  /// provider.
  @visibleForTesting
  final VisionProvider? debugVisionProvider;

  /// Test seam for the run's own note channel: a provider built with the sink
  /// the screen feeds warnings from, which [debugVisionProvider] is
  /// constructed too early to have (T-0110). Tried only when that one is null,
  /// and null itself in production.
  @visibleForTesting
  final VisionProvider Function(void Function(String note) onNote)?
      debugVisionProviderBuilder;

  /// Test seam: a HEIC decoder to use instead of the platform's, so a widget
  /// test can make a chosen file fail without a real codec.
  @visibleForTesting
  final HeicDecoder? debugHeicDecoder;

  /// Test seam: what a chosen folder holds, instead of the disk.
  ///
  /// Not a convenience -- `testWidgets` runs its body in a fake async zone, so
  /// a real `Directory.list()` future never completes there and the pick hangs
  /// with nothing added and nothing named. The walk itself is covered against
  /// real directories in `media_folders_test.dart`, which is a plain test.
  @visibleForTesting
  final Future<MediaFolder> Function(String path)? debugFolderReader;

  /// Test seam: the GOG library, instead of Galaxy's own database.
  ///
  /// Same reason as [debugFolderReader], twice over: the real read is a file
  /// copy and an FFI query on another isolate, neither of which completes in
  /// `testWidgets`'s fake async, and what it reads is a real purchases file.
  /// `galaxy_db_test.dart` drives the real reader against real databases, as
  /// a plain test.
  @visibleForTesting
  final Future<GalaxyLibrary> Function()? debugLibraryReader;

  /// Test seam: the host this screen is drawn for, instead of the real one.
  ///
  /// Widget tests run on the developer's machine, so `Platform` answers one
  /// host there and the branch that has to be pinned is the other one.
  /// `provider_config.dart` takes the same seam for the same reason, and
  /// production code never assigns either.
  @visibleForTesting
  final String? debugOperatingSystem;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<PhotoInput> _photos = [];

  /// Folders of games and films, added from their own control (T-0161).
  ///
  /// A second list rather than a mode on [_photos]: the two inputs share the
  /// Scan button and nothing else. A folder makes no vision call, costs
  /// nothing, needs no key and fails in ways a photograph cannot, and the
  /// removals this project already learned to give the photo list (T-0138)
  /// have to work per input, not per run.
  final List<MediaFolder> _folders = [];

  /// The GOG library, once the user has asked for it (T-0179).
  ///
  /// A third input and not a fourth folder: there is one Galaxy database, at
  /// one known path, so there is nothing to pick and nothing to hold a list
  /// of. It is nullable for that reason -- "added or not" is the whole of its
  /// state -- and it is the read itself rather than a flag, because
  /// [GalaxyLibrary.asOf] is what the staleness line is written from and the
  /// entries are what the run is handed.
  GalaxyLibrary? _library;

  /// Why this host cannot have a GOG library at all, or null when it can
  /// (T-0344).
  ///
  /// **Not offered, rather than offered and refused.** Galaxy is a Windows
  /// program, so on any other host there is no database, nothing to pick and
  /// nothing a press could achieve -- and a control whose press cannot achieve
  /// anything is a failed action dressed as a feature, which is the shape
  /// T-0311 to T-0340 spent two days taking off the review screen. Disabling
  /// it instead would have looked to the user exactly like the defect they
  /// reported: pressed, and nothing happened.
  ///
  /// Hiding alone would teach nothing, so the reason takes the offer's place
  /// on the empty screen rather than the offer simply vanishing. It is
  /// [galaxyUnsupported], the reader's own refusal, so the screen and the
  /// reader name the platform in the same words. The reader keeps its check --
  /// the CLI reaches it too -- and the screen no longer depends on it.
  late final String? _noGalaxy = galaxyUnsupported(
      widget.debugOperatingSystem ?? Platform.operatingSystem);

  /// Why there is no review screen, in one sentence -- never a label in front
  /// of one.
  ///
  /// Four things write it: a blocker the settings can fix, that same blocker
  /// arriving as a `StateError` when the scan starts, a run whose every photo
  /// failed, and an error of no shape this app knows. Each is a sentence from
  /// whoever knows the answer -- the policy for a condition, the exception for
  /// a run that ended -- and only the last has no such author, so only the last
  /// is worded here. The screen's own `Failed: ` prefix was written when `$e`
  /// was a raw exception; once T-0072 gave that exception a sentence of its
  /// own it read `Failed: All 3 photo(s) failed`, while the CLI printing the
  /// same sentence bare read correctly (T-0101).
  String _status = '';
  bool _running = false;

  /// The running scan's stop switch, or null when nothing is running. Held
  /// rather than a bool because it is what the pipeline reads (T-0121), and
  /// the screen's own "is it stopping" answer is then the same fact rather
  /// than a copy of it that can disagree.
  StopToken? _stop;

  /// Where the pipeline is right now. `_total == 0` means the current stage
  /// reports no count -- `dedupe`, and the gap before the first stage
  /// callback arrives -- and the bar runs indeterminate for those.
  String _stage = '';
  int _done = 0;
  int _total = 0;

  /// Everything non-fatal the run had to say, in arrival order, each carrying
  /// its [Severity]. Kept rather than shown once: a photo that died halfway
  /// through a long run is still the reason the review list is short by the
  /// time the run ends.
  final List<ScanWarning> _warnings = [];

  /// Files the last "Add photos" could not turn into scannable bytes. Kept
  /// separate from [_warnings], which a scan clears: a file rejected at the
  /// picker must stay named until the user picks again.
  final List<RejectedPhoto> _rejected = [];

  /// The HEIC currently being converted, or `''`. Each costs ~0.4 s.
  String _converting = '';

  /// A pick in flight -- a dialog is open, or what it returned is still being
  /// converted or walked. Not a fifth flag beside [_running]: it takes over
  /// from `_converting.isNotEmpty` in [_busy], which covered only the second
  /// half of the same span and left the dialog itself unguarded (T-0116).
  ///
  /// One flag for all three add controls, so the guard covers the
  /// cross-product too: the stack of explorers the owner got was one dialog
  /// per press, and pressing another control inside that frame opens exactly
  /// the same stack. The library control opens no dialog and is behind it
  /// anyway -- its read is a 3 MB file copy and an SQLite query, which is long
  /// enough for a second press to land inside.
  bool _picking = false;

  /// The last finished scan, kept here rather than in the pushed route's call
  /// frame (T-0117). Recovering a dropped one costs another full scan: ~80 s
  /// locally on three photos, or cloud money.
  _HeldReview? _review;

  /// A message about something Settings holds a field for is only useful with
  /// a way to reach that field, so it comes with a shortcut. Set for a blocker
  /// (no cloud key) and for the failures [_settingsCanFix] admits.
  bool _statusOffersSettings = false;

  /// What the selected backend costs even when it works -- currently
  /// "your photos leave this machine" (decision 0011 puts that at the point of
  /// selection). Null for the local default, which is nagged at about
  /// nothing. Its blocking sibling rides [_status] instead, so a backend
  /// that cannot run says the same sentence here as it will at the failure.
  String? _backendWarning;

  /// The way out of [_backendWarning], which differs by platform -- see
  /// [privacyAdvice]. Set from the same [BackendCheck] as the warning, never
  /// separately: an action left over from a backend the user has since
  /// switched away from is worse than none.
  String? _backendAdvice;

  /// What this run does with the titles it reads, once the user has said
  /// (T-0230). Null until they do, and that is the whole of the default rule:
  /// an unpicked mode follows the credentials, so storing either catalogue
  /// credential in Settings switches the next run to matching without a
  /// second gesture, while a mode the user picked outlives that trip.
  ///
  /// Deliberately not persisted, and not a [ProviderSettings] field. The
  /// backend is configuration -- which service this app talks to at all --
  /// and survives a restart for that reason; this is a property of one run,
  /// like the photos in it and the Stop that ended it. Its restart default is
  /// derived from something that IS persisted (the credentials), so nothing
  /// is silently forgotten: the only state a restart drops is "I have
  /// credentials and skipped them this once", which is what "this once"
  /// means.
  TitleMatching? _matchingChoice;

  TitleMatching get _matching =>
      _matchingChoice ??
      (_settings.hasAnyCatalogue
          ? TitleMatching.matched
          : TitleMatching.keyless);

  ProviderSettings get _settings => widget.settings;

  bool get _busy => _running || _picking;

  bool get _stopping => _stop?.isStopped ?? false;

  @override
  void initState() {
    super.initState();
    // A stored backend is a selection in force, not the absence of one, so the
    // screen owes the same notice on the first frame as on a tap (T-0076).
    // No blocker here: at launch nothing has been done for it to report on.
    _readBackendNotice();
  }

  /// What the backend in force costs, from the single entry point (T-0040).
  /// Assigns rather than notifies -- its callers are already inside a
  /// `setState`, or are [initState].
  ///
  /// [answeringAnAction] adds the blocker half. A condition may greet the
  /// user, a report about an action may not (T-0076): [_status] carries an
  /// `Open settings` button and the wording of a failed scan, so only a tap
  /// on the switch and a return from Settings take it, never the first frame.
  /// It is assigned and never merged, so a failure written before a trip to
  /// Settings cannot outlive the trip -- what comes back is the condition as
  /// it is now, which for a fixed one is nothing at all.
  void _readBackendNotice({bool answeringAnAction = false}) {
    final check = ProviderPolicy.check(_settings);
    _backendWarning = check.warning;
    _backendAdvice = check.advice;
    if (!answeringAnAction) return;
    // The same status line and the same "Open settings" shortcut the scan's
    // own failure uses (T-0010): one message, several moments.
    _status = check.blocker ?? '';
    _statusOffersSettings = !check.canRun;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(settings: _settings, store: widget.store),
    ));
    if (!mounted) return;
    // Coming back is an action, and often one the blocker itself asked for
    // (T-0079): a user sent here to add a key who did not add one is owed the
    // message again, not silence until the scan dies of it.
    setState(() => _readBackendNotice(answeringAnAction: true));
  }

  /// One dialog at a time, and one row per file (T-0116).
  ///
  /// The guard is in here rather than only on the button: the button goes
  /// disabled on the next frame, and the owner got a stack of explorers out of
  /// presses inside that frame. The order of `_photos` was the worse half --
  /// two dialogs resolve in whichever order they are closed, and both append.
  Future<void> _pickPhotos() async {
    // TODO: camera capture (image_picker).
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final chosen = await widget.picker.pickPhotos();
      if (chosen == null || !mounted) return;

      setState(() => _rejected.clear());
      final picked = await loadPickedPhotos(
        chosen,
        decodeHeic: widget.debugHeicDecoder ?? platformHeicDecoder,
        onConverting: (name) {
          if (mounted) setState(() => _converting = name);
        },
      );
      if (!mounted) return;
      setState(() {
        for (final photo in picked.photos) {
          // By name, because that is the identity the rest of the pipeline
          // uses: `source_photo` keys every detection and the review screen
          // groups rows by it, so two rows for one name are two shelves as
          // far as anything downstream can tell.
          if (_photos.any((chosen) => chosen.name == photo.name)) {
            _rejected.add(RejectedPhoto(
                name: photo.name,
                reason: 'already in the list -- adding it again would scan '
                    'the same photo twice'));
          } else {
            _photos.add(photo);
          }
        }
        _rejected.addAll(picked.rejected);
      });
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          _converting = '';
        });
      }
    }
  }

  /// Add a folder of games, films and anime, from its own control (T-0161,
  /// T-0345, T-0430).
  ///
  /// Behind the same [_picking] guard as [_pickPhotos] and for the same
  /// reason, which here also covers one control being pressed while the
  /// other's dialog is open.
  ///
  /// **The steering is the interesting part, not the picker.** A file name
  /// cannot say whether an installer installs a game or an application, and
  /// over a `Downloads` folder the source titles every installer it finds
  /// without one of them being a game (T-0158). Nothing downstream can recover
  /// from that,
  /// so three things happen before an entry is read: the control says which
  /// folder it wants, the dialog repeats it, and a folder that holds whatever
  /// was put in it is questioned by name before it is added.
  ///
  /// **The prompt is ordered steer first, accumulation second (T-0430).** It
  /// is the dialog's window caption, so a caption longer than the window is
  /// ellipsised from the right -- what is at the front survives a truncation
  /// nothing here can measure without a real dialog.
  Future<void> _pickFolder() async {
    if (_picking) return;
    setState(() => _picking = true);
    var path = '';
    try {
      path = await widget.picker.pickFolder(
            prompt: 'Pick a folder your games are installed in or your films '
                'and anime are kept in -- you can add more than one',
          ) ??
          '';
      if (path.isEmpty || !mounted) return;

      setState(() => _rejected.clear());
      if (_folders.any((folder) => folder.path == path)) {
        setState(() => _rejected.add(RejectedPhoto(
            name: path,
            reason: 'already in the list -- adding it again would read the '
                'same folder twice')));
        return;
      }
      if (folderConcern(path) case final concern?) {
        if (!await _confirmFolder(path, concern) || !mounted) return;
      }
      final folder = await (widget.debugFolderReader ?? readMediaFolder)(path);
      if (!mounted) return;
      setState(() => _folders.add(folder));
    } on Object catch (e) {
      // The walk is the app's own I/O, so a failure here has no pipeline
      // warning to ride on and is named where the picker's other refusals are.
      if (mounted) {
        setState(() => _rejected
            .add(RejectedPhoto(name: path.isEmpty ? '?' : path, reason: '$e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// The question a folder full of other things is asked, before it is read.
  ///
  /// Questioned rather than refused: a user who does keep their games in
  /// `Downloads` is wrong about tidiness, not about their own machine. What
  /// may not happen is their adding it and finding out at review, where a
  /// screenful of applications looks exactly like games nobody recognises.
  Future<bool> _confirmFolder(String path, String concern) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('folder-concern'),
        title: Text('Read games, films and anime out of $path?'),
        content: Text(concern),
        actions: [
          TextButton(
            key: const Key('folder-concern-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Pick another folder'),
          ),
          FilledButton(
            key: const Key('folder-concern-accept'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Read it anyway'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// Behind [_busy] for [_removePhoto]'s reason: the run walks this list, and
  /// a pick appends to it after an await having already checked it.
  void _removeFolder(MediaFolder folder) {
    if (_busy) return;
    setState(() => _folders.remove(folder));
  }

  /// Add the GOG library, from its own control (T-0179).
  ///
  /// **Its own control and not a second use of "Add media folder"**, on the
  /// same test T-0115 and T-0118 set when they each removed a control for
  /// duplicating one beside it: those two were second routes to the *same*
  /// function, and these two are not. A folder is a path the user chooses and
  /// is questioned about; the library is one known file with nothing to pick.
  /// A folder holds what is installed; the library holds what is owned,
  /// including what is not installed, which is the whole reason it exists. A
  /// folder is read now; the library is a cache of the last sync and says so
  /// before its rows are counted. And they fail differently -- a folder full
  /// of applications against a database that is absent, stale or on a machine
  /// Galaxy does not run on. The CLI settled the same question the same way,
  /// with `scan-library` a sibling of `scan-installs` rather than a flag on it
  /// (T-0177).
  ///
  /// Behind the same [_picking] guard as the two pickers, and pressable while
  /// already added: it answers by name rather than going dead, so a press that
  /// does nothing says why.
  Future<void> _addLibrary() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _rejected.clear();
    });
    try {
      if (_library != null) {
        setState(() => _rejected.add(RejectedPhoto(
            name: _libraryLabel,
            reason: 'already in the list -- remove it first to read Galaxy '
                'again')));
        return;
      }
      final library = await (widget.debugLibraryReader ?? readGalaxyLibrary)();
      if (!mounted) return;
      setState(() => _library = library);
    } on Object catch (e) {
      // Where the picker's other refusals go. The reader's platform refusal
      // no longer arrives here: since T-0344 the control is not offered where
      // [_noGalaxy] answers, so what lands here is a database absent, locked
      // or unreadable on a host that could have had one.
      if (mounted) {
        setState(() =>
            _rejected.add(RejectedPhoto(name: _libraryLabel, reason: '$e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Behind [_busy] for [_removeFolder]'s reason.
  void _removeLibrary() {
    if (_busy) return;
    setState(() => _library = null);
  }

  /// Every source this run reads, each stated by the screen rather than
  /// inferred downstream from an entry's name: the two produce different rows
  /// from the same file name, and only this screen knows which list an entry
  /// came out of (T-0179).
  List<SourceRun> _sourceRuns() => [
        if (_folders.isNotEmpty)
          SourceRun(const InstalledGameSource(),
              [for (final folder in _folders) ...folder.entries]),
        if (_library case final library?)
          SourceRun(const GogLibrarySource(), library.entries),
      ];

  bool get _hasInput =>
      _photos.isNotEmpty || _folders.isNotEmpty || _library != null;

  /// Take a mis-picked photo back out before it costs a vision call -- ~25 s
  /// on the local model, money on a cloud one, and a shelf's worth of rows to
  /// reject at review (T-0138).
  ///
  /// Behind [_busy], which is the same gate Add photos is behind and for the
  /// same reason: a run walks `_photos`, and a pick appends to it after an
  /// await having already checked it for duplicates. A removal landing in
  /// either window changes the list under a decision that was already made.
  void _removePhoto(PhotoInput photo) {
    if (_busy) return;
    setState(() => _photos.remove(photo));
  }

  /// Push the held review, then rebuild: the review screen writes its marks
  /// straight into [_HeldReview.document], so the panel's counts are stale by
  /// the time it pops.
  Future<void> _openReview() async {
    final held = _review;
    if (held == null) return;
    final lost = _lostPhotos(held.document);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          document: held.document,
          resolver: held.resolver,
          keyless: held.keyless,
          failedPhotos: lost.failed,
          notLookedAtPhotos: lost.notLookedAt,
          // The same list, not a copy: the review screen shows each group
          // of rows against the shelf it was read off, and the document
          // holds photo names only (T-0042).
          photos: _photos,
          // For the same reason as [photos], and it is the only place the
          // paths exist: a row carries the entry it was read from and no
          // source row carries the folder that was chosen (T-0161).
          folders: [for (final folder in _folders) folder.path],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// The one moment a held review is destroyed, so it is the one moment the
  /// user is asked (T-0117). Deliberately not on Back, which is now a pop and
  /// costs nothing: a dialog on every exit is one people learn to dismiss
  /// unread, and it would then be unread here too.
  Future<bool> _confirmReplace(_HeldReview held) async {
    final decided = held.decided;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('rescan-confirm'),
        title: const Text('Replace the current review?'),
        content: Text(
          decided == 0
              ? 'The last scan is still open for review, and nothing in it is '
                  'marked yet. Scanning again replaces it.'
              : 'You have marked $decided item${decided == 1 ? '' : 's'} in '
                  'the last scan. Scanning again replaces that review, '
                  '${decided == 1 ? 'that mark' : 'those marks'} included.',
        ),
        actions: [
          TextButton(
            key: const Key('rescan-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('rescan-replace'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Scan again'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// Everything this run has to say that did not stop it: the pipeline's own
  /// warnings (T-0030) and the endpoint's adjustment notes (T-0110), in one
  /// list under T-0114's "From this scan:" heading. Shared rather than copied
  /// so the note reaches the panel in the provider's words -- it is the only
  /// thing that knows what was refused, what went instead and what that costs
  /// (T-0139), and a run at an unstated sampling is exactly what may not be
  /// rephrased into a shorter sentence here.
  ///
  /// A note can arrive before the first photo finishes, which is why the list
  /// is cleared in [_runScan] rather than on arrival of the first entry.
  /// [Severity.failure] is right for both of this method's own callers, and it
  /// is not the default arriving by omission (T-0222). A pipeline warning
  /// carries its own class and comes in through [_addScanWarning]; what reaches
  /// here instead is an endpoint's adjustment note, and a run at a sampling the
  /// endpoint chose rather than the one asked for is something the run wanted
  /// and did not get (T-0139).
  void _addWarning(String message) =>
      _addScanWarning(ScanWarning(message, severity: Severity.failure));

  void _addScanWarning(ScanWarning warning) =>
      setState(() => _warnings.add(warning));

  Future<void> _runScan() async {
    // The new scan wins if it is confirmed: the user asked for it by name,
    // and the alternative -- refusing to scan until the old review is dealt
    // with -- would make exporting a precondition of taking a photo. It wins
    // only once it has a document, though; a run that fails every photo
    // replaces nothing, which is why the assignment is at the bottom of the
    // try and not here.
    final held = _review;
    if (held != null && !await _confirmReplace(held)) return;
    if (!mounted) return;

    final stop = StopToken();
    setState(() {
      _running = true;
      _stop = stop;
      _statusOffersSettings = false;
      _status = '';
      _stage = 'starting';
      _done = 0;
      _total = 0;
      _warnings.clear();
    });

    try {
      // Built once and handed to both the scan and the review screen: an
      // item added by hand at review resolves through exactly the same
      // resolver (and the same "no credentials means skip" rule) as one the
      // model read off a photo.
      final resolver = ProviderPolicy.buildResolver(_settings,
          aliases: widget.aliases, matching: _matching);
      // No photos means no vision provider is built at all, so a folder-only
      // run needs no key, no endpoint and no backend that can run -- which is
      // the whole difference between the two inputs, made structural rather
      // than promised. `resolveOnly` has no vision worker, so it provably
      // cannot make a call.
      final orchestrator = _photos.isEmpty
          ? Orchestrator.resolveOnly(resolverWorker: resolver)
          : Orchestrator(
              // No `secondReader:`, and no setting that could ask for one
              // (T-0061): one vision call per photo, so a local run sends no
              // photo anywhere. Measurement and reasoning on ProviderPolicy.
              visionWorker: VisionWorker(
                widget.debugVisionProvider ??
                    widget.debugVisionProviderBuilder?.call(_addWarning) ??
                    ProviderPolicy.build(_settings,
                        onRequestAdjusted: _addWarning),
              ),
              resolverWorker: resolver,
              visionConcurrency:
                  ProviderPolicy.visionConcurrency(_settings.backend),
            );

      final doc = await orchestrator.runScan(
        _photos,
        sources: _sourceRuns(),
        stop: stop,
        progress: ScanProgress(
          onStage: (stage) => setState(() {
            _stage = stage;
            _done = 0;
            _total = 0;
          }),
          onItem: (stage, done, total) => setState(() {
            _stage = stage;
            _done = done;
            _total = total;
          }),
          onWarning: _addScanWarning,
        ),
      );
      if (!mounted) return;
      setState(() => _review = _HeldReview(document: doc, resolver: resolver));
      // A stopped run does not push the review screen over the top of its own
      // account of itself: what was read, and which shelves are not in it, is
      // news the user asked for by pressing Stop. The review is held, and the
      // resume panel below is the way into it.
      if (stop.isStopped) {
        setState(() => _status = _stoppedSummary(doc, _lostPhotos(doc).all));
      } else {
        await _openReview();
      }
    } on ScanStoppedException catch (e) {
      // Nothing survived, so there is no review to resume and this line is the
      // whole report -- the sentence the orchestrator wrote, as the CLI would
      // print it. No settings shortcut: a stop is not a condition to fix.
      setState(() => _status = e.message);
    } on StateError catch (e) {
      // The blocker, arriving late: `build` throws the very string `check`
      // offers at the tap, one constant rather than two wordings of one
      // condition (T-0040), so this branch shows it as it is.
      setState(() {
        _status = e.message;
        _statusOffersSettings = true;
      });
    } on ScanFailedException catch (e) {
      // Every photo failed, so no review screen opens to carry the news and
      // this line is the whole report (T-0072) -- the same sentence the CLI
      // prints bare, and it needs no more introduction here than it does
      // there. `any`, not `every`: the button offers a fix that exists, it
      // does not diagnose every photo.
      setState(() {
        _status = e.message;
        _statusOffersSettings =
            e.failures.any((failure) => _settingsCanFix(failure.$2));
      });
    } catch (e) {
      // The only branch with no author for its sentence: nothing on the way
      // recognised this, so `$e` may be any object's `toString`. It says no
      // more than it knows -- the try also covers opening the review screen,
      // so this is not always about the photos -- and offers no route, since
      // an unrecognised failure cannot be claimed to be a Settings one.
      setState(() => _status = 'The scan could not finish: $e');
    } finally {
      setState(() {
        _running = false;
        _stop = null;
      });
    }
  }

  /// Stop the run without pretending anything else about it.
  ///
  /// The bar stays, the Scan button stays disabled and the run stays `_running`
  /// until it actually returns: what is in flight is still in flight, bounded
  /// by one vision call (`visionCallTimeout`, 120 s), and a screen that went
  /// idle here would say the spending had stopped before it had.
  void _requestStop() => setState(() => _stop?.stop());

  /// What a stopped run leaves behind, in the line the user reads on the way
  /// out of it. Both halves are counted from the document rather than from the
  /// stop, so it cannot claim a photo was skipped that was in fact read.
  String _stoppedSummary(ReviewDocument doc, List<String> lost) {
    final games = doc.games.length;
    final total = doc.photos.length;
    final kept = 'Stopped. $games item${games == 1 ? '' : 's'} from '
        '${total - lost.length} of $total photo${total == 1 ? '' : 's'} '
        '${games == 1 ? 'is' : 'are'} in the review below.';
    if (lost.isEmpty) return kept;
    return '$kept Nothing from ${lost.join(', ')} is in it -- the warning for '
        '${lost.length == 1 ? 'it' : 'each'} says why.';
  }

  /// Whether Settings holds a field that could change the outcome of [error].
  ///
  /// Two questions, because a vision call fails in two ways, and neither is
  /// answered here any more: each failure carries its own answer and this is
  /// the switch that reads it.
  ///
  /// A call that reached an HTTP status is judged by what its sentence blames
  /// ([UserSetCause], T-0169). This used to be a status allowlist, and the
  /// four 200-shape sentences broke it in both directions at once: three of
  /// them end on the model id, a Settings field, and the fourth says the model
  /// id is fine -- one status, both answers. The status the sentence's author
  /// chose could not carry the fact, the sentence's text must not (matching on
  /// it is the coupling T-0140 and T-0145 deleted), so the author says it. The
  /// per-status reasoning moved to `visionApiFailure` and `ollamaFailure`, with
  /// the sentences it is about.
  ///
  /// A call that reached no status at all is judged by whose address it was:
  /// nothing answered, so neither the key nor the model id can be what failed
  /// and the URL is the only Settings field left. Each provider answers that
  /// about its own address on [UnreachableEndpoint], so this is one arm rather
  /// than one per provider and a new provider's class inherits the rule instead
  /// of falling through it silently (T-0105). Still two arms rather than one:
  /// folding them would mean core's [UnreachableEndpoint] gaining a second name
  /// for `endpointIsUserSet`, which is a rename of a settled fact and not a
  /// gain.
  ///
  /// What belongs here rather than in core is why a `false` answer is left
  /// alone -- Anthropic's sentence already reads "there is nothing to correct
  /// in your settings", and a button under it would contradict the paragraph
  /// above it.
  static bool _settingsCanFix(Object error) => switch (error) {
        UserSetCause(:final causeIsUserSet) => causeIsUserSet,
        UnreachableEndpoint(:final endpointIsUserSet) => endpointIsUserSet,
        _ => false,
      };

  /// Which of the chosen photos contributed nothing to [doc], and which of the
  /// two reasons each one is missing for.
  ///
  /// Read off the document, which names both classes since T-0145. Until then
  /// this matched the orchestrator's warning sentence with `startsWith`, so
  /// a rewording in core -- or any other warning that happened to open the
  /// same way -- decided which banner a photo landed under.
  ///
  /// The walk is over [ReviewDocument.photos] rather than over the two lists so
  /// that [_LostPhotos.all] stays in the order the photos were passed, which is
  /// the order the stopped summary names them in.
  _LostPhotos _lostPhotos(ReviewDocument doc) {
    final failed = doc.failedPhotos.toSet();
    final notLookedAt = doc.notLookedAtPhotos.toSet();
    final lost = _LostPhotos();
    for (final name in doc.photos) {
      if (failed.contains(name)) {
        lost.failed.add(name);
      } else if (notLookedAt.contains(name)) {
        lost.notLookedAt.add(name);
      } else {
        continue;
      }
      lost.all.add(name);
    }
    return lost;
  }

  /// Answer at the tap (T-0040). Everything the user needs to hear about a
  /// backend -- that it cannot run, and that it ships their photos off the
  /// machine -- is already in [_settings]; before this the first of the two
  /// waited for the Scan button and the second was never said here at all.
  Future<void> _switchBackend(VisionBackend backend) async {
    setState(() {
      _settings.backend = backend;
      _readBackendNotice(answeringAnAction: true);
    });
    // The quick switch is a real setting too, so it survives a restart.
    try {
      await widget.store.save(_settings);
    } on Object {
      // Persisting the choice is best-effort; the run itself uses the
      // in-memory value either way. Settings reports storage failures.
    }
  }

  /// Pipeline stage names as the user should read them. Falls back to the
  /// raw name so a stage added to the orchestrator later still shows up
  /// rather than disappearing from the bar.
  ///
  /// `resolve` said "Matching against IGDB" until T-0367 and named a
  /// catalogue this run may never touch: films go to TMDB, and a run keyed by
  /// a token alone reaches IGDB not at all. It is one label for every
  /// combination, so it names the stage rather than the service -- which
  /// catalogue answered a given row is the review screen's to say.
  static const _stageLabels = {
    'starting': 'Starting',
    'vision': 'Reading photos',
    'source': 'Reading folders',
    'dedupe': 'Merging duplicates',
    'resolve': 'Matching titles',
  };

  /// Determinate wherever the stage supplies a total. `dedupe` supplies none
  /// and neither does the moment before the first stage callback, so those
  /// run indeterminate -- a bar pinned at zero for a stage of a ~80 s run
  /// is the hang this replaces.
  ///
  /// The Stop control lives here rather than beside Scan because this panel
  /// exists exactly while a run does (T-0121): there is no state in which it
  /// is on screen with nothing to stop.
  Widget _progressPanel() {
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final counted = _total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_stageLabels[_stage] ?? _stage, style: labelStyle),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(counted ? '$_done / $_total' : 'working...',
                      style: labelStyle),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    key: const Key('scan-stop'),
                    onPressed: _stopping ? null : _requestStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    // The stopping label is not decoration: what is in flight
                    // can take another vision call to come back, and a button
                    // that read "Stop" throughout would invite a second press
                    // against a run that is already stopping.
                    label: Text(_stopping ? 'Stopping...' : 'Stop'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            key: const Key('scan-progress'),
            value: counted ? _done / _total : null,
          ),
        ],
      ),
    );
  }

  /// A heading for one of the two red panels, saying which run it is about.
  ///
  /// The two look alike and only one of them clears when a scan starts, which
  /// is what the owner read as the error log not being cleared at all
  /// (T-0122). The wording is the difference: a scan's warnings are about the
  /// run that just ended, a picker rejection is about a file that is still
  /// rejected (T-0039).
  Widget _panelHeading(String text, Key key, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          key: key,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color ?? Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
        ),
      );

  /// Warnings as they arrive, newest first, so a photo that just died is on
  /// screen while the rest of the run continues.
  ///
  /// **Two sections, and the heading of each is what separates them (T-0222).**
  /// The first real scan produced four lines, every one of them a
  /// documented exclusion, all in `colorScheme.error` under one heading that
  /// said only "From this scan:" -- and asked what the errors were. Nothing had
  /// failed. So the class is named in words: colour and icon are the second and
  /// third signals here, never the only one, which is T-0043's rule and the
  /// reason a screen reader gets the same answer a sighted reader does.
  ///
  /// Failures first and exclusions under them, against the newest-first order
  /// inside each: the panel is capped at 120px and scrolls, and the run's
  /// silences are the great majority by count, so below them a real failure
  /// is a line nobody scrolls to.
  ///
  /// Height-capped and scrollable because the resolve stage can warn once
  /// per detection, and the three control photographs make many.
  Widget _warningList() {
    final scheme = Theme.of(context).colorScheme;
    final failures = [
      for (final warning in _warnings.reversed)
        if (warning.severity == Severity.failure) warning,
    ];
    final exclusions = [
      for (final warning in _warnings.reversed)
        if (warning.severity == Severity.exclusion) warning,
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 120),
      child: ListView(
        key: const Key('scan-warnings'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (failures.isNotEmpty) ...[
            _panelHeading('Went wrong in this scan:',
                const Key('scan-warnings-heading')),
            for (final warning in failures)
              _warningRow(warning, Icons.warning_amber, scheme.error),
          ],
          if (exclusions.isNotEmpty) ...[
            // Padded off the section above it rather than ruled off: one
            // divider inside a 120px scroller reads as the end of the panel.
            if (failures.isNotEmpty) const SizedBox(height: 10),
            _panelHeading(
              'Left out of this scan on purpose, nothing wrong:',
              const Key('scan-exclusions-heading'),
              color: scheme.onSurfaceVariant,
            ),
            for (final warning in exclusions)
              // Not a warning triangle: a struck-through filter is the one
              // shape at 18px that reads as "left out on purpose" rather than
              // as a smaller alarm.
              _warningRow(warning, Icons.filter_alt_off_outlined,
                  scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
  }

  Widget _warningRow(ScanWarning warning, IconData icon, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(warning.message, style: TextStyle(color: color)),
          ),
        ],
      );

  /// Files the picker let the user choose and the app then could not read.
  ///
  /// At the picker, not at the provider call: a HEIC that reaches Anthropic
  /// declared `image/jpeg` fails minutes later and blames the wrong thing.
  ///
  /// Outlives a scan, unlike [_warningList], because the file is still
  /// rejected after one (T-0039); the heading is what says so.
  Widget _rejectedPanel() {
    final error = Theme.of(context).colorScheme.error;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 120),
      child: ListView(
        key: const Key('rejected-photos'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _panelHeading('From your last pick, not from a scan:',
              const Key('rejected-photos-heading')),
          for (final file in _rejected)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.broken_image_outlined, size: 18, color: error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${file.name} -- ${file.reason}',
                      style: TextStyle(color: error)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The way back into the last scan (T-0117), and the only thing on this
  /// screen that says a review exists at all.
  ///
  /// It carries the counts rather than a bare button because it is also the
  /// answer to "did my marks survive?" -- a user who has just pressed Back on
  /// work they thought was gone reads the number, not the label.
  Widget _resumeReviewPanel(_HeldReview held) {
    final games = held.document.games.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        key: const Key('resume-review'),
        children: [
          const Icon(Icons.fact_check_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Last scan: $games item${games == 1 ? '' : 's'}, '
                '${held.decided} marked'),
          ),
          TextButton.icon(
            key: const Key('resume-review-button'),
            onPressed: _busy ? null : _openReview,
            icon: const Icon(Icons.rate_review),
            label: const Text('Resume review'),
          ),
        ],
      ),
    );
  }

  /// What the chosen backend implies, and what to do about it. Same icon,
  /// colour and shape as the two panels above rather than a third kind of
  /// banner; not scrollable because there is only ever one of these.
  ///
  /// The advice is its own line under the risk, not appended to it (T-0070):
  /// this row is read in passing on the way to the Scan button, and the one
  /// clause the user can act on has to survive that. It is also the only
  /// clause here that changes with the platform.
  Widget _backendWarningPanel(String warning, String? advice) {
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        key: const Key('backend-warning'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 18, color: error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(warning, style: TextStyle(color: error)),
                if (advice case final advice?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      advice,
                      key: const Key('backend-advice'),
                      style:
                          TextStyle(color: error, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The keyless run, offered as a mode rather than reached by leaving a
  /// field blank (T-0230).
  ///
  /// Here and not in Settings, for two reasons. It is a property of the run,
  /// and the run starts on this screen -- Settings persists everything it
  /// holds, so a per-run control there would be the one thing its Save did
  /// not save. And it is the screen a person is on before they scan, so the
  /// mode is met rather than looked for: the same test T-0115 set when it
  /// took the backend selector off Settings and left the statement behind.
  ///
  /// Plain rather than the coloured panel the backend warning uses: choosing
  /// keyless costs no privacy and risks nothing, it changes what the export
  /// can carry. Colouring it like the upload warning would say those two are
  /// the same kind of news.
  Widget _matchingPanel() {
    final check = ProviderPolicy.checkMatching(_settings, _matching);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<TitleMatching>(
            key: const Key('title-matching'),
            showSelectedIcon: false,
            segments: [
              for (final option in TitleMatching.values)
                ButtonSegment(value: option, label: Text(option.label)),
            ],
            // What was asked for, not what [check] says will happen: the
            // gap between the two is exactly what the sentence below is for,
            // and a control that silently re-selects itself cannot say it.
            selected: {_matching},
            onSelectionChanged: (selection) =>
                setState(() => _matchingChoice = selection.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              check.consequence,
              key: const Key('title-matching-consequence'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// The three input lists, in the order a run reads them.
  List<Widget> _inputRows() => [
        for (final photo in _photos)
          ListTile(
            leading: const Icon(Icons.photo),
            title: Text(photo.name),
            trailing: IconButton(
              key: Key('remove-photo-${photo.name}'),
              tooltip: 'Remove ${photo.name}',
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => _removePhoto(photo),
            ),
          ),
        for (final folder in _folders)
          ListTile(
            leading: const Icon(Icons.folder),
            title: Text(folder.name),
            // The path, because two folders one level apart have
            // the same name; the count, because it is what says
            // a folder of four thousand things was picked before
            // the scan says it.
            subtitle: Text('${folder.path} -- '
                '${folder.entries.length} '
                'entr${folder.entries.length == 1 ? 'y' : 'ies'} '
                'to read'),
            trailing: IconButton(
              key: Key('remove-folder-${folder.path}'),
              tooltip: 'Remove ${folder.name}',
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => _removeFolder(folder),
            ),
          ),
        if (_library case final library?)
          ListTile(
            key: const Key('library-input'),
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text(_libraryLabel),
            // The staleness note in full, in front of the row
            // count rather than after it: what this file is a
            // cache of decides whether the count means anything,
            // and nothing in the database dates its own sync
            // (T-0177).
            subtitle: Text('${library.entries.length} '
                'release${library.entries.length == 1 ? '' : 's'}'
                ' to read -- ${galaxyStalenessNote(library)}'),
            trailing: IconButton(
              key: const Key('remove-library'),
              tooltip: 'Remove $_libraryLabel',
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : _removeLibrary,
            ),
          ),
      ];

  /// What the run has to say about itself, below the inputs and above the
  /// buttons in either layout. One list rather than two copies: the empty
  /// screen and a screen with inputs show the same panels, and a second copy
  /// is a second thing to forget.
  List<Widget> _runPanels() => [
        if (_converting.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              key: const Key('converting-photo'),
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Converting $_converting...')),
              ],
            ),
          ),
        if (_rejected.isNotEmpty) _rejectedPanel(),
        if (_running) _progressPanel(),
        if (_warnings.isNotEmpty) _warningList(),
        if (_review case final held?) _resumeReviewPanel(held),
        // Directly above the status line: for a backend that both
        // leaks photos and cannot run, the two halves of the answer
        // read as one.
        if (_backendWarning case final warning?)
          _backendWarningPanel(warning, _backendAdvice),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_status,
                    key: const Key('scan-status'), textAlign: TextAlign.center),
                if (_statusOffersSettings)
                  TextButton.icon(
                    key: const Key('status-open-settings'),
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open settings'),
                  ),
              ],
            ),
          ),
        // Last, so it sits directly above the Scan button it governs -- and
        // so that nothing already on this list moves when it appears. This
        // screen has three measured overflows behind it (T-0161, T-0179 and
        // the empty-state one below), and a panel inserted above the others
        // pushed the resume-review button and the status line's own shortcut
        // out of an 800x600 viewport: still built, still found, no longer
        // tappable (measured 2026-08-22, `flutter test`).
        //
        // Not while a run is in flight: its mode was fixed when it started,
        // and a live control over a settled fact invites a tap that cannot
        // do anything.
        if (!_running) _matchingPanel(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('shelfscan'),
        actions: [
          if (ProviderPolicy.available.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<VisionBackend>(
                showSelectedIcon: false,
                // From the policy, not a hand-written list: a backend this
                // list forgot is a stored setting the button cannot render.
                // Icon-only -- three labelled segments do not fit an app bar.
                segments: [
                  for (final backend in ProviderPolicy.available)
                    ButtonSegment(
                      value: backend,
                      icon: Icon(backendIcon(backend)),
                      tooltip: backend.label,
                    ),
                ],
                selected: {_settings.backend},
                onSelectionChanged: _running
                    ? null
                    : (selection) => _switchBackend(selection.first),
              ),
            ),
          // The same 8 the SegmentedButton beside it already carries, so the
          // gear's gap to the window edge is the gap between the two controls
          // rather than nothing at all (T-0114).
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: const Key('open-settings'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: _running ? null : _openSettings,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // One scroll region for everything above the buttons: the inputs,
          // and everything the run has to say about itself. They were pinned
          // panels until the third input's control wrapped the button bar to
          // two lines, at which point a failed cloud run overflowed a 544 px
          // body by 16 px -- a striped bar across the Scan button and a tap
          // that misses it (measured 2026-08-16, `flutter test`). The panels
          // are the variable half and a Column cannot shrink them, so a longer
          // sentence would have done the same thing on its own.
          Expanded(
            child: !_hasInput
                ? Column(
                    children: [
                      // Scrolled for the reason the panels below are (T-0230,
                      // T-0430): this Column cannot shrink, and the sentences
                      // in it grew by two lines at 360 dp when the third kind
                      // and the plural arrived. The empty screen fitted a
                      // 360x564 body before that and a 360x604 one after,
                      // measured with `flutter test`; scrolling ends the class
                      // rather than buying back the 40 px. Centred still, and
                      // unchanged wherever it fits: a scroll view under loose
                      // constraints is exactly as tall as its child.
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Pick shelf photos to begin'),
                                // The empty screen is the first place the
                                // second input can be named, and naming the
                                // folder it wants is half of T-0161's steer
                                // away from a downloads folder. It names films
                                // because the same walk has read them since
                                // T-0162 and this line was the only place a
                                // person with a folder of them would have
                                // looked (T-0345).
                                //
                                // Plural since T-0430, and this line rather
                                // than the label beside it: the control has
                                // always appended, and the only place that
                                // said so was the list of folders, which does
                                // not exist until the first press. This is the
                                // one site a person reads BEFORE it, and it
                                // costs the button row nothing -- a longer
                                // label reflows the Wrap below, this sentence
                                // does not.
                                const Text(
                                    'or add the folders your PC games, films '
                                    'and anime are kept in -- one scan reads '
                                    'them all',
                                    key: Key('folder-hint')),
                                // The third input, named where the second one
                                // is and for the same reason: one run may hold
                                // all three, and a disc and an install of one
                                // game are one row only if they are in the same
                                // run (T-0179). Where it cannot exist, the same
                                // slot carries why instead of an offer
                                // (T-0344).
                                if (_noGalaxy case final reason?)
                                  Text(reason,
                                      key: const Key('no-library-here'))
                                else
                                  const Text(
                                      'or the GOG library this PC has synced',
                                      key: Key('library-hint')),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Flexible and scrolled, where this was a plain spread
                      // until T-0230: the empty screen had ~4 px of slack
                      // left over an 800x600 window (measured 2026-08-22,
                      // `flutter test`), so the mode panel overflowed it the
                      // moment it arrived -- the striped bar over the Scan
                      // button this file has now measured three times. The
                      // centred hint keeps its Expanded, the panels take what
                      // they need up to the half they are flexed for, and
                      // anything past that scrolls instead of being clipped.
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(children: _runPanels()),
                        ),
                      ),
                    ],
                  )
                // Scrolled, not clipped, and a Column inside a
                // SingleChildScrollView rather than a ListView: every panel is
                // built whether or not it is on screen, which is what the
                // pinned layout guaranteed and what a lazy list would take
                // away.
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        ..._inputRows(),
                        ..._runPanels(),
                      ],
                    ),
                  ),
          ),
          // SafeArea insets nothing on desktop, where the window frame is the
          // only edge there is, so the padding is additional to it.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              // A Wrap and not a Row since the third input arrived: four
              // labelled controls overflowed an 800x600 window by 95 px, which
              // is a yellow-and-black bar over the Scan button and a tap that
              // misses it (measured 2026-08-16, `flutter test`). A Wrap is one
              // row wherever they fit and two rows where they do not, which is
              // every Android phone; clipping or shortening the labels would
              // cost the naming T-0161 put in them.
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Add photos'),
                  ),
                  // Its own control, not a mode on the one beside it (a
                  // real call, 2026-08-16, and the code agrees: no vision
                  // call, no cost, no key, its own failures). It said "games"
                  // until T-0345, by which time the same walk had read films
                  // since T-0162 and the CLI's own notice already said "point
                  // this at a media folder". T-0158's
                  // every-title-an-application steer is unchanged and lives
                  // where it is read at the moment of choosing -- the picker's
                  // prompt and the concern dialog. "media" is the same 16
                  // characters, so the Wrap measures as it did -- and T-0430
                  // left the label alone for that same reason, putting "you
                  // can add more than one" in the empty screen's hint and in
                  // the prompt, neither of which this row measures.
                  TextButton.icon(
                    key: const Key('add-games-folder'),
                    onPressed: _busy ? null : _pickFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add media folder'),
                  ),
                  // The third input, and its own control for the reasons on
                  // [_addLibrary]. Absent, not disabled, where [_noGalaxy]
                  // answers.
                  if (_noGalaxy == null)
                    TextButton.icon(
                      key: const Key('add-gog-library'),
                      onPressed: _busy ? null : _addLibrary,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Add $_libraryLabel'),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || !_hasInput ? null : _runScan,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Scan'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A finished scan, held on the screen that started it.
///
/// The document itself, never a copy of the decisions: the review screen
/// writes each mark straight into `document.games`, so holding this one
/// reference is the whole of surviving Back. The resolver rides along because
/// nothing reconstructs it afterwards, and a manually added item has to go
/// through the same one the run used. The photos the run lost used to ride
/// along too; since T-0145 the document names them, so they are derived where
/// they are needed rather than held twice.
///
/// In memory only, and it dies with the process. Writing a `review.json`
/// beside it would survive a crash, but it would be a lesser document than
/// this one: the photos are bytes with no stable path on Android (T-0042),
/// so a reloaded review comes back with no images to group against and no
/// failed-photo banner, while the file itself is an unasked-for machine
/// readable inventory of a private home. The durable copy is the export,
/// which the user asks for by name.
class _HeldReview {
  _HeldReview({required this.document, required this.resolver});

  final ReviewDocument document;
  final ResolverWorker resolver;

  /// Whether this run had a resolve stage at all (T-0230).
  ///
  /// Read off the resolver the run actually used rather than held beside it
  /// as a second field: [SkipResolver] IS "nothing was looked up", it is what
  /// `buildResolver` returns for both ways of arriving at a keyless run, and
  /// a copy of the mode kept here could disagree with the document the review
  /// screen is rendering.
  ///
  /// **Said of the run and not of IGDB, which is the whole of what T-0367
  /// changed here.** The derivation is unchanged and is now the only wording
  /// that was ever true of it: a run with a TMDB token and no Twitch
  /// application looks films up, so it is not keyless, and the review
  /// screen's banner -- *nothing was looked up* -- would be false over it.
  /// Its game rows are keyless per kind instead, which is the state T-0308
  /// already made ordinary and the review screen already marks per row.
  bool get keyless => resolver is SkipResolver;

  /// Every row the user has ruled on, approved and rejected alike. Not the
  /// exporters' `approved`/`edited` rule, which lives in one place on the
  /// review screen: what is at stake here is the work, not the output.
  int get decided =>
      document.games.where((g) => g.status != ReviewStatus.pending).length;
}

/// The photos a run left out of its document, by why (T-0140).
///
/// One run can produce both: a photo dies, and Stop then reaches the rest.
/// [all] is the two together in the order the photos were passed, which is the
/// order the stopped summary names them in.
class _LostPhotos {
  final List<String> failed = [];
  final List<String> notLookedAt = [];
  final List<String> all = [];
}
