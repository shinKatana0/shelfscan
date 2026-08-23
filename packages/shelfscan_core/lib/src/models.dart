/// Canonical data models.
///
/// The intermediate review document is the contract between the scan stage
/// and the export stage. Exporters never read vision output directly --
/// they only consume [ResolvedGame] entries approved during review.
library;

import 'dart:convert';

/// JSON that parsed but is not the shape a review document has (T-0050).
///
/// A named type rather than the raw cast failure the factories used to throw:
/// `on TypeError` around [ReviewDocument.fromJson] is the alternative, and it
/// cannot tell a hand-broken file from a bug in this parser -- both arrive as
/// the same `TypeError`, so the second would be reported to the user as the
/// first. `review.json` is hand-editable by design, which makes the wrong
/// shape an expected input and worth a message that names the field.
class ReviewFormatException implements Exception {
  ReviewFormatException(this.path, this.problem);

  /// Where, as a JSON path -- `games[3].detection.confidence`, or `''` for
  /// the document itself.
  final String path;

  /// What is wrong there, phrased for someone with the file open.
  final String problem;

  @override
  String toString() => path.isEmpty ? problem : '$path $problem';
}

String _foundType(Object? value) => switch (value) {
      null => 'missing',
      String() => 'a string',
      num() => 'a number',
      bool() => 'true/false',
      List() => 'a list',
      _ => 'an object',
    };

/// [value] as [T], or a [ReviewFormatException] naming [path] and [expected].
T _shape<T>(Object? value, String path, String expected) => value is T
    ? value
    : throw ReviewFormatException(
        path, 'is ${_foundType(value)}; it must be $expected');

/// The same for a field that may be left out: absent is fine, wrong is not.
T? _shapeOrNull<T>(Object? value, String path, String expected) =>
    value == null ? null : _shape<T>(value, path, expected);

String _at(String path, String key) => path.isEmpty ? key : '$path.$key';

/// An optional list of photo file names: absent is an empty list, wrong at
/// either level is a [ReviewFormatException] naming the level that is wrong.
List<String> _optionalPhotoNames(Object? value, String path, String expected) =>
    [
      for (final (index, name)
          in (_shapeOrNull<List<dynamic>>(value, path, expected) ?? const [])
              .indexed)
        _shape<String>(name, '$path[$index]', 'a photo file name'),
    ];

/// `''` and absent are the same absence for an optional photo name, and only
/// one of them is ever stored -- so no caller has to test for both.
String? _presentName(String? name) {
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// The same, for a photo name read out of JSON: absent is fine, wrong is not.
String? _photoName(Object? value, String path) =>
    _presentName(_shapeOrNull<String>(value, path, 'a photo file name'));

/// The physical CARRIER a row was read off, never what the row is a copy of
/// -- [WorkKind] is that, and decision 0015 is why the two are separate types
/// with one confusable name between them.
enum MediaType {
  cartridge,
  disc,
  unknown;

  static MediaType parse(String? v) => MediaType.values.firstWhere(
        (e) => e.name == v,
        orElse: () => MediaType.unknown,
      );
}

/// The kind of WORK a row is a copy of, as against [MediaType], which is the
/// carrier it came on: a disc case on a shelf holds a game or an anime, and
/// `.xcoll` has a field for the kind because Tonkatsu Box is a mixed-media
/// manager (decision 0015).
///
/// Not named for media, though `media_type` is the wire key on both sides:
/// that name already means the carrier throughout this repository -- in
/// `review.json`, in the CSV header, and in the vision schema whose
/// fingerprint `control_set_test.dart` pins -- and one name for two concepts
/// is what this type exists to stop.
///
/// EXTERNAL CONTRACT on the export side. `game` is the only value that has
/// been round-tripped through Tonkatsu Box's importer, which is what T-0009
/// verified; `anime` is Tonkatsu's own vocabulary for a kind it manages, but
/// this spelling of it is an assumption until an import measures it.
enum WorkKind {
  game,
  anime;

  /// Absent is [game] -- the whole collection was games before this field
  /// existed. An unrecognised value is NOT: `unknown` is an honest answer for
  /// a carrier the model could not tell, and there is no equivalent here, so
  /// a typo in a hand-edited document would land silently on a claim about
  /// what the row is. `review.json` is hand-editable by design (T-0050).
  static WorkKind parse(Object? value, String path) {
    final name = _shapeOrNull<String>(value, path, 'game or anime');
    if (name == null) return WorkKind.game;
    return WorkKind.values.firstWhere(
      (e) => e.name == name,
      orElse: () =>
          throw ReviewFormatException(path, 'is "$name"; it must be game or '
              'anime'),
    );
  }
}

/// Set by the human during the review step.
enum ReviewStatus {
  pending,
  approved, // exported
  rejected, // false positive, skipped on export
  edited; // human replaced the match manually

  static ReviewStatus parse(String? v) => ReviewStatus.values.firstWhere(
        (e) => e.name == v,
        orElse: () => ReviewStatus.pending,
      );
}

/// Values a model writes when it means "I have nothing here", written as
/// text instead of as JSON null.
///
/// Compared against the whole trimmed value, case-insensitively -- never as
/// a substring, so a genuine hint such as "Unknown Pleasures" survives.
const _absentMarkers = <String>{'null', 'none', 'unknown', 'n/a', '-', ''};

/// Normalizes an optional free-text field read from JSON.
///
/// The vision prompt describes optional fields with example text, and models
/// take that literally: qwen2.5vl:7b answered `"platform_hint": "null"` for
/// items whose platform it could not tell (T-0014). Left alone, the string
/// "null" reaches the review UI and the exports as a platform name, and it
/// makes "no hint at all" indistinguishable from "a hint was read".
///
/// This sits in [Detection.fromJson] rather than in each provider's parser
/// on purpose: it is the one choke point that both providers AND every read
/// of an existing `review.json` already pass through, so documents written
/// before the fix are healed on load.
String? _optionalText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return _absentMarkers.contains(trimmed.toLowerCase()) ? null : trimmed;
}

