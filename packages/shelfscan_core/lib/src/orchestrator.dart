/// Pipeline orchestrator. Stage order is in ARCHITECTURE.md.
///
/// The orchestrator never talks to external APIs itself: all I/O with the
/// vision model and IGDB lives in workers/providers, which keeps stages
/// independently testable and lets a provider be swapped without touching
/// pipeline logic. It is likewise UI-agnostic -- it reports through
/// [ScanProgress] and returns the document; persisting to disk and rendering
/// progress are the caller's job (CLI or Flutter app).
library;

import 'models.dart';
import 'providers/igdb.dart';
import 'providers/vision.dart';
import 'title_key.dart';
import 'workers/base.dart';
import 'workers/resolver.dart';
import 'workers/vision.dart';

/// Progress callbacks so the Flutter UI can render a live pipeline view.
class ScanProgress {
  ScanProgress({this.onStage, this.onItem, this.onWarning});

  /// e.g. "vision", "dedupe", "resolve".
  final void Function(String stage)? onStage;

  final void Function(String stage, int done, int total)? onItem;

  /// Everything non-fatal the run has to say, each line carrying which of
  /// [Severity]'s two things it is.
  final void Function(ScanWarning warning)? onWarning;
}

/// One line for the user, and what it means (T-0222).
///
/// A [String] until T-0222, which is how a scan's documented exclusions
/// reached the screen as `colorScheme.error` and were read as errors. The
/// class is a field rather than something a shell recovers from [message]:
/// the one time this screen inferred a class from the orchestrator's wording,
/// a rewording in core changed the UI's behaviour (T-0145).
class ScanWarning {
  const ScanWarning(this.message, {this.severity = Severity.failure});

  /// A whole sentence, shown as it stands.
  final String message;

  /// Defaults to the loud side for [DeclinedEntry.severity]'s reason: an
  /// unstated class is not a claim that nothing went wrong.
  final Severity severity;

  /// So a shell that only wants the sentence -- and every test that collected
  /// these into a `List<String>` -- keeps reading.
  @override
  String toString() => message;
}

/// Every photo of a scan failed its vision call, so there is nothing to review.
///
/// Thrown rather than returned as an empty [ReviewDocument] because a document
/// is a claim that the shelf was read: with a mistyped model id the CLI wrote
/// one, reported `0 game(s) detected`, and exported cleanly to an empty
/// collection (T-0072). One photo of three failing is the opposite case and
/// stays a warning -- a partial result the user may well want (T-0030). The
/// line is drawn at failed CALLS, not at an empty result: a photo that was
/// read and held no game is an answer, and a shelf can legitimately scan to
/// zero.
///
/// It lives here rather than in the CLI because both shells reach the same
/// state through this method, and only this method knows how many photos
/// failed.
class ScanFailedException implements Exception {
  ScanFailedException(this.failures);

  /// Photo name and what ended it, in the order the photos were passed --
  /// never the pool's completion order, which is a race.
  final List<(String, Object)> failures;

  /// One line, because that is the shape of every other user-fixable failure
  /// in the CLI (T-0037, T-0049, T-0050, T-0051). The per-photo detail was
  /// already reported through [ScanProgress.onWarning] as each photo died; a
  /// single shared cause is repeated here because the summary is the line that
  /// gets read.
  String get message {
    final reasons = {for (final (_, error) in failures) '$error'};
    return 'All ${failures.length} photo(s) failed: nothing was read, so no '
        'review document was produced. '
        '${reasons.length == 1 ? reasons.single : 'Each photo failed '
            'differently -- see the warning for each above.'}';
  }

  @override
  String toString() => message;
}

/// A stop reached the run before any photo had been read.
///
/// A sibling of [ScanFailedException] rather than a subclass, and thrown for
/// the same reason it is: an empty [ReviewDocument] is a claim that the shelf
/// was read (T-0072). It is a separate type because a stop is not a failure --
/// nothing here is a condition to fix, and the sentence has to say who ended
/// the run. A run stopped after one photo survived is the opposite case and
/// returns a document, as a run with one dead photo does.
class ScanStoppedException implements Exception {
  ScanStoppedException({required this.notLookedAt, this.failures = const []});

  /// Photos never sent, in the order they were passed.
  final List<String> notLookedAt;

  /// Photos that died before the stop, each already reported through
  /// [ScanProgress.onWarning] as it died.
  final List<(String, Object)> failures;

  String get message {
    final failed = failures.isEmpty
        ? ''
        : ' ${failures.length} photo(s) failed before the stop -- see the '
            'warning for each above.';
    return 'Stopped before any photo was read, so no review document was '
        'produced. ${notLookedAt.length} photo(s) were not looked at: '
        '${notLookedAt.join(', ')}.$failed';
  }

  @override
  String toString() => message;
}

/// One thing a shell found that may describe a game: a file, or a directory.
///
/// The analogue of [PhotoInput], and it exists for that one's reason:
/// `shelfscan_core` is pure Dart and does not import `dart:io`
/// (ARCHITECTURE.md), so enumerating cannot happen here. The shell walks the
/// filesystem and hands the pipeline plain values -- the same split that keeps
/// HEIC conversion in `bin/` and lets the identical pipeline run on Android.
///
/// It carries no bytes, and that is the point of the whole group: nothing
/// downstream decodes an image, so a source run makes no vision call, costs
/// nothing and repeats byte for byte for free.
class SourceEntry {
  const SourceEntry({required this.name, this.container, this.content});

