/// Exporters.
///
/// Exporters consume ONLY approved/edited games from a reviewed document.
/// They are thin adapters over the canonical model -- no network calls, no
/// resolution logic, no filtering decisions beyond the review status.
/// They produce strings; writing to a file or a share sheet is the
/// caller's job (CLI or Flutter app).
library;

import 'dart:convert';

import '../models.dart';

const _exportable = {ReviewStatus.approved, ReviewStatus.edited};

/// A cell an export writes that a spreadsheet evaluates instead of showing,
/// named by the column it sits under so a reader can find it.
typedef FormulaCell = ({String column, String value});

abstract class Exporter {
  /// Registry key used in the UI/CLI: tonkatsu / csv.
  String get name;

  /// Suggested file extension, without the dot.
  String get extension;

  String render(List<ResolvedGame> games);

  /// Whether this target can carry [game] at all, review status aside.
  ///
  /// Used to be one shared `best != null` rule for every exporter. It is per
  /// target now because the two targets genuinely differ: `.xcoll` items ARE
  /// ids (external contract), while CSV is title text and can carry an item
  /// IGDB never matched -- which is the normal state of a manually added
  /// one (T-0012). The default stays the strict rule, so a new exporter
  /// opts into the loose one deliberately.
  ///
  /// The UI calls this to warn about what an export would drop, so it is
  /// part of the contract, not an implementation detail.
  bool canExport(ResolvedGame game) => game.best != null;

  /// Games this exporter would actually write out of a reviewed document.
  ///
  /// Exposed so callers can COUNT what survives without rendering; the
  /// exporter stays the single authority on the rule.
  List<ResolvedGame> select(ReviewDocument doc) => doc.games
      .where((g) => _exportable.contains(g.status) && canExport(g))
      .toList();

  /// Filter + render in one call.
  String export(ReviewDocument doc) => render(select(doc));

  /// Why this target left a marked row out, as the CLI's summary says it --
  /// the tail of `N left out: the <target> target ...`.
  ///
  /// A member for the same reason [canExport] is one: the shells narrate, the
  /// exporter owns the rule. It was one hardcoded sentence in `bin/` naming
  /// IGDB, which had already stopped being the whole truth for a TMDB-matched
  /// film row and would be exactly backwards for [TonkatsuCardsExporter],
  /// whose subject is the rows with no match at all.
  ///
  /// The default is the shipped wording byte for byte: `doc/guide.md` and its
  /// two translations quote that line, and `guide_transcript_test.dart` pins
  /// the guides against what the program prints.
  String get leftOutReason =>
      'carries only items with a resolved IGDB match.';

  /// Why this target carried none of the marked rows, as the app says it --
  /// the tail of `Nothing to export: ...`.
  ///
  /// [leftOutReason] one level further: that one explains a row this target
  /// declined beside rows it took, this one explains a selection that came
  /// back empty. Same contract as [canExport] and for the same reason, the
  /// shells narrate and the exporter owns the rule -- a copy of it on the
  /// screen is a copy that rots, and this is the third member added after the
  /// first one did.
  ///
  /// The default is the sentence the screen shipped with, and it is
  /// [TonkatsuExporter]'s answer: an item of that file is a pair of ids, so a
  /// row nothing resolved has none. It was every target's answer until here,
  /// and for [TonkatsuCardsExporter] it stated the exact inverse of the
  /// reason.
  String get carriedNothingReason => 'no approved item has a resolved match.';

  /// Whether the file this writes when [select] returns nothing is one the
  /// target's consumer can read.
  ///
  /// True for both targets that shipped, and the default for that reason: a
  /// `.xcoll` whose `items` array is empty is a well-formed collection and a
  /// CSV of its header row alone is a well-formed CSV. Each has been written
  /// on an empty selection since there were exporters, and each goes on being
  /// written byte for byte.
  ///
  /// [TonkatsuCardsExporter] is the one target whose consumer refuses the
  /// empty form outright -- read at `release/0.44`, and it is the parser's
  /// first act rather than a per-row issue. A shell reads this to decide
  /// whether to write the file at all: a file the importer rejects with a
  /// message naming the wrong problem is worse than no file, and the run has
  /// already said how many rows it carried (T-0460).
  bool get emptyFileIsUsable => true;