/// Why [hint] cannot be a platform at all, or null to keep it (T-0084).
///
/// `platformIds` is a lookup, not a vocabulary: `NINTENDO` is left unmapped on
/// purpose (T-0026) and `platformAgreement` matches such a hint against the
/// platform NAME IGDB returns (T-0002), so rejecting what the map does not key
/// would throw away hints the resolver uses today. What separates a platform
/// nobody mapped from a line of this project's own prompt is notation, not
/// vocabulary:
///
///   - the schema's menu separator. Measured at temperature 0 (T-0074):
///     `SWITCH2 | SWITCH` on every detection of one photo and
///     `SWITCH2 | N64 -- omit this field entirely if the platform is unclear`
///     on most of another; at 0.8 the whole schema line verbatim, on every row
///     of one photo and every row of another (T-0053). A pipe with
///     whitespace beside it, or a second pipe: `Xbox Series X|S` is the one
///     real platform name carrying a pipe and it has neither.
///   - `--`, the marker the schema line uses to gloss its own menu.
///   - length. The longest hint measured in this repository is
///     `NINTENDO SWITCH` (15 characters, T-0021); the longest name the
///     resolver's fallback can match a hint against is
///     `Super Nintendo Entertainment System` (35). The echo above is 68.
///
/// What it would wrongly reject: a hint transcribing a whole band rather than
/// the console name on it, and a human typing two consoles into one field at
/// review. Neither is measured; both land in [Detection.discardedPlatformHint]
/// where they stay visible, rather than in the platform column.
///
/// What it deliberately does not test is containment of prompt text: `SWITCH`
/// is prompt text and is also an answer the hi-res control run produces.
String? platformHintRejection(String hint) {
  if (_menuSeparator.hasMatch(hint)) {
    return 'reads as the prompt\'s "A | B" menu, not one console';
  }
  if (hint.contains('--')) {
    return 'carries the schema line\'s "--" gloss';
  }
  if (hint.length > _maxPlatformHintLength) {
    return 'is ${hint.length} characters, longer than any console name';
  }
  return null;
}

final _menuSeparator = RegExp(r'\|\s|\s\||\|[^|]*\|');

const _maxPlatformHintLength = 40;

/// Who put a detection into the document, and whether the title on it is a
/// transcription of something or a value somebody vouches for.
///
/// The vision stage cannot see everything: a logo-only spine (Nocturne 5
/// Royal in the T-0001 run) carries no text to read, and after T-0011 a
/// photo can also report spines it saw and failed to read. Those items
/// only ever enter the document because a human typed them, and the
/// difference matters downstream -- a manual title is ground truth, not a
/// noisy OCR guess, so it must not be presented (or scored) as one.
///
/// [metadata] and [filename] are the two values a non-photograph source can
/// carry (T-0155). Two rather than one, and the reason is the sentence above
/// rather than where the row came from: a GoG install's `goggame-*.info` names
/// the game because the installer wrote it there (T-0157), while a title cut
/// out of `Game.Name.2019.RePack-GROUP` is a guess with nobody behind it
/// (T-0158). One value would make those two indistinguishable at exactly the
/// point [isAuthoritative] is consulted -- which read of a game wins a merge
/// when a folder holds both (T-0160), how hard the review screen should push
/// the human to check a row, and what the resolver may match on. Where they
/// came from is [Detection.sourceEntry]'s job and is not this field's.
///
/// [vision] is the parse default on purpose: a `review.json` written before
/// this field existed carries no `origin` key, and everything in it came
/// from the model. A document written by a NEWER build reads its unknown
/// origin back as [vision] here, which is the same defaulting seen from the
/// other side and is why the values below are only ever added to.
enum DetectionOrigin {
  vision,

  manual,

  /// Read out of machine-written metadata shipped beside the game.
  metadata,

  /// Guessed out of a file or directory name.
  filename;

  /// Whether the title came from something that knows it, rather than from
  /// something that read it.
  ///
  /// The axis every consumer actually branches on, named once here so that
  /// adding the next source is a decision about this line and not a search
  /// for `== DetectionOrigin.x` across the repository.
  bool get isAuthoritative => this == manual || this == metadata;

  static DetectionOrigin parse(String? v) => DetectionOrigin.values.firstWhere(
        (e) => e.name == v,
        orElse: () => DetectionOrigin.vision,
      );
}

/// One item spotted by the vision worker on a photo. Raw, unresolved.
class Detection {
  Detection({
    required this.rawTitle,
    required this.mediaType,
    required this.confidence,
    required this.sourcePhoto,
    this.platformHint,
    this.notes,
    this.origin = DetectionOrigin.vision,
    this.addedFromPhoto,
    this.discardedPlatformHint,
    this.sourceEntry,
    this.sourceId,
    this.sourceYear,
    this.workKind = WorkKind.game,
  });

  /// An item the vision stage never produced, typed in by a human at review.
  ///
  /// [sourcePhoto] stays empty even when [addedFromPhoto] names a shelf: it
  /// was read off no photo, which is what that field means to every other
  /// stage -- dedupe counts rows per `source_photo` to rank how legible a
  /// photo was, and the csv export publishes it as provenance to a reader
  /// that has no `origin` column to qualify it with (T-0052).
  ///
  /// Confidence is 1.0 because a human-entered title is not an estimate. It
  /// no longer decides where the row lands: since T-0068 the resolve stage
  /// orders by [photoContext] and input position, confidence by nothing.
  factory Detection.manual({
    required String rawTitle,
    String? platformHint,
    MediaType mediaType = MediaType.unknown,
    String? notes,
    String? addedFromPhoto,
  }) =>
      Detection(
        rawTitle: rawTitle,
        platformHint: platformHint,
        mediaType: mediaType,
        confidence: 1.0,
        sourcePhoto: '',
        notes: notes,
        origin: DetectionOrigin.manual,
        addedFromPhoto: _presentName(addedFromPhoto),
      );

  /// A row produced from something that is not a photograph (T-0155).
  ///
  /// The invariants sit here rather than in each source, exactly as
  /// [Detection.manual] holds them for the review screen. [sourcePhoto] is
  /// empty because nothing was read off a photo -- T-0052's rule, and here it
  /// is load-bearing twice over: `dedupeDetections` does arithmetic on that
  /// field and the csv export publishes it as provenance to a reader with no
  /// `origin` column, so a directory name in it would be a photo file name to
  /// both. The name of the thing this was read from goes in [sourceEntry].
  ///
  /// Confidence follows [DetectionOrigin.isAuthoritative] and takes no
  /// argument: a name the installer wrote is not an estimate (1.0, as for a
  /// human-typed row), and a title cut out of a filename has no scale anyone
  /// could put a number on, so it gets this file's existing "nobody
  /// estimated" value rather than an invented one -- 0.0 is what
  /// [Detection.fromJson] already reads an absent `confidence` as. Nothing
  /// ranks on it: since T-0068 the field orders nothing, and in dedupe it is
  /// the last tiebreak between rows already agreed to be one game.
  factory Detection.fromSource({
    required String rawTitle,
    required DetectionOrigin origin,
    required String sourceEntry,
    String? platformHint,
    MediaType mediaType = MediaType.unknown,
    String? notes,
    String? sourceId,
    int? sourceYear,
  }) {
    assert(
        origin == DetectionOrigin.metadata ||
            origin == DetectionOrigin.filename,
        'a source row is metadata or filename: vision means read off a photo, '
        'manual means typed at review');
    return Detection(
      rawTitle: rawTitle,
      platformHint: platformHint,
      mediaType: mediaType,
      confidence: origin.isAuthoritative ? 1.0 : 0.0,
      sourcePhoto: '',
      notes: notes,
      origin: origin,
      sourceEntry: _presentName(sourceEntry),
      sourceId: _presentName(sourceId),
      sourceYear: sourceYear,
    );
  }