  /// The entry's own file or directory name, with no path around it.
  ///
  /// A path would bring `dart:io`'s separators into core through the back
  /// door, and core cannot resolve one anyway. A name is what a title is
  /// parsed out of (T-0158) and what a [DeclinedEntry] is named by.
  final String name;

  /// The directory [name] was found in, when the shell went down a level.
  ///
  /// Needed by the parser rather than merely available to the shell: an
  /// installer's real title is often only in the parent -- `Marlows Gate
  /// 3/setup_mg3_2.0.0.7.exe` (T-0158) -- and the shell cannot know which of
  /// the two names a title is in without doing the parsing itself.
  ///
  /// **A parent a title may be read off, not a path segment (T-0193).** It is
  /// read as a title whenever [name] carries none, so the only directory that
  /// belongs here is one that could be a game's own folder. The directory the
  /// user pointed the scan AT is not one: both shells passed it until T-0193,
  /// and every child of it that titled nothing came back titled after the scan
  /// root -- several at once, which stage 2 then merged into a single row
  /// reading like a real game. Null is the answer both for that and for a
  /// [name] the shell did not go down a level to find; the parser cannot tell
  /// those two apart and has no reason to.
  final String? container;

  /// The text of the metadata file the shell read for this entry, if any.
  ///
  /// What makes T-0157 possible without core opening a file: a GoG install
  /// carries `goggame-PRODUCTID.info`, JSON naming the game and GoG's product
  /// id, and parsing it is core's job while reading it is the shell's. Text
  /// rather than bytes, because choosing an encoding is a filesystem concern
  /// and nothing here decodes anything else.
  ///
  /// A directory holding SEVERAL metadata files is handed over as several
  /// entries sharing a [container] -- one content per entry, so the field
  /// stays singular and stage 2 merges the rows if they agree.
  final String? content;
}

/// What a source made of one [SourceEntry].
///
/// The second list is the whole reason this is not a bare `List<Detection>`,
/// as it is for [PhotoAnalysis]: "no rows" and "no rows, 40 archives skipped"
/// are very different answers to show a human.
class SourceReading {
  const SourceReading({this.items = const [], this.declined = const []});

  final List<Detection> items;

  /// Entries this source deliberately made no row out of ([DeclinedEntry]).
  final List<DeclinedEntry> declined;
}

/// Stage 1 for a source that is not a photograph (T-0155).
///
/// Synchronous on purpose, unlike [VisionProvider]: an implementation parses
/// text the shell has already read, so it opens nothing, waits for nothing and
/// cannot fail slowly. That is what lets the stage below run with no pool, no
/// retry and no stop check -- see [Orchestrator.runScan].
///
/// An implementation reports what it could not use through
/// [SourceReading.declined] rather than by throwing; a throw is caught and
/// declined for it, so one unreadable entry cannot end the run
/// (ARCHITECTURE.md, "a failed task never kills the run").
abstract class DetectionSource {
  SourceReading read(SourceEntry entry);
}

/// The entries of one source and the source that reads them, together because
/// neither is any use without the other and a run may have both these and
/// photographs.
///
/// One of these is one source, not one run: [Orchestrator.runScan] takes a
/// list of them, because a shell may hold a shelf, a games folder and a store
/// library at once and each is read by a different [DetectionSource] (T-0179).
class SourceRun {
  const SourceRun(this.source, this.entries);

  final DetectionSource source;
  final List<SourceEntry> entries;
}

class Orchestrator {
  Orchestrator({
    required VisionWorker this.visionWorker,
    required this.resolverWorker,
    this.visionConcurrency = 3,
    this.resolverConcurrency = igdbRequestsPerSecond,
  });

  /// Orchestrator for a run with no photographs in it: a re-resolve
  /// ([runResolve]) or a source-only scan (`runScan(const [], sources: ...)`).
  ///
  /// No vision worker exists at all, so neither provably can call a vision
  /// provider. [runScan] throws if it is handed a photo. The name predates the
  /// second caller (T-0155) and stays because both shells construct it.
  Orchestrator.resolveOnly({
    required this.resolverWorker,
    this.resolverConcurrency = igdbRequestsPerSecond,
  })  : visionWorker = null,
        visionConcurrency = 0;

  /// Null only for [Orchestrator.resolveOnly].
  final VisionWorker? visionWorker;
  final ResolverWorker resolverWorker;
  final int visionConcurrency;

  /// Lanes on the resolve stage. Defaulted to [igdbRequestsPerSecond] so the
  /// pool asks for no more than the provider will serve; it was 8 against a
  /// documented 4 until T-0064, and the numbers that cost are on that
  /// constant. Raising it no longer exceeds the limit -- [IgdbClient] holds
  /// the rate itself -- it only queues lanes behind the bucket.
  final int resolverConcurrency;