  /// Cells of the file this would write that a spreadsheet reads as a
  /// formula rather than as text.
  ///
  /// Empty by default rather than abstract, because the answer for a target
  /// nobody opens in a spreadsheet is genuinely "none": `.xcoll` is JSON.
  /// Takes the document, not the selected list, so what it names is exactly
  /// what [export] writes.
  ///
  /// Same contract as [canExport] and for the same reason: the shells warn,
  /// the exporter owns the rule. Its callers are the CLI's export summary and
  /// the app's export flow -- README alone was the whole of the warning until
  /// T-0187, and decision 0011's own precedent is that a README is not the
  /// point of export.
  List<FormulaCell> formulaCells(ReviewDocument doc) => const [];
}

/// What a `.xcoll` item's `platform_id` is, per [WorkKind].
///
/// Read off Tonkatsu's own published collections rather than reasoned about
/// (T-0162): every item of its movie collection is exactly `media_type` +
/// `external_id`, while its game and `animation` collections all carry the
/// third key -- and in the `animation` ones the value is not a platform at
/// all but `0` for a film and `1` for a series.
enum _PlatformId {
  /// The catalogue platform id the resolver matched.
  fromMatch(null),

  /// No key at all. A film has no platform, so writing one would invent it.
  absent(null),

  /// Tonkatsu's film-or-series discriminator, on a row where nobody has
  /// answered it.
  ///
  /// `0` would be a claim nobody made, and `0` is exactly the shape this file
  /// refuses elsewhere: a valid-looking id in a column other tools key on. So
  /// the row is declined by [TonkatsuExporter.canExport] and named to the user
  /// as dropped.
  ///
  /// **What narrowed, T-0368.** This was every animation row, because nothing
  /// upstream could tell the two apart. Now a fansub-shaped file name answers
  /// `series` on its own and a person answers either at review, so what is
  /// left here is the one honest gap: a row corrected to `Animation` and left
  /// there. The refusal is the same refusal and it is still true of that row;
  /// what changed is that it is no longer the only thing an animation row can
  /// be.
  undecidable(null),

  /// An animated film (T-0162).
  film(0),

  /// An animated series (T-0162).
  series(1);

  const _PlatformId(this.literal);

  /// The number this target's item carries where the answer is the kind's
  /// rather than the match's. Null for the three answers that are not a
  /// literal, which is what [TonkatsuExporter._item] branches on.
  final int? literal;
}

/// Tonkatsu Box exporter -- light .xcoll format.
///
/// Format reference: https://github.com/hacan359/tonkatsu-collections
/// The "light" variant carries IGDB ids only; Tonkatsu Box fetches
/// metadata and covers itself on import (Import -> Import Collection).
///
/// NOTE: format ownership belongs to the Tonkatsu Box project; treat it
/// as an external contract and pin the `version` field. If upstream bumps
/// the format, add a new writer rather than mutating this one.
class TonkatsuExporter extends Exporter {
  TonkatsuExporter({
    this.collectionName = 'Shelf scan',
    this.author = 'shelfscan',
  });

  final String collectionName;
  final String author;

  @override
  String get name => 'tonkatsu';

  @override
  String get extension => 'xcoll';

  // The default `best != null` still holds and is half the rule below: an
  // item of this format IS a pair of ids, so there is nothing to write for an
  // unmatched game. A manually added item that IGDB never resolved is
  // excluded here and exported through CSV instead.