  /// Text exactly as readable on the spine/cover.
  final String rawTitle;

  /// e.g. "SNES", guessed from form factor / logo. Null if unclear, and null
  /// when what was read was not a platform at all ([discardedPlatformHint]).
  final String? platformHint;
  final MediaType mediaType;

  /// What this row is a copy of, which is a property of the ROW and not of the
  /// run that found it (decision 0015): one shelf holds both, one photograph
  /// reads both, and one collection imports both.
  ///
  /// Read here rather than on [ResolvedGame] because the stage that would
  /// route it -- pick which catalogue answers this title -- consumes a
  /// [Detection] and produces a [ResolvedGame], so a kind decided after
  /// resolution would be decided too late to route anything.
  ///
  /// Mutable, alone among this class's fields, because the review step
  /// corrects it (decision 0015, the owner's mitigation): the kind is
  /// INFERRED on a source that has no prompt, a filename never announces that
  /// it is not what it looks like, and a person looking at the row is the only
  /// party who can see that the inference was wrong. [ResolvedGame.best] and
  /// [ResolvedGame.status] are non-final for the same reason and are the
  /// precedent.
  ///
  /// Correcting it is not a rename: it changes which catalogue answers the
  /// row, so [ResolvedGame.correctWorkKind] clears the match and marks the row
  /// rather than writing the new word beside the old match.
  ///
  /// No source reads a kind yet, so nothing but review sets it away from
  /// [WorkKind.game].
  WorkKind workKind;

  /// 0..1, the vision model's own estimate.
  final double confidence;

  /// Photo file name of the photo this was READ off. Empty for a manual
  /// entry -- it came off no photo.
  final String sourcePhoto;

  /// Free-form vision remarks ("label worn").
  final String? notes;

  final DetectionOrigin origin;

  /// The photo the human had in front of them when they typed this row
  /// (T-0052). Null on a vision row, and null for a row typed with no photo
  /// in view.
  ///
  /// A second field rather than a second meaning for [sourcePhoto]: "read
  /// off this photo" is a claim `dedupeDetections` does arithmetic on and
  /// the csv export publishes, and csv has no `origin` column with which a
  /// reader could tell the two claims apart. Optional and additive, so a
  /// `review.json` written before it parses unchanged -- the same treatment
  /// [origin] and `unreadable` got, and the reason the document version
  /// stays 1.
  final String? addedFromPhoto;

  /// What [platformHint] would have been, had it been a platform (T-0084).
  ///
  /// A field of its own rather than a line appended to [notes]: `notes` is the
  /// model's own remarks about the item, and a count of rows this happened to
  /// needs something to count that is not a substring match. Optional and
  /// additive, so a `review.json` written before it parses unchanged and the
  /// document version stays 1 -- the treatment [origin] and [addedFromPhoto]
  /// got.
  ///
  /// Not discarded, despite the name: the value is kept here precisely because
  /// the failure it comes from is quiet by construction. An unresolvable hint
  /// yields no IGDB rows, the row reaches review "unmatched", and `CsvExporter`
  /// publishes the hint in the platform column, where it reads as a plausible
  /// answer rather than as the prompt line it is.
  final String? discardedPlatformHint;

  /// The file or directory this row was read from ([Detection.fromSource]).
  /// Null on every row read off a photograph or typed at review.
  ///
  /// The row's own provenance, which nothing else on it carries: [sourcePhoto]
  /// is empty for a source row and [origin] names the KIND of source, not the
  /// thing. Without it a folder of 300 installs reviews as 300 rows nobody can
  /// trace back, and the review screen has nothing to group them under
  /// (T-0161) -- which is why it is here rather than left to the shell that
  /// enumerated the folder: the shell no longer has the row.
  ///
  /// Optional and additive, so a `review.json` written before it parses
  /// unchanged and the document version stays 1 -- the treatment [origin],
  /// [addedFromPhoto] and [discardedPlatformHint] got.
  final String? sourceEntry;

  /// What the catalogue this row was read from calls the game, as
  /// `catalogue:id` -- `gog:1100000014` for a GoG install (T-0157).
  ///
  /// A stable external id, which is what separates this from every other field
  /// on the row: T-0159 joins it against IGDB's `external_games` instead of
  /// matching a title string, and that join is exact or it is nothing.
  ///
  /// Namespaced rather than bare because the number alone is only unique
  /// inside one store, and two stores' ids colliding would resolve one game to
  /// another with nothing visible to a reader -- the silent-failure class
  /// decision 0012 lists. The prefix is the source's own constant
  /// (`GogMetadataSource.idPrefix`), so a consumer splits at the first `:`
  /// rather than guessing which store answered.
  ///
  /// Not derivable from [sourceEntry], which happens to contain the digits
  /// today only because GoG puts them in the file name; the value here is the
  /// `gameId` the installer wrote inside the file.
  ///
  /// Optional and additive, so a `review.json` written before it parses
  /// unchanged and the document version stays 1.
  final String? sourceId;

  /// The release year the SOURCE printed, when it printed one where a title
  /// cannot be (`parseGameFileName`'s positional rule, T-0158).
  ///
  /// A claim about the name, never a fact about the game, and that is the
  /// whole of what a consumer may treat it as. The rule that produced it reads
  /// position, not meaning: a four-digit token is a year only when something
  /// follows it, so `Game.Name.2019.RePack-GROUP` answers 2019 and `MOOR 2016`
  /// answers nothing — and 2019 there is whatever the namer put in that slot,
  /// which on a scene name is conventionally the release and may be the year
  /// the rip was made. Nothing downstream may render it as the game's year
  /// ([Candidate.releaseYear] is that, from IGDB), export it, or narrow a
  /// search with it. The one use T-0171 wired is choosing between rows the
  /// resolver has already judged equal — `ResolverWorker._best`, which carries
  /// the argument for why that is the only entitled one.
  ///
  /// Null on everything read off a photograph: no read of either control set
  /// contains a four-digit year, because no spine prints one
  /// (T-0165). Absent rather than null in JSON, for the reason [sourceEntry]
  /// and [sourceId] are: a photo-only scan keeps writing the bytes it wrote
  /// before this field existed.
  final int? sourceYear;

  bool get isManual => origin == DetectionOrigin.manual;