  /// Full scan pipeline: photos and non-photo sources in, review document out.
  ///
  /// [sources] is stage 1 for everything that was not photographed (T-0155),
  /// and either half may be empty: photographs alone, a folder of installs
  /// alone (on an [Orchestrator.resolveOnly], which has no vision provider to
  /// call), or both in one run. Both in one run is the case that matters --
  /// a collection can span a shelf and a disk, and only a single run puts
  /// the two through one dedupe, so a disc and an install of one game are one
  /// row rather than two documents nobody can reconcile.
  ///
  /// It is a LIST because that reconciliation is not limited to two inputs and
  /// no source can read another's entries: a games folder and a GOG library
  /// are read by different [DetectionSource]s and a run may hold both
  /// (T-0179). Which source owns an entry is therefore stated by the shell
  /// that produced it, never inferred here from the entry's name. The runs are
  /// read in the order given and their rows keep that order into stage 2.
  ///
  /// The source stage has no pool, no retry and no stop check, all three of
  /// which the vision stage needs: it makes no request, so there is nothing to
  /// overlap, nothing to rate-limit and nothing that takes long enough for a
  /// stop to arrive during it. The stop that costs on such a run is stage 3's
  /// IGDB pass, which honours it already.
  ///
  /// An entry that yields no row is NOT the empty-document case
  /// [ScanFailedException] guards (T-0072): a photo whose CALL failed was
  /// never read, while an entry a source declined was read and held no game,
  /// which is an answer. So a run whose every entry declines returns a
  /// document -- with [ReviewDocument.declinedEntries] naming all of them.
  ///
  /// [stop] ends the run at the next item either pool would have started, and
  /// reaches BOTH stages: a stop during vision leaves the resolve pool with
  /// nothing to start, so the photos already read come back as unmatched rows
  /// rather than as one fresh IGDB request per detection answering a stop.
  /// What the user
  /// keeps is every photo that finished, deduped and assembled as usual; what
  /// they lose is named twice -- through [ScanProgress.onWarning] for the user
  /// to read, and as [ReviewDocument.notLookedAtPhotos] /
  /// [ReviewDocument.failedPhotos] for a shell to act on. Nothing read at all
  /// throws [ScanStoppedException].
  Future<ReviewDocument> runScan(
    List<PhotoInput> photos, {
    List<SourceRun> sources = const [],
    ScanProgress? progress,
    StopToken? stop,
  }) async {
    final vision = visionWorker;
    if (vision == null && photos.isNotEmpty) {
      throw StateError('Orchestrator.resolveOnly has no vision worker; '
          'use runResolve(), or runScan(const [], sources: ...)');
    }

    final failures = <(int, String, Object)>[];
    final notLookedAt = <String>[];
    final detections = <Detection>[];
    final unreadable = <UnreadSpineReport>[];

    // ---- Stage 1: vision, fan out one task per photo ---------------- //
    if (vision != null) {
      progress?.onStage?.call('vision');
      var done = 0;
      // Indices rather than photos, as in [runResolve]: the pool answers in
      // completion order, and both stage-1 lists need the input position.
      final perPhoto = await runPool<int, (int, PhotoAnalysis)>(
        [for (var i = 0; i < photos.length; i++) i],
        (index) async {
          final result = await vision.run(photos[index]);
          done += 1;
          progress?.onItem?.call('vision', done, photos.length);
          return (index, result);
        },
        concurrency: visionConcurrency,
        stop: stop,
        onError: (index, error) {
          failures.add((index, photos[index].name, error));
          progress?.onWarning?.call(
              ScanWarning('Vision failed for ${photos[index].name}: $error'));
        },
      );
      // A photo the stop kept out of the pool is neither a result nor a
      // failure, so what is missing from both lists is what was never looked
      // at. Named one by one: after a stop this is the list that says which
      // shelves the review does not cover, and anything the pipeline drops is
      // named (decision 0012).
      final answered = {
        for (final (index, _) in perPhoto) index,
        for (final (index, _, _) in failures) index,
      };
      notLookedAt.addAll([
        for (var i = 0; i < photos.length; i++)
          if (!answered.contains(i)) photos[i].name,
      ]);
      // The sentence is written from the list the document then carries, so
      // the two cannot drift: T-0145 removed the app's parse of this line, and
      // a rewording that left the value behind would put the defect back.
      for (final name in notLookedAt) {
        progress?.onWarning?.call(
            ScanWarning('Stopped before $name: it was not looked at.'));
      }
      // Sorted once, here rather than inside the branch below, because the
      // document and that exception both want input order.
      failures.sort((a, b) => a.$1.compareTo(b.$1));
      if (perPhoto.isEmpty && photos.isNotEmpty) {
        final failed = [for (final (_, name, error) in failures) (name, error)];
        if (notLookedAt.isNotEmpty) {
          throw ScanStoppedException(
              notLookedAt: notLookedAt, failures: failed);
        }
        throw ScanFailedException(failed);
      }
      detections.addAll([
        for (final (_, analysis) in _orderedAnalyses(photos, perPhoto))
          ...analysis.items,
      ]);
      // Seen-but-unread spines travel beside the detections, never inside them
      // (T-0007 / T-0011).
      unreadable.addAll(_orderedUnreadable(perPhoto));
    }

    // ---- Stage 1b: sources, one entry at a time --------------------- //
    // After the photographs, so a merged row keeps the place of the earliest
    // photo that read it (_orderedAnalyses). Nothing is re-ordered here: with
    // no pool there is no completion order to undo, so the entries and their
    // rows stay exactly as the shell passed them.
    final declined = <DeclinedEntry>[];
    if (sources.isNotEmpty) {
      progress?.onStage?.call('source');
      // One count across every run, not one per source: the stage is one bar
      // to the user, and a second bar restarting at 1 would read as a second
      // stage.
      final total = sources.fold<int>(0, (sum, run) => sum + run.entries.length);
      var read = 0;
      for (final run in sources) {
        for (final entry in run.entries) {
          try {
            final reading = run.source.read(entry);
            detections.addAll(reading.items);
            declined.addAll(reading.declined);
          } on Object catch (error) {
            // A source is not supposed to throw; one that does declines the
            // entry rather than ending the run (ARCHITECTURE.md).
            declined.add(DeclinedEntry(name: entry.name, reason: '$error'));
          }
          progress?.onItem?.call('source', ++read, total);
        }
      }
      // After every run, so two sources declining for the same reason are one
      // warning rather than two -- the grouping is per run only by accident of
      // where the call sat.
      _warnDeclined(declined, progress);
    }

    // ---- Stage 2: dedupe across overlapping photos and sources ------ //
    progress?.onStage?.call('dedupe');
    final unique = dedupeDetections(detections);

    // ---- Stage 3: resolve, fan out one task per detection ----------- //
    final resolved = await runResolve(unique, progress: progress, stop: stop);

    // ---- Stage 4: assemble ------------------------------------------ //
    return ReviewDocument(
      version: 1,
      created: DateTime.now().toUtc().toIso8601String(),
      photos: photos.map((p) => p.name).toList(),
      games: resolved,
      unreadable: unreadable,
      failedPhotos: [for (final (_, name, _) in failures) name],
      notLookedAtPhotos: notLookedAt,
      declinedEntries: declined,
    );
  }

