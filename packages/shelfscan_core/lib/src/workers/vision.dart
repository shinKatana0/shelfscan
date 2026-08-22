/// Vision worker: one shelf photo -> what was read + what was not.
///
/// Separate from both the provider and the orchestrator so that retry policy,
/// future pre-processing (downscaling, segmentation) and the second-reader
/// policy (T-0011, T-0032) have one home: providers stay single-model and know
/// nothing about each other, and the orchestrator stays free of provider
/// concerns.
library;

import '../providers/vision.dart';
import '../title_key.dart';
import 'base.dart';

class VisionWorker extends Worker<PhotoInput, PhotoAnalysis> {
  VisionWorker(this.provider, {this.secondReader});

  final VisionProvider provider;

  /// A second model that reads EVERY photo after [provider], results merged.
  ///
  /// Null by default: no extra call, no extra cost, no cloud traffic unless a
  /// caller asked for it (the CLI behind `--fallback`). This class constructs
  /// no provider of its own, so it cannot read a photo anywhere the caller did
  /// not name.
  ///
  /// Unconditional since T-0032, and the condition it replaces was not a close
  /// call. Until then a photo was re-read only when the primary's `unreadable`
  /// list was non-empty -- the model's own report of what it had skipped. On
  /// the local path that report does not exist: across seven T-0028 prompt
  /// variants `qwen2.5vl:7b` never once named a spine it had actually skipped
  /// (against a hand count taken off each photograph its answers were either
  /// empty or named spines it had already read and listed), so the trigger
  /// fired on no photo of any
  /// run. Before T-0028 it fired on every photo of every run, on the schema
  /// example the model was copying. Neither state was a signal, and there is
  /// no other one: T-0028 also measured asking the model to count the spines
  /// it can see and subtract the ones it listed, which came back 0/0/0 as
  /// well. So the primary cannot say which photos are worth a second call, and
  /// the only honest per-photo answers left are all of them or none of them.
  /// Which one a run gets is now the user's choice, made per run, and it costs
  /// exactly one extra call per photo.
  ///
  /// What that choice bought with the one second reader available here, so it
  /// is not sold as free quality: qwen2.5vl:7b primary + gemma3:12b second on
  /// the three 4000x3000 control photos added 15 rows, and took the wall
  /// clock from 70 s to 146 s. Every added row was checked against
  /// the photographs. None was an item the primary had missed. Most were
  /// second readings of spines the primary had already read correctly, kept
  /// apart by one character
  /// (`HARBOUR STARBURT`, `NOCTURNE(R) GOLD`, `IRON HERALD` for
  /// `IRON HERALD SUNFALL`); the rest were wrong, including titles welded
  /// out
  /// of characters from two different spines and one invented Japanese title
  /// on a photo whose JP spines gemma3 had itself just reported as
  /// unreadable -- the T-0001 failure mode that T-0007's prompt closed for the
  /// primary and that no wording here reaches, since the second model gets the
  /// same prompt and does not obey it. A second local reader does not reach
  /// what the feature was built for: a JP-script spine carrying the Switch 2
  /// band.
  ///
  /// **A cloud PRIMARY can report its own misses, and it is still not a
  /// trigger** (T-0090, 2026-08-15, live `gpt-4.1-mini` through
  /// [OpenAiCompatibleVisionProvider], both control sets, 38 calls). Unlike the
  /// local 7B it names spines it really skipped: on the three photographs
  /// carrying JP-script spines it answered a `japanese` entry on 15 of 15 runs,
  /// four of them naming the position or the number correctly -- it answers
  /// in the form "the Nth and Mth spines from the top", and the eye check
  /// agrees. Three things stop that being a gate:
  ///   - it fires on 4 of the 5 control photos, so gating saves one call in
  ///     five against an unconditional re-read, and the photo it stays silent
  ///     on has unread spines of its own (hidden behind a bag, or logo-only);
  ///   - the count is a draw where the read is not. Ten runs of one photo:
  ///     `items` byte-identical every time, `unreadable` 1 entry on 8 and 2 on
  ///     the other 2; ten runs of another: one entry whose own text says
  ///     *three* spines on 3 runs and *two* on 7, against a hand count that
  ///     does not move between runs at all.
  ///     Sending `temperature: 0` and a `seed` does not fix it (T-0057's
  ///     "asked for, not shown").
  ///   - a self-reporting primary is a CLOUD primary, which inverts
  ///     decision 0011's local desktop default and uploads every photograph of
  ///     a private home to reach a signal worth one call in five.
  /// It is also not free quality on this shelf: fewer detections than
  /// the local model, every one of them a Japanese title the 7B transcribes,
  /// plus one invented title at 1200x900. The per-photo eye check is in
  /// doc/measurements.md, "A bigger local model, measured and rejected".
  ///
  /// A cloud SECOND reader remains unmeasured; nothing above is about it.
  final VisionProvider? secondReader;

  @override
  Future<PhotoAnalysis> process(PhotoInput task) async {
    // TODO: downscale large photos before upload (cost + latency).
    // Pre-segmentation into strips was built and measured here (T-0003) and
    // removed: on the two real photos it found no additional item net -- the
    // same distinct items either way -- while inventing two titles per run
    // that the whole-photo read got right, and it cost 3x the calls.
    final primary = await provider.analyze(task);

    final second = secondReader;
    if (second == null) return primary;

    final PhotoAnalysis reread;
    try {
      reread = await second.analyze(task);
    } on Object {
      // Rethrowing would drop the photo entirely -- runPool skips failures.
      return primary;
    }
    return mergeAnalyses(primary, reread);
  }
}

/// Combines a primary read with a second read of the SAME photo.
///
/// A re-read adds rows, it does not re-order them: the primary's items keep
/// their place, because churning the review list is what the second read must
/// not cost. Duplicates are matched on [titleKey] -- the two models often
/// disagree about `platform_hint`, and that must not turn one game into two
/// -- plus [isTruncatedRead] at [ReadScope.samePhoto], because a second model
/// can cut a spine the first one read whole, and the reverse. The second
/// read's `unreadable` list replaces the primary's outright: it is the later
/// and better-informed verdict on the same photo, and unioning the two would
/// count one spine twice whenever both models noticed it.
///
/// The one case where a primary row's TEXT changes: it was the cut-short read
/// of a pair. Dropping the second read's full title instead would leave the
/// resolver searching IGDB for `PATH OF EM`, which is worse than the churn this
/// otherwise avoids -- and the row does not move.
PhotoAnalysis mergeAnalyses(PhotoAnalysis primary, PhotoAnalysis reread) {
  final items = [...primary.items];
  final keys = [for (final item in items) titleKey(item.rawTitle)];

  for (final item in reread.items) {
    final key = titleKey(item.rawTitle);
    if (keys.contains(key)) continue;

    final match = uniqueTruncationMatch(key, keys, scope: ReadScope.samePhoto);
    if (match == null) {
      items.add(item);
      keys.add(key);
    } else if (key.length > keys[match].length) {
      items[match] = item;
      keys[match] = key;
    }
  }

  return PhotoAnalysis(items: items, unreadable: reread.unreadable);
}