  /// This detection reading one of the several entries it maps to, for
  /// [ResolvedGame.expandParts].
  ///
  /// Everything but the title is kept, and [sourcePhoto] above all: the part
  /// was read off the same photograph as the box, so it belongs in the same
  /// group on the review screen and carries the same provenance into the csv
  /// export. Private because a general `copyWith` on this class would be an
  /// invitation to rewrite fields the pipeline treats as facts about where a
  /// row came from.
  Detection _withRawTitle(String title) => Detection(
        rawTitle: title,
        mediaType: mediaType,
        confidence: confidence,
        sourcePhoto: sourcePhoto,
        platformHint: platformHint,
        notes: notes,
        origin: origin,
        addedFromPhoto: addedFromPhoto,
        discardedPlatformHint: discardedPlatformHint,
        sourceEntry: sourceEntry,
        sourceId: sourceId,
        sourceYear: sourceYear,
        workKind: workKind,
      );

  /// Which photo this row belongs with on the review screen: the one it was
  /// read off, or failing that the one it was typed from. Empty means
  /// neither, which is the screen's "Not from a photo" group.
  ///
  /// [sourcePhoto] wins if a hand-edited document sets both: a read is a
  /// stronger claim than a note about what was on screen at the time.
  String get photoContext =>
      sourcePhoto.isNotEmpty ? sourcePhoto : (addedFromPhoto ?? '');

  /// True when a raw detection map carries a title worth reviewing.
  ///
  /// qwen2.5vl:32b emitted one detection of 40 with an empty `raw_title` and
  /// a `PS5` hint (2026-08-14), and it travelled into the review document as
  /// a row containing nothing. Such a row is noise from the moment it is
  /// parsed: `titleKey` folds it to the empty string, so two of them off
  /// different photos merge into one meaningless row; `CsvExporter.canExport`
  /// refuses it (T-0012) and `.xcoll` needs an id it can never resolve, so no
  /// target can export it either. All it can do is cost the human a row to
  /// reject.
  ///
  /// A static gate rather than a check inside [fromJson] because a factory
  /// cannot decline to build. Callers drop the row and record
  /// [UnreadSpineReport.titleless] in its place.
  static bool hasTitle(Map<String, dynamic> json) {
    final title = json['raw_title'];
    return title is String && title.trim().isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
        'raw_title': rawTitle,
        'platform_hint': platformHint,
        'media_type': mediaType.name,
        'confidence': confidence,
        'source_photo': sourcePhoto,
        'notes': notes,
        'origin': origin.name,
        'added_from_photo': addedFromPhoto,
        'discarded_platform_hint': discardedPlatformHint,
        // Absent rather than null when there is none, unlike every optional
        // key above it: a photo-only scan has to keep writing the bytes it
        // wrote before this field existed, which is the reproducibility
        // T-0053, T-0068 and T-0085 each paid for separately.
        if (sourceEntry != null) 'source_entry': sourceEntry,
        if (sourceId != null) 'source_id': sourceId,
        if (sourceYear != null) 'source_year': sourceYear,
        // Absent at the default for the reason the three above are absent when
        // empty, and here it covers every document anyone has yet written: a
        // scan of games writes the exact bytes it wrote before this field
        // existed.
        if (workKind != WorkKind.game) 'work_kind': workKind.name,
      };

  /// Every field except `raw_title` is optional, so the minimum a human has
  /// to hand-write into a `review.json` is a title and an origin (see the
  /// CLI usage header). Same choke point as [_optionalText]: documents
  /// written before `origin` existed read back as [DetectionOrigin.vision].
  ///
  /// [path] is where this object sits in the document being read, for the
  /// message a wrong-typed field produces; the default suits a caller that
  /// has only one object to talk about.
  ///
  /// A hint that is not a platform ([platformHintRejection]) crosses to
  /// [discardedPlatformHint] here for the same reason the absence markers are
  /// normalized here: this is the one choke point both providers and every
  /// read of an existing `review.json` pass through, so a document written
  /// before the check heals on load. Re-parsing what this writes moves
  /// nothing a second time -- the value is no longer in `platform_hint`.
  factory Detection.fromJson(Map<String, dynamic> json, {String path = ''}) {
    final hint = _optionalText(json['platform_hint']);
    final rejected = hint != null && platformHintRejection(hint) != null;
    return Detection(
      rawTitle: _shape<String>(json['raw_title'], _at(path, 'raw_title'),
          'the text readable on the spine'),
      platformHint: rejected ? null : hint,
      discardedPlatformHint: rejected
          ? hint
          : _optionalText(json['discarded_platform_hint']),
      mediaType: MediaType.parse(_shapeOrNull<String>(json['media_type'],
          _at(path, 'media_type'), 'cartridge, disc or unknown')),
      workKind: WorkKind.parse(json['work_kind'], _at(path, 'work_kind')),
      confidence: _shapeOrNull<num>(json['confidence'], _at(path, 'confidence'),
                  'a number between 0 and 1')
              ?.toDouble() ??
          0.0,
      sourcePhoto: _shapeOrNull<String>(json['source_photo'],
              _at(path, 'source_photo'), 'a photo file name') ??
          '',
      notes: _optionalText(json['notes']),
      origin: DetectionOrigin.parse(_shapeOrNull<String>(
          json['origin'], _at(path, 'origin'),
          'vision, manual, metadata or filename')),
      addedFromPhoto:
          _photoName(json['added_from_photo'], _at(path, 'added_from_photo')),
      sourceEntry: _presentName(_shapeOrNull<String>(json['source_entry'],
          _at(path, 'source_entry'), 'the file or folder this row was read '
              'from')),
      sourceId: _presentName(_shapeOrNull<String>(json['source_id'],
          _at(path, 'source_id'), "the catalogue's own id, as catalogue:id")),
      // [Candidate.releaseYear]'s treatment, for its reason: never
      // model-written text, so a string here is a broken file rather than a
      // "none" for [_optionalText] to heal.
      sourceYear: _shapeOrNull<num>(json['source_year'],
              _at(path, 'source_year'), 'a four-digit year')
          ?.toInt(),
    );
  }
}

/// Writing system a spine appears to be printed in.
///
/// A guess about the SHAPE of the characters, never about their meaning:
/// the model is allowed to say "these look Japanese" precisely because it
/// could not read them.
enum SpineScript {
  japanese,
  latin,
  unknown;

  static SpineScript parse(String? v) => SpineScript.values.firstWhere(
        (e) => e.name == v,
        orElse: () => SpineScript.unknown,
      );
}

/// One report of spines the model saw but could not read.
///
/// A report, not a spine: `gpt-4.1-mini` answers a single entry naming two or
/// three middle spines on `CONTROL-HIRES` `shelf-3`, 10 of 10 runs, against a
/// hand count off the photograph that the entry never matches; and a second
/// photo answers one entry on 8 runs and two on 2 for one and the same group
/// of spines (T-0109). So a count of these is a
/// lower bound on spines and never a count of them. The type was named
/// `UnreadableSpine` until T-0154, and that name is what taught four separate
/// sites to count spines (T-0151).
///
/// Deliberately NOT a [Detection] and never merged into one: T-0007 forbids
/// an unread item from entering `items`, and this type exists so that
/// obeying that rule no longer costs the signal that something was there.
/// It carries no title field at all, so there is nowhere to put a guess.
class UnreadSpineReport {
  UnreadSpineReport({
    required this.sourcePhoto,
    this.script = SpineScript.unknown,
    this.reason,
  });

