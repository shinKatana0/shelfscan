/// Review screen: approve/reject/fix each detected game, then export.
///
/// This is the human step of the pipeline made tappable -- the same
/// review.json semantics as the CLI, but interactive. Review is mandatory
/// UX (decision 0007): model confidence is not trustworthy, so a wrong match
/// must be correctable here, from the resolver's candidate list.
library;

import 'package:flutter/material.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import '../export_saver.dart';
import '../game_folders.dart' show folderName;

/// Statuses an exporter will actually emit -- mirrors `_exportable` in
/// `shelfscan_core/lib/src/exporters/exporters.dart`. What each target does
/// on top of that (`.xcoll` needs an IGDB id, csv does not) is asked of the
/// exporter itself via `canExport`, never re-derived here: the two rules
/// diverged in T-0012 and a second copy of them would rot.
const _exportableStatuses = {ReviewStatus.approved, ReviewStatus.edited};

/// Marking a row uses the exporter that would drop it, for the reason above:
/// the rule is `canExport`'s, and a copy of it here would rot.
final _xcoll = TonkatsuExporter();

/// What a row `.xcoll` cannot carry says, in the slot the absent `score N%`
/// leaves free.
///
/// 36 characters, measured against the 88 below: the widest subtitle in
/// CONTROL-HIRES is a 72-character raw title under a 6-character hint, and
/// with this clause it reads 127; the 90th percentile of the same control run
/// goes 59 -> 98. Only the unmatched rows pay it (a seventh of a real
/// run) and they are the ones that never carry a score or a canonical
/// platform name, so nothing that exports gets longer.
const _noXcollClause = 'not in .xcoll -- tap to pick a match';

/// What a row says instead of `score N%` when nothing scored it (T-0172).
///
/// It replaces the percentage rather than sitting beside it: an exact join
/// writes 1.0 into `score` because that was the only field, and on 18 of
/// T-0159's 394 live joins the store title is not IGDB's canonical name, so a
/// percentage on those rows is a string measurement nobody took. Text rather
/// than a badge, for the reason the mark buttons already carry one (T-0043):
/// the subtitle is what spells a row out, and colour or an icon alone says
/// nothing to a screen reader. 19 characters against the 10 of `score 100%`,
/// on a row class that did not exist when the 88 below was measured -- no
/// detection off a photograph carries a source id.
const _exactIdClause = 'matched by store id';

/// Names a dialog lists before it stops and counts the rest.
/// Ten still reads as a list and leaves the counted tail empty on an ordinary
/// run; a hundred is a wall of text, and by then the per-row clause is what
/// the list is read with.
const _namedDrops = 10;

/// Below this the photo goes above its rows instead of beside them.
///
/// Measured on a real run: the widest row subtitle is 88
/// characters and the 90th percentile is 61, which needs ~380 logical px of
/// bodySmall text; a [ListTile] spends another ~128 on its padding and the
/// two mark buttons. 528 for the rows plus a 280 px photo pane and the gap
/// lands just under Material 3's 840 dp "expanded" boundary, so that is the
/// line. The Windows window opens at 1280 and is on the wide side of it.
const double _wideLayout = 840;

/// Wide enough to judge a shelf at a glance; reading a spine is what the
/// tap-to-enlarge viewer is for.
const double _photoPane = 280;

/// The frame around a row `.xcoll` cannot carry (T-0223), and the scheme role
/// it is drawn in.
///
/// A border is a non-text element, so the bar is 3:1, and the roles were
/// measured on both surfaces before this one was picked: `tertiary` is 6.18:1
/// on the light surface (#f4fbf8) and 10.89:1 on the dark one (#0e1513).
/// `outlineVariant` -- the role a divider reaches for -- is 1.62:1 and 1.99:1
/// and fails outright; `outline` passes at 4.28:1 and 5.85:1 but is the app's
/// ordinary boundary colour and so marks nothing. `primary` and `error` pass
/// too and are spoken for: they are the approved and rejected marks on this
/// very row (T-0043).
///
/// No fill goes with it. `tertiaryContainer` is 1.23:1 and 1.97:1 against
/// those surfaces, so a tint cannot be the identifying element under the same
/// bar, and it would take the row's own text from 16.31:1 and 14.32:1 down to
/// 13.22:1 and 7.27:1 to buy that nothing.
///
/// 12 is Material 3's medium corner, the one a Card takes.
BoxDecoration _unmatchedFrame(ColorScheme scheme) => BoxDecoration(
      border: Border.all(color: scheme.tertiary),
      borderRadius: BorderRadius.circular(12),
    );

