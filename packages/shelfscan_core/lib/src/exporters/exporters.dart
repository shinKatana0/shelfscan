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
  /// left here is the one honest gap: a row corrected to `Anime` and left
  /// there. The refusal is the same refusal and it is still true of that row;
  /// what changed is that it is no longer the only thing an animation row can
  /// be.
  undecidable(null),

  /// An anime film (T-0162).
  film(0),

  /// An anime series (T-0162).
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
  /// A row whose id this target cannot fill is refused by [_externalId].
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
  /// Leaving it would have refused an answered anime row for a second reason
  /// dressed as the first: the row would look like one whose catalogue nobody
  /// has chosen, when Tonkatsu files anime under a TMDB id and T-0162 measured
  /// it. [_PlatformId.undecidable] is what refuses the unanswered row, and it
  /// is the only thing that should.
  static String? _catalogue(WorkKind kind) => switch (kind) {
        WorkKind.game => igdbCatalogue,
        WorkKind.movie => tmdbCatalogue,
        WorkKind.animation ||
        WorkKind.animationFilm ||
        WorkKind.animationSeries =>
          tmdbCatalogue,
      };

  /// What Tonkatsu's item for this kind puts in `platform_id`.
  ///
  /// A switch with no default, so a fourth [WorkKind] cannot reach the writer
  /// without someone answering this for it -- the export string is the half of
  /// a new kind that is easiest to add and forget, because a wrong one still
  /// produces a well-formed file.
  static _PlatformId _platformId(WorkKind kind) => switch (kind) {
        WorkKind.game => _PlatformId.fromMatch,
        WorkKind.movie => _PlatformId.absent,
        WorkKind.animation => _PlatformId.undecidable,
        WorkKind.animationFilm => _PlatformId.film,
        WorkKind.animationSeries => _PlatformId.series,
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

/// Exporter registry for the UI/CLI.
final exporters = <String, Exporter Function()>{
  'tonkatsu': TonkatsuExporter.new,
  'csv': CsvExporter.new,
};