  /// The record left where a detection with no title used to be
  /// ([Detection.hasTitle]).
  ///
  /// The model listed a spine and named nothing on it, which is this class's
  /// definition, so the row is counted here rather than dropped in silence --
  /// the failure T-0025 and T-0030 are both about. Chosen over
  /// `ScanProgress.onWarning` because half of this fix runs while reading an
  /// existing `review.json`, where no progress object exists; this channel is
  /// persisted in the document, and the CLI summary and the review screen
  /// both already display it.
  ///
  /// T-0028 measured that the entries the model writes into `unreadable`
  /// itself carry no perception on the local 7B; this one is not of that
  /// kind, being derived from a row the model really did emit. It is the only
  /// entry the local path can still produce (T-0032).
  ///
  /// [script] stays unknown: the row carried no characters to judge. The
  /// source photo is empty for a hand-written manual entry, the same as on
  /// the [Detection] it replaces -- including one that names a
  /// [Detection.addedFromPhoto]. This list is what the model PERCEIVED on a
  /// photo, and blaming a photo for a human's blank row would inflate that
  /// photo's unread count in `unreadableByPhoto` with something nobody saw:
  /// the fabricated count T-0028 removed.
  factory UnreadSpineReport.titleless({required String sourcePhoto}) =>
      UnreadSpineReport(
        sourcePhoto: sourcePhoto,
        reason: 'listed as an item with an empty title',
      );

  /// Photo file name, so counts can be reported per photo.
  final String sourcePhoto;

  /// What the characters looked like, not what they said.
  final SpineScript script;

  /// Short free-text reason ("characters too small to resolve").
  final String? reason;

  Map<String, dynamic> toJson() => {
        'source_photo': sourcePhoto,
        'script': script.name,
        'reason': reason,
      };

  factory UnreadSpineReport.fromJson(Map<String, dynamic> json,
          {String path = ''}) =>
      UnreadSpineReport(
        sourcePhoto: _shapeOrNull<String>(json['source_photo'],
                _at(path, 'source_photo'), 'a photo file name') ??
            '',
        script: SpineScript.parse(_shapeOrNull<String>(json['script'],
            _at(path, 'script'), 'japanese, latin or unknown')),
        // Same textual-absence normalization the detections get: a model
        // that writes "none" as a reason means it has none.
        reason: _optionalText(json['reason']),
      );
}

/// How a [Candidate] was arrived at -- a fact about the match, where every
/// other field on it is a fact about the game.
///
/// [Candidate.score] cannot carry this and must not be asked to. An exact join
/// writes 1.0 because identity is the honest reading of the only field there
/// was, but 18 of T-0159's 394 live joins carry a store title that is NOT
/// IGDB's canonical name (an abbreviated edition against the full subtitle it
/// stands for is the commonest shape; the rows are a real library's and are
/// not named), so on those rows 1.0 is true of the match and false of the
/// strings. A reviewer reading one number cannot tell which claim is being
/// made, and when a join is wrong -- an IGDB data error -- nobody can tell
/// afterwards which mechanism produced the row (T-0172).
///
/// [fuzzy] is the parse default for the reason [DetectionOrigin.vision] is: a
/// `review.json` written before this field existed carries no key, and every
/// match in it was scored against a string.
enum MatchMethod {
  fuzzy,

  /// The store's own product id joined to IGDB `external_games` (T-0159).
  /// No gate applies to it -- [minAutoScore], `platformAgreement`,
  /// `volumeNumbersAgree` and the tie rule all exist to make a guess safe.
  externalId;

  static MatchMethod parse(String? v) => MatchMethod.values.firstWhere(
        (e) => e.name == v,
        orElse: () => MatchMethod.fuzzy,
      );
}

/// One possible IGDB match for a detection.
class Candidate {
  Candidate({
    required this.igdbId,
    required this.title,
    required this.platformId,
    required this.platformName,
    required this.score,
    this.matchedAlternativeName,
    this.releaseYear,
    this.matchMethod = MatchMethod.fuzzy,
  });

  final int igdbId;

  /// Canonical IGDB name -- what gets exported and what the target app
  /// shows, even when [matchedAlternativeName] is what actually matched.
  final String title;
  final int platformId;
  final String platformName;

  /// 0..1 fuzzy match score.
  final double score;

  /// The IGDB alternative name that beat the canonical one, if any.
  ///
  /// Without it a Japanese spine matching an English canon name is baffling
  /// at review: the reviewer sees "Resident Evil 4" against a raw title that
  /// says "Biohazard" and has no way to tell a good match from a wrong one.
  ///
  /// Optional in JSON: `review.json` files written before this field existed
  /// carry no key, and absent means "the canonical name matched".
  final String? matchedAlternativeName;

  /// IGDB's `first_release_date` year, or null where IGDB stores none -- a
  /// small fraction of the games one control run touches (T-0165).
  ///
  /// It is what separates two rows the resolver refuses to choose between:
  /// a title returned twice under one name at two release years, and a title
  /// tied against a differently named edition of itself -- measured live on
  /// T-0156's desktop titles. Every other field on such a pair is
  /// identical, `score` included at 1.000 (T-0170).
  ///
  /// Optional in JSON, like [matchedAlternativeName]: absent means IGDB has no
  /// date for the game, and nothing may render it as a year.
  final int? releaseYear;

  final MatchMethod matchMethod;

  Map<String, dynamic> toJson() => {
        'igdb_id': igdbId,
        'title': title,
        'platform_id': platformId,
        'platform_name': platformName,
        'score': score,
        'matched_alternative_name': matchedAlternativeName,
        'release_year': releaseYear,
        'match_method': matchMethod.name,
      };

  factory Candidate.fromJson(Map<String, dynamic> json, {String path = ''}) =>
      Candidate(
        igdbId: _shape<int>(
            json['igdb_id'], _at(path, 'igdb_id'), 'an IGDB game id'),
        title: _shape<String>(
            json['title'], _at(path, 'title'), 'the canonical IGDB title'),
        platformId: _shape<int>(json['platform_id'], _at(path, 'platform_id'),
            'an IGDB platform id'),
        platformName: _shape<String>(json['platform_name'],
            _at(path, 'platform_name'), 'the platform name'),
        score: _shape<num>(json['score'], _at(path, 'score'),
                'a number between 0 and 1')
            .toDouble(),
        matchedAlternativeName:
            _optionalText(json['matched_alternative_name']),
        // Not [_optionalText]'s treatment: this value is never model-written
        // text, so a string here is a broken file rather than a "none" to heal.
        releaseYear: _shapeOrNull<num>(json['release_year'],
                _at(path, 'release_year'), 'a four-digit year')
            ?.toInt(),
        matchMethod: MatchMethod.parse(_shapeOrNull<String>(
            json['match_method'], _at(path, 'match_method'),
            'fuzzy or externalId')),
      );
}