  /// Stage 3 on its own: detections in, resolved games out.
  ///
  /// Exposed separately so an existing review document can be re-resolved
  /// without re-running vision (`shelfscan resolve`). Re-running vision to
  /// measure the resolver would mix scorer changes with model
  /// non-determinism and cost; this path is repeatable and free of both.
  ///
  /// Rows come back grouped by [Detection.photoContext], photoless rows last,
  /// and inside a group in the order they arrived in [detections]. Both parts
  /// of that key are fixed before the first request leaves, so no answer can
  /// change where a row lands: two resolves of one document write
  /// byte-identical files. That is a guarantee this function can make on its
  /// own, unlike the same claim about two SCANS (see [dedupeDetections]).
  ///
  /// It did not hold before T-0068. The key was `source_photo` then confidence
  /// descending, and the local model reports confidence 1.0 for every
  /// detection (doc/measurements.md), so within a photo the whole key was
  /// constant and `List.sort` -- unstable, over a pool that returns completion
  /// order -- handed back whichever order IGDB had answered in. Three live
  /// resolves of a real hi-res document at concurrency 2 disagreed with the
  /// first run's order on a third of its rows and more; three under this key
  /// disagree in none and write the same bytes.
  ///
  /// The tie-break is the input index and not the raw title because a title
  /// does not always discriminate: dedupe deliberately keeps one title read on
  /// two photos with different platform hints as two rows (SOLAR PILGRIM VII
  /// REMAKE INTERBLOOM, twice, on that document), so two rows can share a
  /// title and tie again. An index cannot tie, it survives a human retitling a
  /// row in `review.json`, and it leaves every row where the reviewer last saw
  /// it -- sorting by title would move nearly every row of that document for
  /// no reason a reader of the diff could act on.
  /// [stop] leaves every detection it kept out of the pool as an unresolved
  /// row -- the shape a failed resolution already degrades to, so review and
  /// both exporters handle it unchanged. Dropping them instead would throw away
  /// the vision read, which is the half of the run that cost money.
  Future<List<ResolvedGame>> runResolve(
    List<Detection> detections, {
    ScanProgress? progress,
    StopToken? stop,
  }) async {
    progress?.onStage?.call('resolve');
    var done = 0;
    // The pool is fed indices rather than detections because the index has to
    // ride along with the result: the pool returns completion order, and a
    // fallback is appended out of band.
    final fallbacks = <(int, ResolvedGame)>[];
    final failures = <(int, Object)>[];
    final resolved = await runPool<int, (int, ResolvedGame)>(
      [for (var i = 0; i < detections.length; i++) i],
      (index) async {
        final result = await resolverWorker.run(detections[index]);
        done += 1;
        progress?.onItem?.call('resolve', done, detections.length);
        return (index, result);
      },
      concurrency: resolverConcurrency,
      stop: stop,
      onError: (index, error) {
        // Failed resolutions degrade to unresolved entries handled at review.
        failures.add((index, error));
        fallbacks.add((index, ResolvedGame(detection: detections[index])));
      },
    );
    _warnResolveFailures(detections, failures, progress);
    final answered = {
      for (final (index, _) in resolved) index,
      for (final (index, _) in fallbacks) index,
    };
    final skipped = [
      for (var i = 0; i < detections.length; i++)
        if (!answered.contains(i)) i,
    ];
    if (skipped.isNotEmpty) {
      // One line, not one per detection: a stopped resolve of a real
      // hi-res control set would otherwise write one warning per row, all
      // saying the same thing.
      progress?.onWarning?.call(ScanWarning(
          'Stopped before IGDB: ${skipped.length} detection(s) are in the '
          'review unmatched.'));
      for (final index in skipped) {
        fallbacks.add((index, ResolvedGame(detection: detections[index])));
      }
    }
    resolved
      ..addAll(fallbacks)
      ..sort(_byPhotoThenInput);
    return [for (final (_, game) in resolved) game];
  }
}