  @override
  String render(List<ResolvedGame> games) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'format': 'light',
        'name': collectionName,
        'author': author,
        'created': DateTime.now().toUtc().toIso8601String(),
        'description': _describe(games),
        'items': [for (final g in games) _item(g)],
      });

  /// One item of the pinned format. Only ever called for a row
  /// [canExport] has already accepted, which is what makes both `!` safe.
  static Map<String, Object?> _item(ResolvedGame g) {
    final platformId = _platformId(g.detection.workKind);
    // Present, absent, or a number that belongs to the KIND rather than to
    // the match -- [_PlatformId] holds all of it and where each was read
    // from. A null platform on a matched game reaches here only from a
    // hand-edited document, and the key is then omitted rather than written
    // null, which this pinned contract has no reading for.
    final value = platformId == _PlatformId.fromMatch
        ? g.best!.platformId
        : platformId.literal;
    return {
      // EXTERNAL CONTRACT, and the key collides with this project's own
      // vocabulary: `media_type` here is Tonkatsu's field for the KIND of
      // work, not the carrier the CSV column of that name carries. [WorkKind]
      // is the kind; the two are separate types because they were one word
      // (decision 0015).
      'media_type': g.detection.workKind.wire,
      // A bare integer with the catalogue implied by `media_type`, which is
      // this target's contract and not this project's: [Candidate.externalId]
      // states the catalogue, so the namespace is split off here and checked
      // rather than cast ([_externalId]).
      'external_id': _externalId(g)!,
      if (value != null) 'platform_id': value,
    };
  }

  /// Two refusals on top of the default rule, and they refuse different
  /// things.
  ///
  /// An UNANSWERED animation row is refused by [_PlatformId.undecidable]: this
  /// target's item for that kind states film-or-series in a field nobody has
  /// filled. That row can be identified perfectly well -- what it lacks is not
  /// an id, and reading it as one sends the next person looking for a
  /// catalogue client that already exists. An answered one exports like any
  /// other row (T-0368).
  ///
  /// A row whose id this target cannot fill is refused by [_externalId]. Two
  /// routes reach that: a match from a catalogue the kind does not imply, and
  /// -- since T-0456 -- [WorkKind.anime], for which this project holds no
  /// catalogue at all.
  ///
  /// Either way the shells name what an export drops, so the row is visibly
  /// excluded rather than silently mis-filed.
  @override
  bool canExport(ResolvedGame game) =>
      super.canExport(game) &&
      _platformId(game.detection.workKind) != _PlatformId.undecidable &&
      _externalId(game) != null;

  /// The bare integer this target's `external_id` takes for [game], or null
  /// when the row cannot fill it honestly.
  ///
  /// Two ways it cannot, stated as one clause because they are one question.
  /// The namespace may name a catalogue other than the one this kind's
  /// `media_type` implies -- which is exactly the defect T-0290 fixed by hand,
  /// a games-catalogue id written one field over under a film kind, made
  /// mechanical here. And the id may not be an integer, which is what this
  /// field is by external contract however the answering catalogue keys it.
  static int? _externalId(ResolvedGame game) {
    final best = game.best;
    final catalogue = _catalogue(game.detection.workKind);
    if (best == null || catalogue == null) return null;
    // The FIRST colon, the split [Detection.sourceId] documents: the rest is
    // the catalogue's id verbatim.
    final colon = best.externalId.indexOf(':');
    if (colon <= 0 || best.externalId.substring(0, colon) != catalogue) {
      return null;
    }
    return int.tryParse(best.externalId.substring(colon + 1));
  }

  /// The catalogue this target's `media_type` implies for [kind] (T-0162).
  ///
  /// **All three animation kinds answer TMDB, including the one this target
  /// declines.** They said `null` while no animation row could be exported at
  /// all, under the comment *null for a kind this target declines anyway* --
  /// which stopped being true the moment a row could be answered (T-0368).
  /// Leaving it would have refused an answered animation row for a second
  /// reason dressed as the first: the row would look like one whose catalogue
  /// nobody has chosen, when Tonkatsu files `animation` under a TMDB id and
  /// T-0162 measured it. [_PlatformId.undecidable] is what refuses the
  /// unanswered row, and it is the only thing that should.
  ///
  /// **[WorkKind.anime] answers null, and that is the opposite case (T-0456).**
  /// Upstream's `anime` takes an AniList or a Kitsu id (`RCOLL_FORMAT.md`,
  /// "Source Values", `release/0.44`) and no catalogue this project wires
  /// answers either. So there is no id here that could honestly fill the
  /// field, [_externalId] returns null, and [canExport] declines the row --
  /// the same visible decline a film row gets in a run with no TMDB token.
  /// Widening this to `tmdbCatalogue` would file a cartoon's id under the
  /// anime type, which is a different work rather than a loose match.
  static String? _catalogue(WorkKind kind) => switch (kind) {
        WorkKind.game => igdbCatalogue,
        WorkKind.movie => tmdbCatalogue,
        WorkKind.animation ||
        WorkKind.animationFilm ||
        WorkKind.animationSeries =>
          tmdbCatalogue,
        WorkKind.anime => null,
      };

  /// What Tonkatsu's item for this kind puts in `platform_id`.
  ///
  /// A switch with no default, so a further [WorkKind] cannot reach the writer
  /// without someone answering this for it -- the export string is the half of
  /// a new kind that is easiest to add and forget, because a wrong one still
  /// produces a well-formed file. T-0456 added the fifth and this is where the
  /// compiler asked.
  ///
  /// [WorkKind.anime] is [_PlatformId.absent] and not [_PlatformId.film]:
  /// upstream's anime item carries no `platform_id` at all, so a `0` there
  /// would be the exact lie [_PlatformId.undecidable] refuses one kind over.
  /// The row is declined anyway, by [_catalogue] having no id for it, but the
  /// two refusals are about different fields and each states its own.
  static _PlatformId _platformId(WorkKind kind) => switch (kind) {
        WorkKind.game => _PlatformId.fromMatch,
        WorkKind.movie => _PlatformId.absent,
        WorkKind.animation => _PlatformId.undecidable,
        WorkKind.animationFilm => _PlatformId.film,
        WorkKind.animationSeries => _PlatformId.series,
        WorkKind.anime => _PlatformId.absent,
      };

  /// What the exported items were actually read from.
  ///
  /// The field is free text inside a pinned external contract, so the writer
  /// may say something truer without touching the format. It said
  /// `Generated by shelfscan from shelf photos` unconditionally until T-0155,
  /// which is a claim about the run and became false the moment a run could
  /// begin from a folder of installs.
  ///
  /// Derived from the rows rather than taken as a constructor argument
  /// because both shells build this exporter from the registry with no
  /// arguments (`exporters['tonkatsu']!()`), so an argument would be a claim
  /// nobody sets and the file would go on lying. An export of photographed
  /// rows still writes the exact string it wrote before.
  static String _describe(List<ResolvedGame> games) {
    final from = [
      for (final origin in DetectionOrigin.values)
        if (games.any((g) => g.detection.origin == origin)) _provenance[origin]!
    ];
    if (from.isEmpty) return 'Generated by shelfscan';
    final last = from.removeLast();
    return from.isEmpty
        ? 'Generated by shelfscan from $last'
        : 'Generated by shelfscan from ${from.join(', ')} and $last';
  }

  static const _provenance = {
    DetectionOrigin.vision: 'shelf photos',
    DetectionOrigin.manual: 'items typed at review',
    DetectionOrigin.metadata: 'installed game metadata',
    DetectionOrigin.filename: 'game file names',
  };
}