/// The two clauses that say which of two otherwise identical rows this is.
///
/// The year is four characters and IGDB has none for a small fraction of the
/// games one control run touches, so an absent one prints nothing at all rather
/// than a
/// placeholder -- the same treatment every other optional clause here gets,
/// and the only one that does not read as a claim. Worst case it takes the
/// 88-character subtitle measured for [_wideLayout] to 95.
List<String> _identity(Candidate candidate) => [
      if (candidate.releaseYear case final year?) '$year',
      if (candidate.matchedAlternativeName case final name?)
        // Why an English canonical title sits above a Japanese raw one: IGDB
        // knows the game under both.
        'matched as "$name"',
      candidate.matchMethod == MatchMethod.externalId
          ? _exactIdClause
          : 'score ${(candidate.score * 100).round()}%',
    ];

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.document,
    this.saver = const PlatformExportSaver(),
    this.resolver,
    this.keyless = false,
    this.failedPhotos = const [],
    this.notLookedAtPhotos = const [],
    this.photos = const [],
    this.folders = const [],
  });

  final ReviewDocument document;

  /// The scanned photos themselves, when this screen is opened in the same
  /// session that produced [document].
  ///
  /// A same-session affordance by design (T-0042): the document carries
  /// photo NAMES, never image data, so a `review.json` opened later arrives
  /// here with this list empty and groups by name alone. Resolving names
  /// back to disk paths is not an option -- Android does not hand out stable
  /// paths, which is why photos travel as bytes at all.
  final List<PhotoInput> photos;

  /// The folders of games this run read, by path, in the order they were
  /// added (T-0161).
  ///
  /// The same same-session affordance as [photos] and for a sharper reason:
  /// a source row carries the entry it was read from ([Detection.sourceEntry])
  /// and nothing carries the folder that was chosen, so a document opened
  /// without this list can say what it read but not where from.
  final List<String> folders;

  /// Photos the run lost outright, by name. Non-empty means the list below
  /// was built from fewer photos than the user chose, which has to stay
  /// visible for as long as they are reviewing it -- a document short by a
  /// third of the shelf looks exactly like a complete one.
  final List<String> failedPhotos;

  /// Photos the run never sent because the user pressed Stop, by name.
  ///
  /// A second list rather than a reason carried per name (T-0140): the two are
  /// rendered as two whole sentences, so anything finer would be partitioned
  /// again at the point of use, and this way the failure path keeps its type,
  /// its wording and its test untouched. Nothing derives one list from the
  /// other -- a name absent from both is a photo that was read.
  final List<String> notLookedAtPhotos;

  /// Platform save/share backend; tests inject a fake so no real dialog
  /// is ever opened.
  final ExportSaver saver;

  /// Resolves a manually added item against IGDB right after it is entered.
  ///
  /// Null, or a [SkipResolver] when the user has no IGDB credentials: the
  /// item is then added unmatched, which is still worth doing -- csv
  /// exports it from the typed title alone.
  final ResolverWorker? resolver;

  /// The run that produced [document] had no IGDB stage (T-0230) -- either
  /// the mode was chosen or there was nothing to authenticate with.
  ///
  /// It changes what this screen SAYS, never what it does: no row is
  /// exported differently, and nothing here re-derives `canExport`. What
  /// moves is where the "not in .xcoll" fact is stated -- see
  /// [_keylessBanner] for the argument, which is the design question T-0230
  /// was filed to settle.
  final bool keyless;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  /// True while a manual item is being resolved, so the add action cannot
  /// be fired twice into a slow IGDB round trip.
  bool _adding = false;

  List<ResolvedGame> get _marked => widget.document.games
      .where((g) => _exportableStatuses.contains(g.status))
      .toList();

  Future<void> _export(String target) async {
    final exporter = exporters[target]!();

    // Asked per target: an approved manual item with no match is dropped by
    // `.xcoll` and carried by csv, so the warning must not fire for csv.
    final marked = _marked;
    final dropped = marked.where((g) => !exporter.canExport(g)).toList();
    final count = marked.length - dropped.length;

    if (dropped.isNotEmpty && !await _confirmDrop(target, dropped)) return;

    if (count == 0) {
      _tell(marked.isEmpty
          ? 'Nothing to export: no item is approved yet.'
          : 'Nothing to export: no approved item has a resolved match.');
      return;
    }

    final content = exporter.export(widget.document);
    final outcome = await widget.saver.save(
      suggestedName: 'shelf.${exporter.extension}',
      extension: exporter.extension,
      content: content,
    );
    if (!mounted) return;

    final items = '$count item${count == 1 ? '' : 's'}';
    // Asked of the exporter, like `canExport` above, and only on the two
    // outcomes that left a file behind: there is nothing to say about a file
    // the user cancelled or the platform refused to write.
    final formulas = exporter.formulaCells(widget.document);
    switch (outcome.kind) {
      case SaveKind.savedToFile:
        _tellSaved('Saved $items to ${outcome.path}', formulas);
      case SaveKind.shared:
        _tellSaved('Shared $items as shelf.${exporter.extension}', formulas);
      case SaveKind.cancelled:
        _tell('Export cancelled.');
      case SaveKind.failed:
        _tell('Export failed: ${outcome.error}');
    }
  }

  /// The export's own confirmation, plus the one thing about the file the
  /// user cannot learn by looking at it (T-0187).
  ///
  /// On the SnackBar the save already shows, after the fact, rather than in
  /// the blocking shape [_confirmDrop] uses before it: the file is correct
  /// and nothing was dropped, so this is a note about a *reader* of it. A
  /// dialog the user must dismiss to finish an export that already succeeded
  /// would be out of proportion, and a second SnackBar would push the first
  /// off the screen.
  ///
  /// Silent when there is nothing to report -- an ordinary export has no such
  /// cell in it, and a warning that fires always is one people learn to
  /// ignore (T-0161).
  void _tellSaved(String message, List<FormulaCell> formulas) {
    if (formulas.isEmpty) return _tell(message);
    final n = formulas.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      // Material's default 4 s is its figure for a message with nothing to
      // do about it; this one carries a button, and 4 s is not enough to read
      // the sentence and then decide to press it.
      duration: const Duration(seconds: 10),
      content: Text('$message. $n cell${n == 1 ? '' : 's'} '
          '${n == 1 ? 'begins' : 'begin'} with =, +, - or @, which a '
          'spreadsheet reads as a formula.'),
      action: SnackBarAction(
        key: const Key('export-formula-cells'),
        label: 'What to do',
        onPressed: () => _showFormulaCells(formulas),
      ),
    ));
  }

  /// Names the cells and gives the remedy, which is the same one README's
  /// "Opening the CSV in a spreadsheet" gives -- there is one remedy because
  /// nothing here rewrites a cell (T-0185).
  ///
  /// The list is the one computed for the file that was saved, not one
  /// recomputed on open: the SnackBar outlives the export and a row edited
  /// after it does not change the file on disk.
  Future<void> _showFormulaCells(List<FormulaCell> formulas) async {
    final rest = formulas.length - _namedDrops;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A spreadsheet reads these cells as formulas'),
        content: SingleChildScrollView(
          child: Text(
            'Excel, LibreOffice and Google Sheets evaluate any cell whose '
            'text begins with =, +, - or @. These names are yours and were '
            'exported exactly as they are:\n\n'
            '${formulas.take(_namedDrops).map((c) => '${c.column}: ${c.value}').join('\n')}'
            '${rest > 0 ? '\n...and $rest more' : ''}'
            '\n\nAn import dialog is not affected by this. To look at the '
            'file in a spreadsheet, import it with the columns set to Text '
            '(Excel: Data > From Text/CSV) rather than double-clicking it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Target picker behind the primary Export button -- the only route to
  /// [_export] since T-0118.
  ///
  /// A target that would carry none of the marked rows says so here, before
  /// the tap, rather than answering a confirmation dialog and then "nothing
  /// to export" (T-0230). That is every target on a keyless run except csv,
  /// and it is how the export a keyless run CAN use is the one offered.
  ///
  /// Asked of each exporter through `canExport`, never decided here: the same
  /// rule [_export] filters by, so the sheet cannot promise a row the file
  /// then drops. Not disabled either -- a target that explains itself beats
  /// one that goes dead.
  Future<void> _chooseExportTarget() async {
    final marked = _marked;
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in exporters.entries)
              Builder(builder: (context) {
                final exporter = entry.value();
                final carries = marked.where(exporter.canExport).length;
                return ListTile(
                  key: Key('export-sheet-${entry.key}'),
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text('Export: ${entry.key}'),
                  subtitle: Text(carries == 0 && marked.isNotEmpty
                      ? '.${exporter.extension} file -- carries none of the '
                          'marked rows'
                      : '.${exporter.extension} file'),
                  onTap: () => Navigator.of(context).pop(entry.key),
                );
              }),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await _export(target);
  }

  /// Names the rows rather than only counting them: a count cannot be traced
  /// back to a row, which is what the owner could not do with it (T-0123).
  Future<bool> _confirmDrop(String target, List<ResolvedGame> dropped) async {
    final n = dropped.length;
    final named = dropped.take(_namedDrops).map(_dropName);
    final rest = n - _namedDrops;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unresolved items will be dropped'),
        content: SingleChildScrollView(
          child: Text(
            '$n approved item${n == 1 ? '' : 's'} '
            '${n == 1 ? 'has' : 'have'} no matched game, and the '
            '$target export can only carry matched ones. '
            '${n == 1 ? 'It' : 'They'} will be left out:\n\n'
            '${named.join('\n')}'
            '${rest > 0 ? '\n...and $rest more' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back to review'),
          ),
          FilledButton(
            key: const Key('export-drop-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export anyway'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// A row with neither a match nor a raw title reaches no exporter at all and
  /// can only come from a hand-edited document; it is still named, because a
  /// list one item short of the count is worse than an ugly line.
  static String _dropName(ResolvedGame game) {
    final title = game.best?.title ?? game.detection.rawTitle.trim();
    return title.isEmpty ? '(untitled row)' : title;
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Add an item the vision stage never produced.
  ///
  /// The two cases this exists for (doc/measurements.md, T-0001/T-0011): a
  /// logo-only spine with no text to read, and a spine the model reported as
  /// unreadable. Neither can be recovered by scanning harder -- on the
  /// control photographs no locally runnable model reads the Japanese spines
  /// at all -- so typing the title is the only path those items have.
  ///
  /// [fromPhoto] is the photo the user was looking at, which every caller
  /// but the FAB knows; the row then joins that photo's group instead of the
  /// one at the bottom (T-0052). Null from the FAB, which floats over the
  /// whole list and belongs to no shelf.
  Future<void> _addManualItem({String? fromPhoto}) async {
    final detection = await showDialog<Detection>(
      context: context,
      builder: (context) => _ManualItemDialog(fromPhoto: fromPhoto),
    );
    if (detection == null || !mounted) return;

    setState(() => _adding = true);
    final outcome = await _resolveManual(detection);
    if (!mounted) return;
    setState(() {
      _adding = false;
      widget.document.games.add(outcome.game);
    });
    _tell(outcome.message);
  }

  /// Resolve on creation when IGDB is configured; degrade to an unmatched
  /// entry otherwise.
  ///
  /// A resolver failure is deliberately NOT an error the user has to deal
  /// with: the item they just typed is the valuable part, and the pipeline
  /// already treats a failed resolution as "unresolved, handle at review"
  /// everywhere else (ARCHITECTURE.md: a failed task never kills the run).
  /// The message travels back with the game so exactly one of the three
  /// outcomes is reported, rather than a queue of snackbars.
  Future<({ResolvedGame game, String message})> _resolveManual(
      Detection detection) async {
    final title = detection.rawTitle;
    final unmatched = 'Added "$title" with no IGDB match -- it exports to '
        'csv, not to .xcoll.';

    final resolver = widget.resolver;
    final unresolved = ResolvedGame(detection: detection);
    if (resolver == null) return (game: unresolved, message: unmatched);

    try {
      final game = await resolver.run(detection);
      final best = game.best;
      return (
        game: game,
        message: best == null
            ? unmatched
            : 'Added "${best.title}" (${best.platformName}).',
      );
    } on Object catch (e) {
      return (
        game: unresolved,
        message: 'Added "$title", but the IGDB lookup failed: $e',
      );
    }
  }

  /// The prompt: T-0011 recorded what the model saw and could not read, so
  /// the screen can say that items are missing instead of leaving the user to
  /// notice on their own.
  ///
  /// "At least", because the list counts reports and one report can describe
  /// several spines: `gpt-4.1-mini` answers one entry naming two or three
  /// middle spines, 10 of 10 runs on `CONTROL-HIRES` `shelf-3`, against a
  /// hand count off the photograph the entry never matches (T-0109). The
  /// report count is the only bound
  /// available -- reading "two or three" out of the entry's prose would be
  /// the fabricated count T-0028 removed. Under-reporting is the expensive
  /// direction here: this prompt exists to make the owner type in what the
  /// scan missed, so a number they read as exact costs them the rest.
  ///
  /// One Add per photo, not one for the prompt: the counts were already per
  /// photo, and an item typed against "shelf2.jpg: 1" is an item that
  /// belongs in shelf2's group (T-0052).
  Widget? _unreadablePrompt() {
    final byPhoto = widget.document.unreadableByPhoto;
    if (byPhoto.isEmpty) return null;

    final total = widget.document.unreadable.length;
    final added = widget.document.games.where((g) => g.detection.isManual).length;
    const caveat =
        'One report can describe several spines, so there may be more.';

    return Material(
      key: const Key('unreadable-prompt'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility_off),
            isThreeLine: true,
            title: Text(
                'At least $total spine${total == 1 ? '' : 's'} could not be read'),
            subtitle: Text(added == 0
                ? '$caveat Nothing was invented for them. Add them by hand.'
                : '$caveat $added item${added == 1 ? '' : 's'} added by hand '
                    'so far.'),
          ),
          for (final entry in byPhoto.entries)
            ListTile(
              dense: true,
              // A report counted against no photo can only come from a
              // hand-edited document; it still gets a row, and its Add lands
              // in the same group the label names.
              title: Text(entry.key.isEmpty ? 'Not from a photo' : entry.key),
              subtitle: Text('${entry.value} unread-spine '
                  'report${entry.value == 1 ? '' : 's'}'),
              trailing: FilledButton(
                key: Key('unreadable-add-${entry.key}'),
                onPressed: _adding
                    ? null
                    : () => _addManualItem(fromPhoto: entry.key),
                child: const Text('Add'),
              ),
            ),
        ],
      ),
    );
  }

  /// Export is the last step of the product -- everything before it exists
  /// to produce that file -- so it gets a persistent primary control, and
  /// since T-0118 the only one. Disabled reads better than a dead end here:
  /// the label says what is missing before the tap rather than after it,
  /// which is the one thing the removed AppBar menu could not do.
  Widget _exportBar(int marked) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('export-primary'),
                onPressed: marked == 0 ? null : _chooseExportTarget,
                icon: const Icon(Icons.save_alt),
                label: Text(marked == 0
                    ? 'Export -- nothing approved yet'
                    : 'Export $marked item${marked == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the list below does not cover, one banner per reason.
  ///
  /// Two banners rather than one merged sentence, because a photo the pipeline
  /// lost and a photo the user stopped before are different events with
  /// different remedies, and one run can produce both (T-0140). Only the
  /// failure half is an error, and only it is coloured as one: being told your
  /// own Stop was an error is worse than being told nothing.
  List<Widget> _missingPhotoBanners() {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.document.photos.length;
    final photos = 'photo${total == 1 ? '' : 's'}';
    final failed = widget.failedPhotos;
    final stopped = widget.notLookedAtPhotos;
    return [
      if (failed.isNotEmpty)
        _runBanner(
          key: const Key('failed-photos-banner'),
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
          icon: Icons.broken_image,
          title: '${failed.length} of $total $photos could not be scanned',
          subtitle: '${failed.join(', ')} -- nothing from '
              '${failed.length == 1 ? 'it' : 'them'} is in this list.',
        ),
      if (stopped.isNotEmpty)
        _runBanner(
          key: const Key('stopped-photos-banner'),
          background: scheme.secondaryContainer,
          foreground: scheme.onSecondaryContainer,
          icon: Icons.pause_circle_outline,
          title: '${stopped.length} of $total $photos '
              '${stopped.length == 1 ? 'was' : 'were'} not looked at',
          subtitle: 'The scan was stopped before ${stopped.join(', ')} -- '
              'nothing from ${stopped.length == 1 ? 'it' : 'them'} is in this '
              'list.',
        ),
    ];
  }

  /// What a keyless run's whole list is, said once instead of on every row
  /// (T-0230).
  ///
  /// This is where the per-row frame and clause go in this mode, and the
  /// move is the point rather than a tidy-up. T-0223 put a frame on the rows
  /// `.xcoll` cannot carry because they were a minority and had no fixed
  /// place on a row to be found at; a universal mark is furniture, and a
  /// reader who has to be told the same thing on every line has been told
  /// nothing about any of them. What is true here is true of the run, so it
  /// is stated where the run's other facts already are -- beside the lost
  /// photos and the unread spines.
  ///
  /// `secondaryContainer` and not the error pair: a keyless run is a
  /// legitimate choice with a consequence, the same footing the settings
  /// screen gives a cloud backend (T-0045 item 22). It names the export that
  /// works, because a banner that only says what is impossible is the
  /// adoption cliff written down.
  ///
  /// Nothing here re-derives `canExport`. Which rows csv carries is the
  /// exporter's rule and stays there; this says which lookup did not happen.
  Widget _keylessBanner() => _runBanner(
        key: const Key('keyless-run-banner'),
        background: Theme.of(context).colorScheme.secondaryContainer,
        foreground: Theme.of(context).colorScheme.onSecondaryContainer,
        icon: Icons.link_off,
        title: 'Keyless run -- nothing was looked up',
        subtitle: 'Every row is the title as it was read, so there are no '
            'covers and no platform ids, and the .xcoll export has nothing '
            'to carry. Export CSV: it takes the rows as they are.',
      );

  Widget _runBanner({
    required Key key,
    required Color background,
    required Color foreground,
    required IconData icon,
    required String title,
    required String subtitle,
  }) =>
      Material(
        key: key,
        color: background,
        child: ListTile(
          iconColor: foreground,
          textColor: foreground,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
        ),
      );

  /// Tap on a row -> pick a different match, or declare there is none.
  Future<void> _pickCandidate(ResolvedGame game) async {
    final choice = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CandidateSheet(game: game),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice.noMatch) {
        // An unresolved item must not reach .xcoll -- rejecting it keeps
        // it out of both exports.
        game.best = null;
        game.status = ReviewStatus.rejected;
      } else {
        game.best = choice.candidate;
        game.status = ReviewStatus.edited;
      }
    });
  }

  /// The rows split by the photo they belong with -- read off it, or typed
  /// while looking at it ([Detection.photoContext]) -- in the order the
  /// photos were scanned.
  ///
  /// A photo that produced no rows still gets a group. "This shelf gave
  /// nothing" is precisely what the flat list could not say, and it is the
  /// half of review the owner said was missing -- seeing what was *not*
  /// picked up, not only checking what was.
  List<_PhotoGroup> _groups() {
    final available = {for (final photo in widget.photos) photo.name: photo};
    final groups = <String, _PhotoGroup>{};
    _PhotoGroup groupFor(String name) => groups.putIfAbsent(
        name, () => _PhotoGroup(name: name, photo: available[name]));

    for (final name in widget.document.photos) {
      groupFor(name);
    }
    // One group for every folder together, not one per folder and not one per
    // container: the rows a games directory produces have a container each --
    // fifty games, fifty headers of one row -- and nothing on a row names the
    // folder that was chosen anyway. What the header is FOR is the question a
    // photo's thumbnail answers, and the answer for a folder is the skipped
    // list rather than a picture (T-0161).
    final games = widget.document.games;
    final folder = widget.document.declinedEntries.isNotEmpty ||
            widget.folders.isNotEmpty ||
            games.any((game) => _fromFolder(game.detection))
        ? _PhotoGroup(name: _folderGroupName(), fromFolder: true)
        : null;
    for (var i = 0; i < games.length; i++) {
      final detection = games[i].detection;
      final group = folder != null && _fromFolder(detection)
          ? folder
          : groupFor(detection.photoContext);
      group.indices.add(i);
    }

    // Rows belonging to no photo -- a row typed with no shelf in view, and
    // any document row whose `source_photo` is empty -- go last rather than
    // first: the photo groups then keep the order the shelves were
    // photographed in, and an item added with no context always lands in the
    // same known place instead of shifting the whole list.
    final ordered = [
      for (final group in groups.values)
        if (group.name.isNotEmpty) group,
    ];
    // After the shelves and before the loose rows: the folder is an input of
    // the run like a photo is, and the loose group stays last so a manually
    // added item keeps landing in the same known place.
    if (folder != null) ordered.add(folder);
    final loose = groups[''];
    if (loose != null) ordered.add(loose);
    return ordered;
  }

  /// A row read out of a folder rather than off a photograph or typed here.
  ///
  /// On the two source origins, not on [Detection.sourceEntry]: `origin` is
  /// the field that names the KIND of thing a row came from, and the two
  /// values are what [Detection.fromSource] asserts.
  static bool _fromFolder(Detection detection) =>
      detection.origin == DetectionOrigin.metadata ||
      detection.origin == DetectionOrigin.filename;

  /// What the folder group is called.
  ///
  /// The chosen folder's own name when there is one -- not the container of
  /// each row, which for a games directory is a different name per game. Two
  /// folders are counted rather than listed in the title; [_folderGroupPaths]
  /// names every one of them under it.
  String _folderGroupName() => switch (widget.folders.length) {
        0 => 'From a folder',
        1 => folderName(widget.folders.single),
        final count => '$count folders',
      };

  /// Full resolution, and only for as long as the viewer is on screen.
  Future<void> _enlarge(PhotoInput photo) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _PhotoViewer(photo: photo)));

  /// A folder's header, which is a photo group's header with the picture
  /// replaced by what the picture is for.
  ///
  /// T-0042 put the shelf in the header so the human could see what was *not*
  /// picked up, not only check what was. A folder has no picture and needs
  /// none: what it was not read for is a list of names the pipeline already
  /// carries ([ReviewDocument.declinedEntries]), so the exact question the
  /// thumbnail answers is answered here in words.
  ///
  /// No "add an item from this" button, unlike a photo group: that writes the
  /// group's name into `addedFromPhoto`, which `models.dart` reserves for a
  /// photo file name -- the csv export publishes it as provenance to a reader
  /// with no `origin` column. The screen's own FAB adds an item with no
  /// context, which is what an item typed here is.
  Widget _folderHeader(_PhotoGroup group) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          key: const Key('folder-group'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text(group.name, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            Text(_groupSubtitle(group), style: theme.textTheme.bodySmall),
            for (final path in widget.folders)
              Text(path, style: theme.textTheme.bodySmall),
            ..._declinedEntries(),
          ],
        ),
      ),
    );
  }

  /// What the folder held and no row came of, by reason, names behind a tap.
  ///
  /// Neither silence nor one line per entry: a games folder declines more than
  /// it accepts and a game's own directory the other way round -- the measured
  /// rates are in T-0158's report, because a rate over a real folder times its
  /// size is a count of that folder's contents -- so the folded form is one
  /// line per distinct reason, a closed set of four in `FilenameSource`, and
  /// the names sit under the disclosure. Counted lines lose the one thing the
  /// user needs when a game is missing, which is whether *their* game is in
  /// the skipped list.
  ///
  /// Grouped by the reason string, which is what the orchestrator's own
  /// warnings group by, and read off the document's values rather than parsed
  /// back out of those warnings (T-0145).
  List<Widget> _declinedEntries() {
    final declined = widget.document.declinedEntries;
    if (declined.isEmpty) return const [];
    final byReason = <String, List<String>>{};
    for (final entry in declined) {
      byReason.putIfAbsent(entry.reason, () => []).add(entry.name);
    }
    final theme = Theme.of(context);
    return [
      Theme(
        // The tile is inside a header, not a list of its own: the dividers
        // Material draws around an expansion would read as a second group.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('declined-entries'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            '${declined.length} file${declined.length == 1 ? '' : 's'} '
            'skipped, no game in ${declined.length == 1 ? 'it' : 'them'}',
            style: theme.textTheme.bodySmall,
          ),
          children: [
            for (final reason in byReason.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${byReason[reason]!.length} $reason',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(byReason[reason]!.join(', '),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _groupHeader(_PhotoGroup group, {required bool wide}) {
    if (group.fromFolder) return _folderHeader(group);
    final theme = Theme.of(context);
    final photo = group.photo;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.name.isEmpty ? 'Not from a photo' : group.name,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (photo != null) const Icon(Icons.zoom_in, size: 18),
            // The whole point of T-0052: the shelf being read is the one
            // thing on screen that knows where a typed item belongs. Absent
            // on the "Not from a photo" group, which is where the FAB
            // already puts things.
            if (group.name.isNotEmpty)
              IconButton(
                key: Key('photo-group-add-${group.name}'),
                icon: const Icon(Icons.playlist_add),
                tooltip: 'Add an item from this photo',
                onPressed:
                    _adding ? null : () => _addManualItem(fromPhoto: group.name),
              ),
          ],
        ),
        Text(_groupSubtitle(group), style: theme.textTheme.bodySmall),
      ],
    );

    final content = photo == null
        ? label
        : wide
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  const SizedBox(height: 8),
                  _thumb(photo, 320),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _thumb(photo, 112),
                  const SizedBox(width: 12),
                  Expanded(child: label),
                ],
              );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        key: Key('photo-group-${group.name}'),
        // No image, no tap: a document loaded from disk carries names and
        // nothing behind them, and an affordance that opens an empty viewer
        // is the fabricated signal T-0028 removed.
        onTap: photo == null ? null : () => _enlarge(photo),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: content,
        ),
      ),
    );
  }

  String _groupSubtitle(_PhotoGroup group) {
    final count = group.indices.length;
    if (count == 0) {
      return group.fromFolder
          ? 'no game was read out of this folder'
          : 'nothing was read off this photo';
    }
    return '$count item${count == 1 ? '' : 's'}';
  }

  /// Decoded at pane size rather than at 4000x3000: a photo that size is
  /// 12 Mpx, ~50 MB in memory, and three of them would fill half of Flutter's
  /// 100 MB image cache with thumbnails. 720 physical px covers the 280 px
  /// wide pane at 2x device pixel ratio.
  Widget _thumb(PhotoInput photo, double height) => Image.memory(
        photo.bytes,
        cacheWidth: 720,
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        // The pipeline accepts formats Flutter cannot draw: a HEIC reaching
        // this screen on Windows decodes nowhere (T-0039), and without this
        // it is a framework error and an empty box. Saying so beats both.
        errorBuilder: (context, error, stack) => SizedBox(
          height: height,
          width: height * 0.75,
          child: const Center(
            child: Icon(Icons.hide_image_outlined,
                semanticLabel: 'this photo cannot be displayed'),
          ),
        ),
      );

  Widget _group(_PhotoGroup group, bool wide) {
    final rows = <Widget>[
      for (final index in group.indices) _row(index),
    ];
    final header = _groupHeader(group, wide: wide);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, ...rows],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _photoPane, child: header),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _row(int index) {
    final game = widget.document.games[index];
    final best = game.best;
    // One evaluation for the frame and the clause below, so the two can never
    // disagree about which rows they mean.
    //
    // False on every row of a keyless run, and that is the answer to T-0223's
    // predicate inverting (T-0230). The frame and the clause mark the rows
    // that need the user's hand, and both earn their place by being rare; a
    // run with no IGDB stage makes them true of everything, at which point
    // the frame locates nothing and "tap to pick a match" is not even
    // accurate -- there is no candidate list to pick from, because nothing
    // was looked up. The fact is a property of the run there, so the run says
    // it once, above the list, in [_keylessBanner].
    //
    // Keyed off the mode and NOT off the rows: a MATCHED run in which every
    // row happens to be unresolved is a run where something went wrong, and
    // there the frames are exactly right.
    final needsAMatch = !widget.keyless && !_xcoll.canExport(game);
    final tile = ListTile(
      key: Key('review-row-$index'),
      onTap: () => _pickCandidate(game),
      // A typed title is not OCR output; marking it keeps the human from
      // re-checking their own input against a photo.
      leading: game.detection.isManual ? const Icon(Icons.edit_note) : null,
      title: Text(best?.title ?? game.detection.rawTitle),
      subtitle: Text([
        best?.platformName ?? game.detection.platformHint ?? '?',
        if (game.detection.isManual)
          'added by hand'
        else
          'raw: "${game.detection.rawTitle}"',
        if (best != null) ..._identity(best),
        // The row's only positive statement of what it cannot do. Independent
        // of the review status on purpose: this is a property of the row's
        // data, true while it is still pending, and the decision the user has
        // taken is spelled out by the next clause anyway (T-0123).
        if (needsAMatch) _noXcollClause,
        if (game.status != ReviewStatus.pending) game.status.name,
        // Otherwise this row is indistinguishable from one whose branding was
        // illegible, and the value that caused it is only in the file
        // (T-0084).
        if (game.detection.discardedPlatformHint case final refused?)
          'hint refused: "$refused"',
        // Last on purpose. It is the only free-length clause here, so ahead of
        // the fixed ones it would move them row to row; behind them the row
        // still reads platform-raw-score-status in the same places (T-0041).
        // Measured empty on every row of both control sets, so no row of
        // either grows a line for it (T-0093).
        if (game.detection.notes case final note?) 'note: "$note"',
      ].join(' - ')),
      // Scheme roles rather than Colors.green/Colors.red: on the light
      // surface (#f4fbf8) those measured 2.65:1 and 3.51:1, and 2.65 is
      // under the 3:1 WCAG bar for a non-text control. primary/error are
      // >= 6.1:1 on both surfaces (T-0043). Colour is not the only signal
      // either way -- the subtitle spells the status out.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.check_circle,
                color: game.status == ReviewStatus.approved
                    ? Theme.of(context).colorScheme.primary
                    : null),
            onPressed: () =>
                setState(() => game.status = ReviewStatus.approved),
          ),
          IconButton(
            icon: Icon(Icons.cancel,
                color: game.status == ReviewStatus.rejected
                    ? Theme.of(context).colorScheme.error
                    : null),
            onPressed: () =>
                setState(() => game.status = ReviewStatus.rejected),
          ),
        ],
      ),
    );
    if (!needsAMatch) return tile;
    // A [DecoratedBox], not a Container: a Container adds the border's width
    // as padding, which would cost the row 2 logical px of height and take the
    // subtitle's measured 380 px budget to 378 -- see [_wideLayout]. This
    // paints on the tile's own bounds, so both stay exactly as measured.
    // Foreground, so the ink of a tap does not wash over it.
    return DecoratedBox(
      key: Key('unmatched-frame-$index'),
      position: DecorationPosition.foreground,
      decoration: _unmatchedFrame(Theme.of(context).colorScheme),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.document.games;
    // Edited items export too, so the counter tracks what would land in
    // the file rather than the literal `approved` status.
    final marked = _marked.length;
    final missing = _missingPhotoBanners();
    final prompt = _unreadablePrompt();
    final groups = _groups();

    return Scaffold(
      bottomNavigationBar: _exportBar(marked),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-manual-item'),
        onPressed: _adding ? null : _addManualItem,
        icon: _adding
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('Add missing item'),
      ),
      // No actions: export is the screen's one command and it lives in the
      // bottom bar (T-0118). The AppBar menu that used to duplicate it was
      // removed -- it reached the same two targets through the same
      // `_export`, but could not carry the bar's disabled state, so with
      // nothing approved it offered a tap that only produced a snackbar.
      appBar: AppBar(
        title: Text('Review ($marked/${games.length} to export)'),
      ),
      body: Column(
        children: [
          // After the photo banners and before the unread-spine prompt: the
          // two above are things that went wrong with this run, and this is
          // what the run is. Both of those keep the top of the screen.
          ...missing,
          if (widget.keyless) _keylessBanner(),
          if (prompt != null) prompt,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideLayout;
                return ListView.builder(
                  // Room for the FAB, so the last row stays reachable.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: groups.length,
                  itemBuilder: (context, index) =>
                      _group(groups[index], wide),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo and the rows filed under it.
///
/// [indices] are positions in `document.games`, not copies: the row widgets
/// keep their `review-row-N` identity and every mark still writes straight
/// into the one document the exporters read.
class _PhotoGroup {
  _PhotoGroup({required this.name, this.photo, this.fromFolder = false});

  /// Empty for the group of rows belonging to no photo.
  final String name;

  /// Null when the bytes are not in this session (a loaded `review.json`).
  final PhotoInput? photo;

  /// The one group of rows read out of a folder (T-0161), which has a header
  /// of its own: no thumbnail to show, and a skipped list to show instead.
  final bool fromFolder;

  final List<int> indices = [];
}

/// The photo at full resolution, pannable and zoomable.
///
/// The whole point of T-0042: a 280 px pane shows which shelf a group came
/// from, and this shows what is actually written on the spines.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photo});

  final PhotoInput photo;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final MemoryImage _image = MemoryImage(widget.photo.bytes);

  @override
  void dispose() {
    // A full-resolution photo decodes to ~50 MB, half of Flutter's default
    // 100 MB image cache. Dropped on the way out so the full-size decode
    // lives only while it is being looked at; the JPEG bytes stay, and they
    // are an order of magnitude smaller.
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.photo.name)),
      body: InteractiveViewer(
        key: const Key('photo-viewer'),
        // Fit-to-window puts the long edge of a full-resolution photo into
        // ~640 logical px of the 1280x720 Windows window, so 1:1 with the
        // sensor is ~6.4x and the default ceiling of 2.5x stops at 2.5 mm of
        // spine text -- unreadable, which is the whole complaint. 12x reaches
        // 1:1 on any viewport taller than 340 logical px, i.e. everything but
        // a phone held sideways.
        maxScale: 12,
        child: Center(
          child: Image(
            image: _image,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) =>
                Center(child: Text('$error')),
          ),
        ),
      ),
    );
  }
}