/// One warning per distinct reason, not one per skipped entry (T-0155).
///
/// The same trade [_warnResolveFailures] records, and the shape the folder
/// source will actually hit: a games directory holds saves, patches,
/// screenshots and DLC archives, so a source pointed at one declines far more
/// entries than it accepts, and a line each would bury the run's real
/// warnings. The names are not repeated into the sentence because
/// [ReviewDocument.declinedEntries] carries every one of them as a value --
/// T-0145's lesson about a shell reading a fact out of a warning's text.
/// The group takes the MAXIMUM [Severity] of its members (T-0222), which is
/// what keeps one real failure from being quietened by fifty silences that
/// happen to share its reason string. Two sources spelling one reason
/// differently is what makes that rare rather than impossible -- `dlcNotAGame`
/// is a different sentence in each of the two GOG sources -- but the fold is
/// not written on that holding.
void _warnDeclined(List<DeclinedEntry> declined, ScanProgress? progress) {
  if (declined.isEmpty) return;
  final byReason = <String, List<String>>{};
  final severities = <String, Severity>{};
  for (final entry in declined) {
    byReason.putIfAbsent(entry.reason, () => []).add(entry.name);
    final seen = severities[entry.reason];
    if (seen == null || entry.severity.index > seen.index) {
      severities[entry.reason] = entry.severity;
    }
  }
  byReason.forEach((reason, names) {
    progress?.onWarning?.call(ScanWarning(
      names.length == 1
          ? 'Skipped ${names.single}: $reason'
          : 'Skipped ${names.length} entries, one reason for all of them; they '
              'are named in the review document rather than repeated here: '
              '$reason',
      severity: severities[reason]!,
    ));
  });
}

/// One warning per distinct cause, not one per failed row (T-0144).
///
/// A stage-wide failure arrives here as N row failures: a Twitch 403 on the
/// credentials produced **one warning per row, all carrying one explanation**
/// on a real document, which the CLI writes to stderr and the app appends to a
/// list the
/// user then scrolls. That is the shape [Orchestrator.runResolve]'s stop branch
/// already refuses, and this is the same trade said the same way.
///
/// **Two failures are the same when they read the same.** The key is `'$error'`
/// -- the text the user would have read twice -- because repetition is what is
/// being removed, and because that is already this file's answer to the same
/// question in [ScanFailedException.message]. The type is not the key: T-0107
/// gave both hosts one exception class and put the distinction in the sentence,
/// so `IgdbApiException` would fold a Twitch 403 into an IGDB 401. A run with
/// two causes therefore still reports both.
///
/// **Where the titles went.** A group names none: they are in the review
/// document as unmatched rows, which is exactly what the [ScanProgress] line
/// says and what the stop branch relies on. A lone failure keeps its title,
/// since one line naming the row it lost is what the odd 400 needs and is what
/// this stage has always written.
///
/// Emitted after the pool rather than as each row dies -- the count is not
/// known until then -- so the resolve stage's warnings now arrive together at
/// the end of the stage.
void _warnResolveFailures(
  List<Detection> detections,
  List<(int, Object)> failures,
  ScanProgress? progress,
) {
  if (failures.isEmpty) return;
  // Input order: the pool answers in completion order, and which cause is
  // reported first is not a race the user should see.
  failures.sort((a, b) => a.$1.compareTo(b.$1));
  final byCause = <String, List<int>>{};
  for (final (index, error) in failures) {
    byCause.putIfAbsent('$error', () => []).add(index);
  }
  byCause.forEach((cause, rows) {
    progress?.onWarning?.call(ScanWarning(rows.length == 1
        ? 'Resolver failed for "${detections[rows.single].rawTitle}": $cause'
        : 'Resolver failed for ${rows.length} detection(s), one cause for all '
            'of them; their titles are in the review as unmatched rows rather '
            'than repeated here: $cause'));
  });
}

/// Walks a scan's photos in the order the review document is grouped in: by
/// photo name, then by the photo's position in [Orchestrator.runScan]'s input.
///
/// This is what hands [dedupeDetections] its input order, and dedupe keeps
/// groups in first-seen order, so it is also what answers the question a
/// merged detection asks and a single-photo one does not: **the earliest photo
/// in this order that read the spine decides where the merged row sits.**
///
/// The alternative -- position it by the read that WINS the merge
/// ([_photoYield], T-0027) -- is not a second candidate but the same key
/// applied later, and it is already applied: [_byPhotoThenInput] groups the
/// games by the winning read's `photoContext`. So the winner's photo decides
/// which block a merged row lands in and this decides where inside that block,
/// which puts it against the edge of the winner's block that faces the other
/// photo. Deciding it twice would only mean deciding it once with a key that
/// is not known until every photo has answered.
///
/// The name leads and the index breaks its ties, exactly as in
/// [_orderedUnreadable] and for its reason: the file is grouped by name at
/// both ends, so the two stage-1 lists must walk the photos the same way, and
/// two [PhotoInput]s may carry one name. That is where T-0068's reasoning does
/// NOT carry -- it took the input index over the raw title because a title can
/// tie, but a title never enters here; what decides is the photo, and the
/// photo has a name the rest of the document already sorts on.
///
/// Every key is fixed before the first photo is uploaded. Measured 2026-08-15
/// on the five control photographs, at both resolutions, their detections
/// merging down to the recorded row count -- replayed through
/// two opposite completion orders: **more than a third of the rows sat in a
/// different position** before this, and none after. The rows themselves are
/// the same rows either way, field for field.
///
/// `CONTROL-HIRES` cannot show it and did not: no detection of one of its
/// photos merges with another's, so a scan of it merges nothing at all -- one
/// row per detection -- and every row is placed by the only photo that saw
/// it. Only
/// cross-photo merges move, which is also why the resolve stage (T-0068) and
/// the unreadable list (T-0073) could both be pinned without this surfacing.
List<(int, PhotoAnalysis)> _orderedAnalyses(
    List<PhotoInput> photos, List<(int, PhotoAnalysis)> perPhoto) {
  return [...perPhoto]..sort((a, b) {
      final nameA = photos[a.$1].name;
      final nameB = photos[b.$1].name;
      if (nameA != nameB) return nameA.compareTo(nameB);
      return a.$1.compareTo(b.$1);
    });
}