/// Generic CSV exporter.
///
/// Lowest common denominator: most collection managers (CLZ and friends)
/// accept a title/platform CSV in some import dialog. Column names are
/// deliberately plain; per-app column mapping can be added later as
/// dedicated exporters.
class CsvExporter extends Exporter {
  @override
  String get name => 'csv';

  @override
  String get extension => 'csv';

  /// CSV carries text, not ids, so an unmatched item is still worth writing
  /// -- the title and platform hint are exactly what a human would type into
  /// the target app by hand. This is the whole point of manual add (T-0012):
  /// the items IGDB cannot resolve are precisely the ones the model could
  /// not read either, and dropping them here would mean adding them was
  /// pointless.
  ///
  /// A blank title is still refused: it would export as an empty row.
  @override
  bool canExport(ResolvedGame game) =>
      game.best != null || game.detection.rawTitle.trim().isNotEmpty;

  /// Names the rule above rather than a match, because a match is not what
  /// this target needs: it takes text, and refuses a row only where there is
  /// no text to write and nothing matched to name it either.
  @override
  String get carriedNothingReason =>
      'no approved item has a title or a match for csv to write.';

  /// The columns every export has carried since T-0012.
  ///
  /// `source_photo` keeps T-0052's meaning exactly -- the photo a title was
  /// READ off, empty when it was read off none -- and is not widened to mean
  /// "where this came from". That field is arithmetic in `dedupeDetections`
  /// as well as text here, and renaming it breaks a consumer that adding
  /// beside it does not.
  ///
  /// `external_id` was `igdb_id` until decision 0016. A column named for one
  /// catalogue that carries another's ids is the same defect as the field it
  /// came from, one level out, and the cost is affordable only because no
  /// catalogue app has ever imported this CSV. The day one does, the column is
  /// frozen and that is a different decision.
  static const _columns = 'title,platform,media_type,external_id,source_photo';