/// "Add missing item": title, platform hint, media type.
///
/// Deliberately the same three fields a vision detection carries, and no
/// more: this dialog produces a [Detection], not a catalog entry. Anything
/// richer (cover art, release year) belongs to the target app -- shelfscan
/// owns no catalog (README.md).
class _ManualItemDialog extends StatefulWidget {
  const _ManualItemDialog({this.fromPhoto});

  /// The photo the user was looking at, or null when they used the FAB.
  final String? fromPhoto;

  @override
  State<_ManualItemDialog> createState() => _ManualItemDialogState();
}

class _ManualItemDialogState extends State<_ManualItemDialog> {
  final _title = TextEditingController();
  final _platform = TextEditingController();
  MediaType _mediaType = MediaType.unknown;

  @override
  void initState() {
    super.initState();
    // Enables/disables the Add button as the title field fills up.
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _platform.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(Detection.manual(
      rawTitle: title,
      // The hint narrows the IGDB search; empty means "no hint", never the
      // string "" (see _optionalText in models.dart for why that matters).
      platformHint:
          _platform.text.trim().isEmpty ? null : _platform.text.trim(),
      mediaType: _mediaType,
      addedFromPhoto: widget.fromPhoto,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fromPhoto = widget.fromPhoto;
    return AlertDialog(
      title: const Text('Add missing item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Where it will land, before it lands there: the FAB and the
          // per-photo buttons open the same dialog and would otherwise be
          // indistinguishable once it is open.
          if (fromPhoto != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                key: const Key('manual-from-photo'),
                'From $fromPhoto',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          TextField(
            key: const Key('manual-title'),
            controller: _title,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Nocturne 5 Gold',
            ),
          ),
          TextField(
            key: const Key('manual-platform'),
            controller: _platform,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Platform (optional)',
              hintText: 'PS4',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<MediaType>(
            key: const Key('manual-media-type'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: MediaType.cartridge, label: Text('Cartridge')),
              ButtonSegment(value: MediaType.disc, label: Text('Disc')),
              ButtonSegment(value: MediaType.unknown, label: Text('Unknown')),
            ],
            selected: {_mediaType},
            onSelectionChanged: (s) => setState(() => _mediaType = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('manual-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('manual-add'),
          // A titleless item would export as a blank row, so there is
          // nothing to add until something is typed.
          onPressed: _title.text.trim().isEmpty ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Result of the picker sheet: either a candidate, or "there is no match".
class _Choice {
  const _Choice.candidate(this.candidate) : noMatch = false;
  const _Choice.noMatch()
      : candidate = null,
        noMatch = true;

  final Candidate? candidate;
  final bool noMatch;
}

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.game});

  final ResolvedGame game;

  @override
  Widget build(BuildContext context) {
    final best = game.best;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text('raw: "${game.detection.rawTitle}"'),
            subtitle: Text(game.candidates.isEmpty
                ? 'The resolver found no candidates'
                : 'Pick the right match'),
          ),
          const Divider(height: 1),
          for (final candidate in game.candidates)
            ListTile(
              key: Key('candidate-${candidate.igdbId}'),
              // The resolver's pick is marked, not privileged: the whole
              // point of this sheet is that it can be wrong.
              leading: Icon(_isBest(candidate, best)
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(candidate.title),
              subtitle: Text([
                candidate.platformName,
                ..._identity(candidate),
              ].join(' - ')),
              onTap: () =>
                  Navigator.of(context).pop(_Choice.candidate(candidate)),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('candidate-no-match'),
            leading: const Icon(Icons.block),
            title: const Text('No match'),
            subtitle: const Text('Clears the match and rejects the item'),
            onTap: () => Navigator.of(context).pop(const _Choice.noMatch()),
          ),
        ],
      ),
    );
  }

  static bool _isBest(Candidate candidate, Candidate? best) =>
      best != null &&
      best.igdbId == candidate.igdbId &&
      best.platformId == candidate.platformId;
}