/// Orders the seen-but-unread spines of a whole scan: by photo, then by the
/// photo's position in [Orchestrator.runScan]'s input, then by the spine's
/// position in that photo's analysis.
///
/// Every part of the key is fixed before the first photo is uploaded, so the
/// same reads always write the same list however the pool's answers arrive --
/// the guarantee the old `sourcePhoto`-only key asserted and did not deliver
/// (T-0073). That key sorted the pool's COMPLETION order and kept it only by
/// accident of size: measured on Dart 3.13, `List.sort` leaves equal keys in
/// input order up to n=33 and no longer does at n=40, so a real 9-entry
/// hi-res document came out reproducibly ordered while a 12-photo scan of the
/// same 3-per-photo shape would not have.
///
/// The tie-break is a position because nothing on an [UnreadSpineReport]
/// discriminates: it carries a photo, a script and a free-text reason, and
/// [UnreadSpineReport.titleless] writes the same script and the same reason on
/// every row it makes. Measured on the hi-res control document -- 9 entries, 3
/// per photo, and the 3 within a photo byte-identical, so no key over their
/// fields could order them at all. That is where a spine differs from a
/// [Detection]: T-0068 chose an index over the raw title because a title *can*
/// tie, and here there is no content candidate to reject in the first place.
///
/// The photo name still groups, so this list runs through the photos in the
/// same order [_byPhotoThenInput] runs the games through. The index below it
/// covers the case the name cannot: two [PhotoInput]s may carry one name, and
/// then the name ties as well.
List<UnreadSpineReport> _orderedUnreadable(
    List<(int, PhotoAnalysis)> perPhoto) {
  final rows = <(int, int, UnreadSpineReport)>[
    for (final (photoIndex, analysis) in perPhoto)
      for (final (readIndex, spine) in analysis.unreadable.indexed)
        (photoIndex, readIndex, spine),
  ]..sort((a, b) {
      final photoA = a.$3.sourcePhoto;
      final photoB = b.$3.sourcePhoto;
      if (photoA != photoB) return photoA.compareTo(photoB);
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      return a.$2.compareTo(b.$2);
    });
  return [for (final (_, _, spine) in rows) spine];
}

/// Orders resolved rows by the photo they belong with, then by where they
/// came in.
///
/// [Detection.photoContext] rather than `source_photo`: a row typed at review
/// was read off no photo, so it sorted to the front of the file on an empty
/// key while the review screen filed it under the shelf it was typed from
/// (T-0066/T-0052). Photoless rows go LAST for the same agreement -- that is
/// where the screen's own grouping puts them, and it is the opposite of what
/// an empty string does under `compareTo`.
int _byPhotoThenInput((int, ResolvedGame) a, (int, ResolvedGame) b) {
  final photoA = a.$2.detection.photoContext;
  final photoB = b.$2.detection.photoContext;
  if (photoA != photoB) {
    if (photoA.isEmpty || photoB.isEmpty) return photoA.isEmpty ? 1 : -1;
    return photoA.compareTo(photoB);
  }
  return a.$1.compareTo(b.$1);
}