  /// Appended only to an export that has provenance to publish (below).
  ///
  /// Three columns rather than one combined `source`, because they answer
  /// three questions a reader asks separately: which folder, how far to trust
  /// the title, and what the store calls the game. Combining the first with
  /// `source_photo` would recreate exactly the ambiguity T-0052 rejected -- a
  /// reader cannot tell "read off this" from "named by this" without the
  /// `origin` cell beside it, which is why `origin` sits between them.
  ///
  /// `source_id` earns the third column on a different axis from the other
  /// two: it is the only cell on the row that is an exact key rather than a
  /// description, so it survives a human editing the title and is the one
  /// field a script can join on (`gog:1100000014`, T-0157/T-0159).
  static const _provenanceColumns = 'source_entry,origin,source_id';

  /// Present only when some row was read off something that is not a
  /// photograph, so a photo-only export writes the bytes it wrote before
  /// T-0166 -- the treatment `source_entry` already gets in the review
  /// document (T-0155). The cost, accepted: two runs of the same tool can
  /// hand a script different column counts, so it must map by header. The
  /// header is what the documented consumer (an import dialog) maps by, and
  /// appending leaves columns 0-4 where a positional reader expects them.
  static bool _hasProvenance(List<ResolvedGame> games) => games.any((g) =>
      g.detection.sourceEntry != null || g.detection.sourceId != null);

  /// One row's cells in column order, under the headers they are written
  /// beneath, with the three that bypass [_cell] marked.
  ///
  /// Shared by [render] and [formulaCells] so the warning names cells this
  /// file actually holds rather than a second derivation of them -- the copy
  /// would rot exactly where the column set already moved once (T-0166).
  static List<({String column, String value, bool quote})> _row(
      ResolvedGame g, bool provenance) {
    final best = g.best;
    final d = g.detection;
    return [
      (column: 'title', value: best?.title ?? d.rawTitle.trim(), quote: true),
      // The hint is a guess ("PS4") where a match is canonical ("PlayStation
      // 4"). Writing the guess beats writing nothing: importers match
      // platform names loosely, and the human can fix one cell.
      //
      // The hint is reached ONLY when nothing matched: a match that names no
      // platform writes none. This was one `??` chain until decision 0016, and
      // it was right by accident -- a film's platform name was `''`, which is
      // not null and blocked the fallback. Nullable, the chain would continue,
      // and a row corrected from game to film keeps the console hint its spine
      // gave it (`correctWorkKind` clears the match, not the detection).
      (
        column: 'platform',
        value: (best == null ? d.platformHint : best.platformName) ?? '',
        quote: true
      ),
      (column: 'media_type', value: d.mediaType.name, quote: false),
      // Empty rather than a bare 0: 0 is a valid-looking catalogue id and
      // would be a lie in a column other tools may key on. Quoted like any
      // other text cell now that it is one -- the values this project writes
      // need no quoting and come out unchanged.
      (
        column: 'external_id',
        value: best?.externalId ?? '',
        quote: true
      ),
      (column: 'source_photo', value: d.sourcePhoto, quote: true),
      if (provenance) ...[
        (column: 'source_entry', value: d.sourceEntry ?? '', quote: true),
        (column: 'origin', value: d.origin.name, quote: false),
        (column: 'source_id', value: d.sourceId ?? '', quote: true),
      ],
    ];
  }