/// One entry in an external catalogue, held by a row that maps to it.
///
/// ASSUMED SHAPE, and deliberately the smallest one that can say which entry
/// is meant (T-0163). Nothing in this repository has yet called a catalogue
/// that answers per season, so every field here is a guess about what such an
/// answer contains, written as a type rather than as prose so that the task
/// building the catalogue seam reconciles against it instead of discovering it
/// disagrees. Widen it when a real call measures what comes back.
///
/// NOT a [Candidate], and the distinction is the whole point of this class.
/// A candidate is a scored GUESS at what one row is, drawn from IGDB, and
/// picking one discards the others. An entry here is not scored and not a
/// guess: it is an entry the row maps to, and where a row maps to several they
/// are all true at once.
class CatalogueEntry {
  const CatalogueEntry({
    required this.title,
    required this.ref,
    this.ordinal,
  });

  /// What the catalogue calls this entry.
  final String title;

  /// The entry's id in the form `catalogue:id`, which is the convention
  /// [Detection.sourceId] already uses for a store's own id -- a consumer
  /// splits at the first `:` rather than guessing which service answered.
  ///
  /// A string rather than an int because the catalogue is not fixed here.
  /// [Candidate.igdbId] is an int precisely because it is only ever IGDB's;
  /// this field's whole job is to be answerable by a service nobody has
  /// chosen yet.
  final String ref;

  /// Season or volume number AS THE CATALOGUE PRINTS IT, null where it prints
  /// none.
  ///
  /// Never inferred from a digit in [title]. This project refuses to read a
  /// sequel number out of a title (T-0055, T-0059) and a season number is
  /// exactly that shape, so the refusal applies unchanged: the number is here
  /// only when something that knows the answer supplied it.
  final int? ordinal;

  Map<String, dynamic> toJson() => {
        'title': title,
        'ref': ref,
        if (ordinal != null) 'ordinal': ordinal,
      };

  factory CatalogueEntry.fromJson(Map<String, dynamic> json,
          {String path = ''}) =>
      CatalogueEntry(
        title: _shape<String>(json['title'], _at(path, 'title'),
            "the catalogue entry's title"),
        ref: _shape<String>(
            json['ref'], _at(path, 'ref'), 'an entry id, as catalogue:id'),
        // [Candidate.releaseYear]'s treatment: never model-written text, so a
        // string here is a broken file rather than a "none" to heal.
        ordinal: _shapeOrNull<num>(json['ordinal'], _at(path, 'ordinal'),
                'a season or volume number')
            ?.toInt(),
      );
}

/// A detection with its best IGDB match and alternatives.
class ResolvedGame {
  ResolvedGame({
    required this.detection,
    this.best,
    this.candidates = const [],
    this.status = ReviewStatus.pending,
    this.parts = const [],
    this.needsReresolution = false,
  });

  final Detection detection;

  /// Null = resolver found nothing confident enough.
  Candidate? best;
  final List<Candidate> candidates;
  ReviewStatus status;

  /// The catalogue entries this one row maps to (T-0163).
  ///
  /// A DIFFERENT RELATION from [candidates], and naming it by that name would
  /// have been wrong: candidates compete and parts coexist. Picking a
  /// candidate discards the rest, because only one of them can be what this
  /// row is; picking one part and discarding the rest would throw away seasons
  /// the person owns. A candidate is also scored and a part is not -- there is
  /// nothing to rank when all of them are true.
  ///
  /// Read by length, which is what makes expansion idempotent:
  ///
  /// - empty -- nobody looked, or the row is an ordinary IGDB game row;
  /// - one -- the row is one entry and there is nothing to offer;
  /// - several -- the row is a BOX and these are its contents, which is the
  ///   case [expandParts] exists for.
  ///
  /// The unit question this settles, and the owner settled it rather than this
  /// type: `.xcoll` carries one `external_id` per item and a catalogue that
  /// answers per season answers several, so a box set of three seasons is one
  /// object on a shelf and three entries in a catalogue. Making the row the
  /// box breaks the export, making it the entry stops the list matching the
  /// shelf, and making it the series loses which seasons are owned. So the row
  /// stays the box, carries what it maps to, and the person holding the box
  /// decides at review.
  final List<CatalogueEntry> parts;

  /// The row's kind was corrected at review, so whatever it was matched
  /// against was the wrong catalogue (decision 0015).
  ///
  /// A mark, not a match: the client that would answer the other catalogue is
  /// another task's, so what this records is that the row is OWED a lookup.
  /// Set with [correctWorkKind], which clears the stale match at the same
  /// time -- a correction that kept the old match would buy a right word and a
  /// wrong match, which is the failure the correction exists to prevent.
  bool needsReresolution;

  /// True when this row is a box rather than a thing -- see [parts].
  bool get mapsToSeveral => parts.length > 1;

  /// The N rows this one becomes when the person holding the box says to
  /// expand it; itself, unchanged, when there is nothing to expand.
  ///
  /// Each row carries exactly one [CatalogueEntry], so none of them offers to
  /// expand again and running this twice changes nothing.
  ///
  /// [best] and [candidates] do not survive: both were answers about the box,
  /// and a part inheriting the box's IGDB match would export every part as the
  /// same item. The detection is copied rather than shared so that correcting
  /// one part's kind cannot move its siblings.
  List<ResolvedGame> expandParts() {
    if (!mapsToSeveral) return [this];
    return [
      for (final part in parts)
        ResolvedGame(
          detection: detection._withRawTitle(part.title),
          parts: [part],
          status: ReviewStatus.pending,
        ),
    ];
  }

  /// Correct what kind of work this row is a copy of, and route it again.
  ///
  /// Not a relabel, which is the half decision 0015 says is not optional: a
  /// row corrected from one kind to another has to resolve against the other
  /// catalogue. Clearing [best] is what makes that true today -- the row stops
  /// claiming a match it no longer has any reason to hold -- and
  /// [needsReresolution] is what a resolver pass reads to know the row is
  /// owed one.
  ///
  /// Correcting a row back to the kind it already had does nothing, so
  /// tapping the value it is already on cannot silently drop a good match.
  void correctWorkKind(WorkKind kind) {
    if (detection.workKind == kind) return;
    detection.workKind = kind;
    best = null;
    needsReresolution = true;
    status = ReviewStatus.pending;
  }

  Map<String, dynamic> toJson() => {
        'detection': detection.toJson(),
        'best': best?.toJson(),
        'candidates': candidates.map((c) => c.toJson()).toList(),
        'status': status.name,
        // Absent at the default, for the reason `source_entry` and
        // `work_kind` are absent when empty: a scan that maps every row to one
        // thing writes the bytes it wrote before either field existed, and the
        // document version stays 1 because nothing about the old shape moved.
        if (parts.isNotEmpty)
          'parts': parts.map((p) => p.toJson()).toList(),
        if (needsReresolution) 'needs_reresolution': true,
      };