/// Stage 2: one physical game becomes one review row, however many photos
/// caught it.
///
/// Detections merge when their hints are equal (both-absent counting as
/// equal) and their [titleKey]s either match outright or stand in the
/// truncation relation [isTruncatedRead] admits at [ReadScope.acrossPhotos]
/// -- deliberately the stricter of the two scopes, for the reason recorded
/// there.
///
/// The truncation half also reaches across ONE kind of hint disagreement,
/// added by T-0146 once a model that reads the Switch 2 band arrived: a hint
/// that [_isRefinedBy] another, with the weaker hint on the cut read. An
/// outright [titleKey] match never does -- that is T-0018-02's two-console
/// case and it must keep making two rows.
///
/// T-0018-01 had the hint half the other way round -- absent was "compatible
/// with anything" -- and the control photographs killed it. One photograph
/// reads no hint on any of its detections, another reads one on every row, and
/// SOLAR PILGRIM VII REMAKE INTERBLOOM is read on both: the old rule merged
/// those two rows and dropped the hintless copy, which survived that run only
/// because the hinted read came back truncated. A hint can go
/// missing for reasons no upstream fix reaches (glare, angle, a platform the
/// model will not name), so the reverse failure is the one to accept: a spine
/// read with a hint on one photo and without on another now shows up twice,
/// and the human taps it away. Visible and cheap over invisible and
/// expensive -- also why two different present hints stay two rows.
///
/// Which read of a merged spine becomes the row is decided by [_photoYield],
/// not by `confidence` -- see [_DedupeGroup.absorb]. WHERE that row sits is a
/// separate question with a separate answer: first-seen order is preserved, so
/// a merged row holds the place of the earliest read of it in this list, and
/// [_orderedAnalyses] is what makes "earliest" name a photo rather than a race
/// (T-0085). The two can name different photos, though on a real five
/// they do not: every cross-photo merge of that set is both placed and typed
/// by a hi-res photo, which sorts first by name and also out-yields every
/// low-res one.
///
/// So the same detections in the same order give the same rows in the same
/// order, which is the whole of what this function can promise. Whether two
/// RUNS reach it with the same detections belongs to the vision call, and when
/// this line first claimed "two identical runs produce identical review files"
/// it was false there -- the local request stated no sampling options at all
/// (T-0053).
///
/// With those pinned it holds end to end for the local provider, measured
/// rather than argued: two consecutive five-photo CLI scans of a real
/// directory wrote byte-identical review files, row for row, `created`
/// aside -- both of them repeat asks for photos that server process had
/// already answered. A FIRST ask is the case to watch, and what decides which
/// of the model's two answers comes back is the prompt cache rather than a
/// freshly loaded model; an unload correlates only because it drops the cache
/// with the model (T-0086 -- run counts and cache figures on
/// [OllamaVisionProvider]). One such run produced the same rows in the same
/// order with the same hints, a handful of raw titles differing in case, ™/®
/// and one diacritic, all of which [titleKey] folds away.
///
/// What it does not fold is what a server allowed to batch can retype: at
/// `OLLAMA_NUM_PARALLEL=4` one title came back without its first half, and a
/// leading loss is refused as a truncation ([isTruncatedRead], T-0054), so it
/// arrives here as a second row. The cloud providers are untested here and
/// nobody has measured whether they are reproducible at all.
List<Detection> dedupeDetections(List<Detection> detections) {
  final yields = _photoYield(detections);
  final groups = <_DedupeGroup>[];
  for (final detection in detections) {
    final key = titleKey(detection.rawTitle);
    final hint = _hintKey(detection.platformHint);

    final compatible = <_DedupeGroup>[];
    final sides = <CutSide>[];
    for (final group in groups) {
      if (group.hint == hint) {
        compatible.add(group);
        sides.add(CutSide.either);
      } else if (_isRefinedBy(hint, group.hint)) {
        compatible.add(group);
        sides.add(CutSide.key);
      } else if (_isRefinedBy(group.hint, hint)) {
        compatible.add(group);
        sides.add(CutSide.candidate);
      }
    }

    _DedupeGroup? target;
    for (var i = 0; i < compatible.length; i++) {
      if (sides[i] != CutSide.either) continue;
      if (compatible[i].titleKey != key) continue;
      target = compatible[i];
      break;
    }
    if (target == null) {
      final match = uniqueTruncationMatch(
        key,
        [for (final group in compatible) group.titleKey],
        scope: ReadScope.acrossPhotos,
        cutSides: sides,
      );
      if (match != null) target = compatible[match];
    }

    final quality = yields[detection.sourcePhoto] ?? 0;
    if (target == null) {
      groups.add(_DedupeGroup(key, detection, quality));
    } else {
      target.absorb(key, detection, quality);
    }
  }
  return [for (final group in groups) group.best];
}

/// How many items each photo yielded, as this run's proxy for how legible
/// that photo was (T-0027).
///
/// The signal has to come from somewhere other than `confidence`, which the
/// local model pins at 1.0 for everything (doc/measurements.md), leaving the
/// first read of a spine to win by accident of filename order. Measured on the
/// five control photographs, at 1200x900 and at
/// 4000x3000 -- every hi-res photo out-yields every low-res one, and the
/// narrowest margin between them is a handful of spines. So this ranks reads
/// of a spine already agreed to be the same spine and nothing else; it is not
/// fit to decide whether two reads match.
///
/// This comment carried a wrong low-res split until T-0060. Two replays of the
/// pair against qwen2.5vl:7b on 2026-08-15 reproduced the recorded one both
/// times, agreeing with the three replays that opened T-0060, where the figure
/// written here did not. A re-scan of the three hi-res photos in the same
/// session reproduced their recorded split too, so that half was never wrong.
/// The splits themselves are in the control record (doc/control-set.md), not
/// here: they are a count of a private shelf (T-0246).
///
/// Two other signals were measured on the same photos and rejected.
/// Legibility rate (read / read + unread) cannot be computed: since T-0028
/// every photo reports an empty `unreadable` list, and before T-0028 it
/// reported a constant 3 whatever the photo showed -- neither state
/// distinguishes a sharp photo from a blurred one. Platform-hint presence is
/// dead by construction: the hint gate above groups a detection only with
/// hints that agree with its own or refine it, so presence never differs
/// within a group.
///
/// Derived from the detections rather than passed in, so no caller can hand
/// stage 2 a quality table that disagrees with the reads it is ranking.
///
/// A row that came off no photograph is counted under no photo at all
/// (T-0155). Letting them share the empty key would rank a GoG install against
/// a 4000x3000 shelf photo by how many OTHER installs the run happened to
/// carry -- 200 of them would out-yield every photo ever measured here, and
/// the number means nothing about either row. Those rows rank by
/// [DetectionOrigin] instead ([_DedupeGroup.absorb]) and never by this.
Map<String, int> _photoYield(List<Detection> detections) {
  final counts = <String, int>{};
  for (final detection in detections) {
    if (detection.sourcePhoto.isEmpty) continue;
    counts[detection.sourcePhoto] = (counts[detection.sourcePhoto] ?? 0) + 1;
  }
  return counts;
}