  @override
  String render(List<ResolvedGame> games) {
    final provenance = _hasProvenance(games);
    final buffer = StringBuffer(
        provenance ? '$_columns,$_provenanceColumns\r\n' : '$_columns\r\n');
    for (final g in games) {
      buffer.writeAll(
          [for (final c in _row(g, provenance)) c.quote ? _cell(c.value) : c.value],
          ',');
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// Leading characters Excel, LibreOffice and Google Sheets evaluate as a
  /// formula.
  ///
  /// Documented behaviour of those readers, not measured here: there is no
  /// spreadsheet in this repository and no run has had a GUI (T-0185).
  static const formulaLeaders = ['=', '+', '-', '@'];

  /// Read off the value, never off the emitted field: quoting settles where a
  /// cell ends and the reader strips the quotes before looking at the first
  /// character, so `"=a,b"` evaluates exactly as `=a` does (T-0182, T-0185).
  @override
  List<FormulaCell> formulaCells(ReviewDocument doc) {
    final games = select(doc);
    final provenance = _hasProvenance(games);
    return [
      for (final g in games)
        for (final c in _row(g, provenance))
          if (formulaLeaders.any(c.value.startsWith))
            (column: c.column, value: c.value),
    ];
  }

  /// The class is the three characters RFC 4180 requires quoting -- quote,
  /// CR, LF -- and the separator, which is the comma this writer hard-codes.
  /// A lone CR needs it as much as a LF does (T-0182): records here are
  /// terminated `\r\n`, so a spreadsheet reads an unquoted CR as the end of
  /// the record and every column after it shifts a row. Backslash is not an
  /// RFC 4180 escape and must not be touched (T-0166: a Windows path).
  ///
  /// It does not make a cell inert, and cannot: a spreadsheet evaluates text
  /// beginning `=`, `+`, `-` or `@` as a formula whether or not the field
  /// arrived quoted. Left unrewritten deliberately (T-0185) -- the documented
  /// consumer is an import dialog, which evaluates nothing, and the leading
  /// `'` that defuses Excel is Excel's own syntax and would be part of the
  /// title to every importer that is not one. [formulaCells] is what the user
  /// is told instead, at the point of export (T-0187); README, "Opening the
  /// CSV in a spreadsheet", is the page it points at.
  static String _cell(String value) => value.contains(RegExp(r'[",\r\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}

/// Tonkatsu Box exporter -- the Custom Cards import.
///
/// Format reference: hacan359/tonkatsu_box at `release/0.44`,
/// `lib/core/import/sources/custom_file/` -- `custom_cards_parser.dart`,
/// `custom_card_entry.dart` and `custom_cards_template.dart`. EXTERNAL
/// CONTRACT, the same standing as [TonkatsuExporter]'s: upstream changes get a
/// new writer rather than a mutation of this one.
///
/// **The row this exists for.** An `.xcoll` item IS a pair of ids, so a row
/// nothing resolved has none and [TonkatsuExporter] declines it -- correctly,
/// and that was the whole of the story since T-0012: such a row left through
/// CSV, which no Tonkatsu import reads. This is the other import that same app
/// already has, and it takes exactly that row -- a title and a type, every
/// other field optional.
///
/// **JSON and not the CSV upstream also accepts.** The JSON form types its
/// values, and this repository already writes a `.csv` whose columns mean
/// something else entirely; two `.csv` exports with different headers and
/// different audiences is the confusion [CsvExporter]'s `source_photo` was kept
/// narrow to avoid.
///
/// **A file this target writes must not depend on the importer being
/// forgiving.** Upstream turns a bad row into issues rather than a whole-file
/// failure -- but that is upstream's property to change, so nothing here rests
/// on it: [_card] refuses a row it cannot build and [render] omits it.
class TonkatsuCardsExporter extends Exporter {
  /// The other target's rule, asked rather than restated.
  ///
  /// The two Tonkatsu targets partition the approved rows, so this one's
  /// question is literally "would the other decline it?" -- and which catalogue
  /// a kind's `external_id` must come from is that exporter's rule and private
  /// to it. `review_screen.dart`'s `_pickReachesXcoll` holds an instance for
  /// the same reason: a second copy of that rule rots, and it has moved twice.
  final TonkatsuExporter _xcoll = TonkatsuExporter();

  @override
  String get name => 'tonkatsu-cards';

  @override
  String get extension => 'json';

  /// The `type` values the import accepts (`CustomCardFields.allowedTypes`).
  ///
  /// `custom` is deliberately absent upstream: the card is stored as a custom
  /// item whatever this field says, and the value only picks how it presents.
  /// Four of these are reachable from [WorkKind.wire] today; the list is kept
  /// whole because it is a transcription of an external vocabulary rather than
  /// a list of what this project happens to write.
  static const cardTypes = <String>{
    'game',
    'movie',
    'tv_show',
    'animation',
    'visual_novel',
    'manga',
    'anime',
    'book',
  };

  @override
  String get leftOutReason => 'carries only what .xcoll cannot -- an item with '
      'a resolved match belongs in that file instead.';

  /// The inverse of the default, and it points at the other file.
  ///
  /// This target takes what [TonkatsuExporter] leaves behind, so it comes back
  /// empty when nothing was left behind -- which on a fully matched shelf is
  /// the best outcome there is. The default sentence said the rows had no
  /// match, when having one is exactly why they are not here; a person told
  /// that goes looking for a resolution failure that did not happen. So this
  /// says what is true of the leftovers rather than of the matches -- [_card]
  /// refuses a leftover it cannot build, and that empties this file too --
  /// and then names the target the rows did go to, because exporting that one
  /// is the whole of what is left to do.
  @override
  String get carriedNothingReason =>
      'no approved item was left over for cards -- export .xcoll instead.';

  /// An empty array is `CustomCardsParseErrorCode.emptyFile` upstream, raised
  /// before any row is looked at (`custom_cards_parser.dart`, `release/0.44`),
  /// so `[]` is a whole-file failure there and not an import of nothing.
  @override
  bool get emptyFileIsUsable => false;

  /// The rows the other Tonkatsu target leaves behind, and only those.
  ///
  /// A partition rather than a second opinion: a row `.xcoll` can carry belongs
  /// in `.xcoll`, where the importer fetches metadata and a cover from an id.
  /// Sending it here as well would import one shelf twice, once as catalogue
  /// entries and once as bare cards.
  ///
  /// The second clause is whatever [_card] needs to build a row at all, asked
  /// here rather than listed again, so the shells' "carries none of the marked
  /// rows" and the file's contents cannot disagree.
  @override
  bool canExport(ResolvedGame game) =>
      !_xcoll.canExport(game) && _card(game) != null;

  @override
  String render(List<ResolvedGame> games) {
    // Throws on no member of the list. [Exporter.render]'s contract is that it
    // is only called for rows [canExport] accepted, which holds for
    // [Exporter.export] and not for a caller with a hand-built list -- and
    // this is the target where that matters, because its whole subject is the
    // rows nothing could resolve.
    final cards = <Map<String, Object?>>[];
    for (final game in games) {
      final card = _card(game);
      if (card != null) cards.add(card);
    }
    // A bare array: no envelope, so no clock. Unlike `.xcoll`, which stamps
    // `created` with `DateTime.now()`, one document renders to the same bytes
    // every time.
    return const JsonEncoder.withIndent('  ').convert(cards);
  }

  /// One card, or null where this pipeline holds nothing honest to build one
  /// from.
  ///
  /// **`title` and `type` are the whole of what upstream requires**, and the
  /// two optional keys below are the only ones this project can fill without
  /// inventing. Every other field of the import schema is refused on purpose:
  ///
  /// - **`cover`, under no condition.** It takes an `http(s)` URL and nothing
  ///   else; the only image this project holds is a photograph on the owner's
  ///   own disk, and a path off that machine must never leave it.
  /// - **`year`, under no condition.** The only year a row here can carry is
  ///   [Detection.sourceYear], whose own doc comment forbids exactly this --
  ///   on a scene name it is conventionally the year of the rip.
  ///   [Candidate.releaseYear] is the trustworthy one and is unreachable here
  ///   by construction: a row with a usable match went to `.xcoll`, so a match
  ///   left on this one is for the wrong catalogue and its year is a year for
  ///   a different work.
  /// - **`status`, `rating`, `comment`, `favorite`, `tags`, `rewatch_count`,
  ///   the two dates, `time_spent_minutes`, `current_episode`,
  ///   `current_season`** -- this tool collects none of them, and a default
  ///   written into a card is a claim the owner did not make.
  /// - **`description`, `genres`, `link`, `format`, `unit_total`,
  ///   `unit_group_total`** -- nothing upstream of this exporter holds a value
  ///   for them at all.
  static Map<String, Object?>? _card(ResolvedGame game) {
    // [CsvExporter]'s title cell, for its reason: a match's canonical name
    // where there is one, the read title where there is not.
    final title = game.best?.title ?? game.detection.rawTitle.trim();
    // [WorkKind.wire] and not a second mapping table -- it is already this
    // importer's vocabulary. The membership test is what makes a further kind
    // fail loudly here rather than write a row `unknownType` disqualifies.
    final type = game.detection.workKind.wire;
    if (title.isEmpty || !cardTypes.contains(type)) return null;

    final rawTitle = game.detection.rawTitle.trim();
    final platform = _platform(game);
    return {
      'title': title,
      'type': type,
      if (rawTitle.isNotEmpty && rawTitle != title) 'alt_title': rawTitle,
      if (platform != null) 'platform': platform,
    };
  }

  /// The platform text for a card, or null where writing one would invent it.
  ///
  /// [CsvExporter]'s chain, and its shape is that file's measurement rather
  /// than a preference: the hint is reached ONLY when nothing matched, because
  /// a match that names no platform names none. A `??` over
  /// [Candidate.platformName] would run past a matched row into the console
  /// hint the spine gave it before its kind was corrected.
  ///
  /// Restricted to [WorkKind.game] on top of that, which the CSV column is not.
  /// A card states its type and the other types have no platform at all, so a
  /// hint surviving onto one would be the same invention one field over.
  static String? _platform(ResolvedGame game) {
    if (game.detection.workKind != WorkKind.game) return null;
    final best = game.best;
    final text = best == null ? game.detection.platformHint : best.platformName;
    return text == null || text.isEmpty ? null : text;
  }
}

/// Exporter registry for the UI/CLI.
///
/// Appended to rather than reordered: the key order is published -- the CLI's
/// `Known:` line and the app's export sheet both read it -- so a new target
/// goes last and the two that shipped keep their places.
final exporters = <String, Exporter Function()>{
  'tonkatsu': TonkatsuExporter.new,
  'csv': CsvExporter.new,
  'tonkatsu-cards': TonkatsuCardsExporter.new,
};