  factory ResolvedGame.fromJson(Map<String, dynamic> json,
      {String path = ''}) {
    final candidatesPath = _at(path, 'candidates');
    final partsPath = _at(path, 'parts');
    final best = _shapeOrNull<Map<String, dynamic>>(json['best'],
        _at(path, 'best'), 'the chosen IGDB match, or null for no match');
    return ResolvedGame(
      detection: Detection.fromJson(
          _shape<Map<String, dynamic>>(json['detection'],
              _at(path, 'detection'), 'an object with a "raw_title"'),
          path: _at(path, 'detection')),
      best: best == null
          ? null
          : Candidate.fromJson(best, path: _at(path, 'best')),
      candidates: [
        for (final (index, candidate) in (_shapeOrNull<List<dynamic>>(
                    json['candidates'],
                    candidatesPath,
                    'a list of IGDB matches') ??
                const [])
            .indexed)
          Candidate.fromJson(
              _shape<Map<String, dynamic>>(
                  candidate, '$candidatesPath[$index]', 'an IGDB match'),
              path: '$candidatesPath[$index]'),
      ],
      status: ReviewStatus.parse(_shapeOrNull<String>(json['status'],
          _at(path, 'status'), 'pending, approved, rejected or edited')),
      parts: [
        for (final (index, part) in (_shapeOrNull<List<dynamic>>(json['parts'],
                    partsPath, 'a list of catalogue entries') ??
                const [])
            .indexed)
          CatalogueEntry.fromJson(
              _shape<Map<String, dynamic>>(
                  part, '$partsPath[$index]', 'a catalogue entry'),
              path: '$partsPath[$index]'),
      ],
      needsReresolution: _shapeOrNull<bool>(json['needs_reresolution'],
              _at(path, 'needs_reresolution'),
              'true when the row is owed a lookup') ??
          false,
    );
  }
}

/// What a warning line and a [DeclinedEntry] MEAN, carried as a value because
/// once either is flattened to a sentence the two are indistinguishable
/// (T-0222).
///
/// The first real scan produced four warning lines, every one of them an
/// [exclusion] -- a non-GOG release, DLC, releases Galaxy hides, a numbered
/// copy -- painted in `colorScheme.error` under one heading, and read them as
/// errors. Nothing had failed. Each line was a filter documented in
/// `GogLibrarySource` reporting itself, which is what working looks like.
///
/// Not inferred from the reason text. This screen already decided a class by
/// matching the orchestrator's sentence with `startsWith` until T-0145, so a
/// rewording in core changed the UI's behaviour; the fix then was that the
/// document names the class itself, and this is the same shape.
///
/// Ordered least-to-most severe: a group of entries takes the maximum of its
/// members, so one real failure among fifty silences still shows as one.
enum Severity {
  /// The source read the entry, understood it, and deliberately made no row of
  /// it. A documented, pre-measured omission -- nothing to fix and nothing
  /// went wrong.
  exclusion,

  /// Something the run wanted and did not get: a photo whose call died, a row
  /// whose shape was not the one its schema promises, a resolution that
  /// failed. The default when nothing states otherwise, because a failure
  /// dressed as a silence is the worse of the two mistakes (decision 0012).
  failure,
}

/// One thing a source was handed and made no row out of (T-0155).
///
/// Declining is the source working, not failing: a games folder holds saves,
/// patches, screenshots and DLC archives, and a title guessed off one of those
/// costs an IGDB call and a row the human has to reject (T-0160). What may not
/// happen is the decline being silent, which is decision 0012's standing rule
/// and this project's most-filed defect class.
///
/// Deliberately NOT an [UnreadSpineReport], and the reason is the one that type
/// records for itself: that list is what a model PERCEIVED on a photograph and
/// `unreadableByPhoto` counts it per photo. Nothing looked at anything here,
/// and filing it there would inflate a photo's count with an entry nobody saw
/// -- the fabricated count T-0028 removed.
class DeclinedEntry {
  const DeclinedEntry({
    required this.name,
    required this.reason,
    this.severity = Severity.failure,
  });

  /// [SourceEntry.name] as the shell handed it over.
  final String name;

  /// Completes "Skipped <name>: ", so it is written as a fragment and shown
  /// to the user as it stands.
  final String reason;

  /// Which of [Severity]'s two things this decline is.
  ///
  /// Defaulted rather than required, and defaulted to the loud side: a decline
  /// site that says nothing is painted as a failure, so the way to get an
  /// exclusion is to claim one. Every source in this package states it; the
  /// default is what covers a new one that forgets, and a document written
  /// before this field existed.
  final Severity severity;

  Map<String, dynamic> toJson() =>
      {'name': name, 'reason': reason, 'severity': severity.name};

  factory DeclinedEntry.fromJson(Map<String, dynamic> json,
          {String path = ''}) =>
      DeclinedEntry(
        name: _shape<String>(json['name'], _at(path, 'name'),
            'the name of the file or folder that was skipped'),
        reason: _shape<String>(json['reason'], _at(path, 'reason'),
            'why it was skipped'),
        severity: Severity.values.asNameMap()[_shapeOrNull<String>(
                json['severity'],
                _at(path, 'severity'),
                'exclusion or failure')] ??
            Severity.failure,
      );
}

/// Top-level intermediate artifact: written by scan, read by export.
class ReviewDocument {
  ReviewDocument({
    required this.version,
    required this.created,
    required this.photos,
    required this.games,
    this.unreadable = const [],
    this.failedPhotos = const [],
    this.notLookedAtPhotos = const [],
    this.declinedEntries = const [],
  });

  final int version;
  final String created; // ISO timestamp
  final List<String> photos;

  /// Must be growable: the review step adds manually entered items to it
  /// (T-0012), and both the orchestrator and [fromJson] build it with
  /// `toList()` for that reason.
  final List<ResolvedGame> games;

  /// What the model REPORTED as seen but not read, across all photos
  /// (T-0011). One report can describe several spines ([UnreadSpineReport]), so
  /// `length` is a lower bound on unread spines and not a count of them. Empty
  /// on every local scan since T-0028 -- see `PhotoAnalysis.unreadable` for
  /// why it is not a count of what was missed either.
  ///
  /// Additive and optional on purpose: `review.json` files written before
  /// this field existed carry no `unreadable` key, and must keep parsing --
  /// absent means "nobody counted", which reads the same as "none found".
  /// Version stays 1 for that reason: nothing about the old shape changed.
  final List<UnreadSpineReport> unreadable;

  /// Photos whose vision call died, in the order they were passed. Each was
  /// already named through `ScanProgress.onWarning` as it died; this is the
  /// same fact as a value, for a reader that has no progress object.
  final List<String> failedPhotos;