/// Detections agreed to be one game, plus the best row seen for it so far.
class _DedupeGroup {
  _DedupeGroup(this.titleKey, this.best, this.bestYield);

  String titleKey;
  Detection best;

  /// Read off [best] rather than stored: since T-0146 a group can hold two
  /// hints of different specificity, and the one it gates on has to be the
  /// one on the row it will emit, not the one that happened to arrive first.
  String? get hint => _hintKey(best.platformHint);

  /// [_photoYield] of the photo [best] came off.
  int bestYield;

  /// Ranks [detection] against the row held, in four steps that get weaker
  /// as they go: completeness, then who vouches for the title, then photo
  /// quality, then confidence.
  ///
  /// The second step is T-0155's and it decides the case T-0160 asks about: a
  /// folder holding a GoG install and a loose installer of one game reaches
  /// here as an authoritative title and a guess ([DetectionOrigin]), and the
  /// installer wrote the name while the filename parser inferred it. Above
  /// photo quality, because a yield is a proxy for how legible a photograph
  /// was and neither of those rows was photographed; below completeness,
  /// which stays first for T-0024's reason -- a truncated title is no use to
  /// the review list or to IGDB whoever vouches for it.
  ///
  /// A cut-short read never becomes the row whatever else it has going for
  /// it -- the review list and the IGDB search both want the whole title --
  /// so completeness stays first, as T-0024 left it. What changed in T-0027
  /// is everything below that: two reads with the same key used to be settled
  /// by `confidence`, which is 1.0 for every local read, so the winner was
  /// whichever photo the caller happened to list first. On the five control
  /// photographs that decided rows (`FROST WAKE(tm)`, `CHRONOS 3
  /// REMADE(tm)`, `PATH OF EMBER: ENDLESS HARVEST(tm)` against the clean
  /// hi-res reads of the same spines) purely by filename order.
  /// Confidence stays as the last tiebreak because a cloud provider does
  /// report a real spread across reads of one photo, where yield cannot.
  ///
  /// Equal on all three keeps the row already held, so a re-run of the same
  /// photos writes the same file.
  void absorb(String key, Detection detection, int photoYield) {
    if (key.length != titleKey.length) {
      if (key.length > titleKey.length) {
        titleKey = key;
        best = detection;
        bestYield = photoYield;
      }
      return;
    }
    if (detection.origin.isAuthoritative != best.origin.isAuthoritative) {
      if (detection.origin.isAuthoritative) {
        best = detection;
        bestYield = photoYield;
      }
      return;
    }
    final better = photoYield > bestYield ||
        (photoYield == bestYield && detection.confidence > best.confidence);
    if (!better) return;
    best = detection;
    bestYield = photoYield;
  }
}

/// Comparable form of a platform hint, or null when there is no hint.
///
/// Nothing beyond case and space is folded: `PS4` and `PS5` differ by one
/// character and must keep differing. Text the model writes to MEAN absence
/// ("null", "unknown") is already a real null by here -- `Detection.fromJson`
/// (T-0014).
String? _hintKey(String? hint) {
  final trimmed = hint?.trim().toLowerCase();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// True when [refined] names the same platform family as [base] and says more
/// about it -- [base]'s words are all of [refined]'s first words, and
/// [refined] has at least one more.
///
/// The reason there is such a relation at all (T-0146, off T-0112): a model
/// that reads the printed band answers `SWITCH 2` where one that cannot see
/// it answers `SWITCH`, and the read that cannot see the band is the same
/// read that is often cut short. Two hints in that relation are one platform
/// described at two legibility levels; two hints NOT in it are two platforms,
/// which is T-0018-02's measured case and stays two rows.
///
/// WORDS, not characters, and that is the whole safety of it. `ps4` and `ps5`
/// differ by one character and must keep differing (see [_hintKey]); as words
/// neither is a prefix of the other, so the relation never touches them. It
/// also never fires on `nintendo` against `switch`, which is the other pair
/// one photo can answer two ways (T-0033) -- that one has no refinement to
/// find and stays two rows.
///
/// Deliberately not a `SWITCH`/`SWITCH 2` table: the next console renames the
/// table and nobody edits it. `xbox` -> `xbox series x` is the same shape and
/// costs nothing to admit.
///
/// A null hint refines nothing and is refined by nothing. T-0018-01 made
/// absence compatible with everything and the control photographs killed it; the
/// note on [dedupeDetections] has the numbers.
bool _isRefinedBy(String? base, String? refined) {
  if (base == null || refined == null) return false;
  final short = base.split(_hintWords);
  final long = refined.split(_hintWords);
  if (long.length <= short.length) return false;
  for (var i = 0; i < short.length; i++) {
    if (short[i] != long[i]) return false;
  }
  return true;
}

final _hintWords = RegExp(r'\s+');
