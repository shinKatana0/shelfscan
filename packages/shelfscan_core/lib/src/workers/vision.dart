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

  /// Optional second reader, off by default. When requested, it reads every
  /// photo and its results are merged with the primary's. The primary's own
  /// unreadable report is not a reliable gate for deciding which photos need
  /// another call: it may be empty when spines were missed or may describe
  /// spines already listed. The caller therefore makes an explicit choice
  /// about the extra cost and any cloud upload.
  final VisionProvider? secondReader;

  @override
  Future<PhotoAnalysis> process(PhotoInput task) async {
    // TODO: downscale large photos before upload (cost + latency).
    // Strip segmentation adds calls and can invent titles that a whole-photo
    // read handles correctly, so this path keeps the whole-photo read.
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