  /// Photos a stop kept out of the run entirely -- never sent, so nothing
  /// about them was read, in the order they were passed.
  ///
  /// These two live on the document rather than on `ScanProgress` because the
  /// fact outlives the run: `progress` is optional, an event cannot be asked
  /// for again by a shell that missed it, and both shells read the document at
  /// leisure. [photos] already lists every photo the caller passed, including
  /// the ones no row came from, so naming which of them contributed nothing
  /// and why finishes a fact this class already carries rather than adding a
  /// new kind of one. Until T-0145 the app recovered the split by matching the
  /// orchestrator's warning sentence with `startsWith`, so rewording that
  /// sentence silently turned a stopped photo back into a failed one.
  ///
  /// Additive and optional for the same reason as [unreadable]: a
  /// `review.json` written before they existed carries neither key and must
  /// keep parsing, absent meaning "nobody recorded" -- which reads the same as
  /// "none". Version stays 1; nothing about the old shape changed.
  final List<String> notLookedAtPhotos;

  /// Entries a source made no row out of, in the order they were passed
  /// ([DeclinedEntry], T-0155).
  ///
  /// A value on the document and not only a `ScanProgress.onWarning` line, for
  /// the reason the two lists above it are: the warnings are grouped by reason
  /// so that a folder of 300 non-games does not write 300 lines, and a shell
  /// that wants the names has to have them from somewhere other than the text
  /// of a sentence. Until T-0145 the app recovered exactly this kind of split
  /// with `startsWith` on the orchestrator's wording.
  ///
  /// Additive and optional like [unreadable]: absent means nobody recorded,
  /// which reads the same as none, and the version stays 1.
  final List<DeclinedEntry> declinedEntries;

  /// How many unread-spine reports each photo contributed -- reports, not
  /// spines, since one can describe several ([UnreadSpineReport]). Photos with
  /// none are absent from the map rather than present with a zero.
  Map<String, int> get unreadableByPhoto {
    final counts = <String, int>{};
    for (final spine in unreadable) {
      counts[spine.sourcePhoto] = (counts[spine.sourcePhoto] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'created': created,
        'photos': photos,
        'games': games.map((g) => g.toJson()).toList(),
        'unreadable': unreadable.map((u) => u.toJson()).toList(),
        'failed_photos': failedPhotos,
        'not_looked_at_photos': notLookedAtPhotos,
        // Absent rather than empty on a run that had no source, for the reason
        // on `Detection.toJson`'s `source_entry`: a photo scan writes the file
        // it wrote before this field existed.
        if (declinedEntries.isNotEmpty)
          'declined_entries': [
            for (final entry in declinedEntries) entry.toJson()
          ],
      };

  /// The on-disk form: JSON text in, document out.
  ///
  /// Two failures, deliberately of two different types, because they have two
  /// different fixes: [FormatException] when [source] is not JSON at all, and
  /// [ReviewFormatException] when it is JSON of the wrong shape.
  static ReviewDocument parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw ReviewFormatException(
          '',
          'the top level of the file is ${_foundType(decoded)}; a review '
              'document is an object with "version", "created", "photos" and '
              '"games"');
    }
    return ReviewDocument.fromJson(decoded);
  }

  /// A titleless row is healed on load, not only on the way in from a
  /// provider: documents written before [Detection.hasTitle] existed already
  /// carry one, exactly as T-0014's absent markers did.
  ///
  /// Healing stops there, and T-0050 is where the line is drawn: a titleless
  /// row heals because the information it carried -- a spine was seen here --
  /// survives the move to [unreadable], while a missing `version` or a
  /// `games` that is not a list has no defensible default. Substituting one
  /// would turn a hand-edit mistake into a successful run over a document
  /// nobody wrote, which is the silent failure decision 0012 keeps filing bugs
  /// about. So: heal what is recoverable, name what is not.
  ///
  /// Fields are read in document order so that the message names the first
  /// thing wrong rather than whichever cast happened to run first.
  factory ReviewDocument.fromJson(Map<String, dynamic> json) {
    final version = _shape<int>(json['version'], 'version',
        'the review format version, currently 1');
    final created = _shape<String>(
        json['created'], 'created', 'the ISO timestamp scan wrote');
    final photos = [
      for (final (index, photo) in _shape<List<dynamic>>(json['photos'],
              'photos', 'a list of the photo file names that were scanned')
          .indexed)
        _shape<String>(photo, 'photos[$index]', 'a photo file name'),
    ];
    final unreadable = [
      for (final (index, spine) in (_shapeOrNull<List<dynamic>>(
                  json['unreadable'],
                  'unreadable',
                  'a list of unread-spine reports') ??
              const [])
          .indexed)
        UnreadSpineReport.fromJson(
            _shape<Map<String, dynamic>>(
                spine, 'unreadable[$index]', 'an unread-spine report'),
            path: 'unreadable[$index]'),
    ];
    final failedPhotos = _optionalPhotoNames(json['failed_photos'],
        'failed_photos', 'a list of the photo file names whose read failed');
    final notLookedAtPhotos = _optionalPhotoNames(
        json['not_looked_at_photos'],
        'not_looked_at_photos',
        'a list of the photo file names a stop kept out of the run');
    final declinedEntries = [
      for (final (index, entry) in (_shapeOrNull<List<dynamic>>(
                  json['declined_entries'],
                  'declined_entries',
                  'a list of the files or folders a source skipped') ??
              const [])
          .indexed)
        DeclinedEntry.fromJson(
            _shape<Map<String, dynamic>>(entry, 'declined_entries[$index]',
                'an object with a "name" and a "reason"'),
            path: 'declined_entries[$index]'),
    ];
    final games = <ResolvedGame>[];
    for (final (index, entry) in _shape<List<dynamic>>(json['games'], 'games',
            'a list of game entries, one per row of the review')
        .indexed) {
      final path = 'games[$index]';
      final game = _shape<Map<String, dynamic>>(
          entry, path, 'an object with a "detection"');
      final detection = _shape<Map<String, dynamic>>(game['detection'],
          _at(path, 'detection'), 'an object with a "raw_title"');
      if (Detection.hasTitle(detection)) {
        games.add(ResolvedGame.fromJson(game, path: path));
      } else {
        unreadable.add(UnreadSpineReport.titleless(
          sourcePhoto: _shapeOrNull<String>(detection['source_photo'],
                  '${_at(path, 'detection')}.source_photo',
                  'a photo file name') ??
              '',
        ));
      }
    }
    return ReviewDocument(
      version: version,
      created: created,
      photos: photos,
      games: games,
      unreadable: unreadable,
      failedPhotos: failedPhotos,
      notLookedAtPhotos: notLookedAtPhotos,
      declinedEntries: declinedEntries,
    );
  }
}
