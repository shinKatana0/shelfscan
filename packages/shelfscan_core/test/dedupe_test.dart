/// Guards cross-photo dedupe, orchestrator stage 2 (T-0018).
///
/// The two failure directions are not symmetric. A surviving duplicate is a
/// row the human rejects with one tap; a game wrongly swallowed by a similar
/// one never appears and nobody can notice it. Both are pinned here, and
/// every judgement call goes to the second.
///
/// Several tests assert the OPPOSITE of what T-0018-01 asserted, and say so
/// at the point of the reversal, so the next reader restores neither the old
/// rule nor the old test.
library;

import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1, 2, 3]));

Detection _item(
  String title,
  String photo, {
  String? hint,
  double confidence = 1.0,
}) =>
    Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: confidence,
      sourcePhoto: photo,
      platformHint: hint,
    );

/// Answers with a fixed script per photo; never touches a network.
class ScriptedProvider implements VisionProvider {
  ScriptedProvider(this.answers);

  final Map<String, PhotoAnalysis> answers;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async =>
      answers[photo.name] ?? const PhotoAnalysis();
}

/// [count] throwaway detections attributed to [photo].
///
/// Stage 2 reads photo quality off how many items a photo yielded (T-0027),
/// and that is the only thing these exist to set. Titles are unique per
/// photo, so none of them can merge with anything.
List<Detection> _yieldOf(String photo, int count, {String? hint}) => [
      for (var i = 0; i < count; i++)
        _item('filler $photo $i', photo, hint: hint),
    ];

/// Runs the real pipeline over two photos and returns the deduped titles.
Future<List<String>> _scanTwoPhotos(Detection a, Detection b) async {
  final doc = await Orchestrator(
    visionWorker: VisionWorker(ScriptedProvider({
      'left.jpg': PhotoAnalysis(items: [a]),
      'right.jpg': PhotoAnalysis(items: [b]),
    })),
    resolverWorker: SkipResolver(),
  ).runScan([_photo('left.jpg'), _photo('right.jpg')]);
  return doc.games.map((g) => g.detection.rawTitle).toList();
}

void main() {
  group('the same spine on two photos', () {
    test('formatted differently by the two reads is one row', () async {
      // The four formatting disagreements observed between qwen2.5vl:7b and
      // gemma3:12b on the T-0001 photos -- a trademark sign, an added colon, a
      // `#` and a dropped macron. Every one survived as two rows before
      // T-0018. The spines that carried them are not published; the pairs
      // below are invented and reproduce the four shapes.
      const pairs = <String, String>{
        'MOONLIGHT': 'MOONLIGHT™',
        'Gilt Banner Three Spires': 'Gilt Banner: Three Spires',
        'Lumen Chorus Sessions GB Encore': 'LUMEN CHORUS SESSIONS #GB Encore',
        'EDGE OF THE SŌREN': 'Edge of the Soren',
      };

      for (final pair in pairs.entries) {
        final titles = await _scanTwoPhotos(
          _item(pair.key, 'left.jpg'),
          _item(pair.value, 'right.jpg'),
        );

        expect(titles, [pair.key],
            reason: '"${pair.value}" stayed a second row beside "${pair.key}"');
      }
    });

    test('a Japanese title survives the folding and still dedupes', () async {
      expect(
        await _scanTwoPhotos(
          _item('ホシノカケラ2', 'left.jpg'),
          _item(' ホシノカケラ2 ', 'right.jpg'),
        ),
        ['ホシノカケラ2'],
      );
      expect(
        await _scanTwoPhotos(
          _item('ホシノカケラ2', 'left.jpg'),
          _item('ホシノカケラ3', 'right.jpg'),
        ),
        hasLength(2),
      );
    });
  });

  group('an apostrophe inside a word (T-0062)', () {
    test('the two readings of one spine are one row, in every spelling of '
        'the apostrophe', () async {
      // Measured on a real run under T-0032: qwen2.5vl:7b read the PS5 spine
      // as FALCON'S CREED II, gemma3:12b read the same spine as FALCONS
      // CREED II, and both reached the review document. Folded to a space the
      // possessive is not even a truncation of the plain spelling, so nothing
      // downstream could rescue it.
      for (final apostrophe in const ["'", '’', 'ʼ', '＇']) {
        expect(
          await _scanTwoPhotos(
            _item('FALCON${apostrophe}S CREED II', 'left.jpg'),
            _item('FALCONS CREED II', 'right.jpg'),
          ),
          ['FALCON${apostrophe}S CREED II'],
          reason: 'U+${apostrophe.runes.first.toRadixString(16)} stayed a '
              'second row',
        );
      }
    });

    test('an apostrophe anywhere but inside a word folds as it always did',
        () async {
      // Deleting is only safe because everywhere else the mark stands beside
      // a space or the end of the string, and the punctuation run that
      // replaces it is collapsed to one space and trimmed either way. These
      // all merged before the change and still do.
      const unchanged = <String, String>{
        "'SPLINTER MAN": 'SPLINTER MAN', // title-initial
        "PLAYERS' CHOICE": 'PLAYERS CHOICE', // word-final, before a space
        "SLATE RACER '95": 'SLATE RACER 95', // before a digit run
        "LIVIN'": 'LIVIN', // title-final
        "そらのは 約束の丘 DIRECTOR'S CUT":
            'そらのは 約束の丘 DIRECTORS CUT', // a Japanese head, Latin suffix
      };

      for (final pair in unchanged.entries) {
        expect(
          await _scanTwoPhotos(
            _item(pair.key, 'left.jpg'),
            _item(pair.value, 'right.jpg'),
          ),
          [pair.key],
          reason: '"${pair.value}" stayed a second row beside "${pair.key}"',
        );
      }
    });

    test('an apostrophe standing BETWEEN two words is a duplicate row, and '
        'that is the accepted cost', () async {
      // The one position where deleting and spacing disagree: an elision
      // joins the words it sits between, so the spaced reading of the same
      // spine no longer matches. Both spellings cannot match at once --
      // spacing would break the possessive pair above instead -- and this
      // direction fails into a duplicate row the human taps away rather than
      // into a deleted game (T-0018-02). No spine of the control run is
      // spelled this way.
      expect(
        await _scanTwoPhotos(
          _item("RUSH'N'RIDE RACING", 'left.jpg'),
          _item('RUSH N RIDE RACING', 'right.jpg'),
        ),
        hasLength(2),
      );
      expect(
        await _scanTwoPhotos(
          _item("RUSH'N'RIDE RACING", 'left.jpg'),
          _item('RUSHNRIDE RACING', 'right.jpg'),
        ),
        hasLength(1),
      );
    });

    test('a sequel is still a sequel once the possessive is one word', () {
      // Deleting drops a word from the key, and both dedupe paths count words
      // (isTruncatedRead). The guard has to hold at the new count.
      for (final pair in const [
        ["FALCON'S CREED", "FALCON'S CREED II"],
        ["Titan's Vigil", "Titan's Vigil 2"],
      ]) {
        expect(
          dedupeDetections([
            _item(pair.first, 'left.jpg', hint: 'PS5'),
            _item(pair.last, 'right.jpg', hint: 'PS5'),
          ]),
          hasLength(2),
          reason: '"${pair.last}" was swallowed by "${pair.first}"',
        );
        expect(
          mergeAnalyses(
            PhotoAnalysis(items: [_item(pair.first, 'p.jpg', hint: 'PS5')]),
            PhotoAnalysis(items: [_item(pair.last, 'p.jpg', hint: 'PS5')]),
          ).items,
          hasLength(2),
          reason: 'inside one photo "${pair.last}" was swallowed by '
              '"${pair.first}"',
        );
      }
    });

    test('a title that is nothing but apostrophes is still an empty key', () {
      expect(titleKey("'''"), '');
      expect(titleKey("'"), titleKey(''));
    });
  });

  group('platform hints', () {
    test('a present hint and an absent one stay two rows', () {
      // REVERSED IN T-0018-02 -- PLEASE DO NOT "FIX" THIS BACK.
      // T-0018-01 merged these, treating absent as compatible with anything.
      // "Nothing was read" is not evidence that the platform is the same one;
      // see the SOLAR PILGRIM VII REMAKE INTERBLOOM test for the item that
      // rule deleted.
      final hintFirst = dedupeDetections([
        _item('Duskhollow', 'left.jpg', hint: 'PS4'),
        _item('Duskhollow', 'right.jpg'),
      ]);
      expect(hintFirst, hasLength(2));
      expect(hintFirst.map((d) => d.platformHint), ['PS4', null]);

      final hintSecond = dedupeDetections([
        _item('Duskhollow', 'left.jpg'),
        _item('Duskhollow', 'right.jpg', hint: 'PS4'),
      ]);
      expect(hintSecond, hasLength(2));
      expect(hintSecond.map((d) => d.platformHint), [null, 'PS4']);
    });

    test('SOLAR PILGRIM VII REMAKE INTERBLOOM, read hintless and hinted, '
        'stays two rows', () {
      // The real case: one photograph hinted no row and another hinted every
      // row, and a collector can own one title on two consoles. T-0018-01
      // merged them and dropped the hintless copy; that run only got away with
      // it because the hinted read came back truncated to "PILGRIM VII REMAKE
      // INTERBLOOM". Identical titles here is the case the accident hid.
      final rows = dedupeDetections([
        _item('SOLAR PILGRIM VII REMAKE INTERBLOOM', 'left.jpg'),
        _item('SOLAR PILGRIM VII REMAKE INTERBLOOM', 'right.jpg', hint: 'PS5'),
      ]);

      expect(rows, hasLength(2), reason: 'the hintless copy was deleted');
      expect(rows.map((d) => d.sourcePhoto), ['left.jpg', 'right.jpg']);
    });

    test('two reads that both failed to name a platform are still one row',
        () {
      // Guards the over-correction: no hint at all is the common case (every
      // detection of one control photograph), so if both-absent stopped
      // counting as equal those rows would duplicate themselves across two
      // photos.
      final rows = dedupeDetections([
        _item('Duskhollow', 'left.jpg'),
        _item('DUSKHOLLOW™', 'right.jpg'),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.platformHint, isNull);
    });

    test('two different present hints stay two rows', () {
      // A collector really can own the same game twice.
      final rows = dedupeDetections([
        _item('Nyxia', 'left.jpg', hint: 'PS5'),
        _item('Nyxia', 'right.jpg', hint: 'Switch'),
      ]);

      expect(rows.map((d) => d.platformHint), ['PS5', 'Switch']);
    });

    test('a hint differing only in case or spacing is not a second row', () {
      expect(
        dedupeDetections([
          _item('Nyxia', 'left.jpg', hint: 'PS5'),
          _item('Nyxia', 'right.jpg', hint: ' ps5 '),
        ]),
        hasLength(1),
      );
    });

    test('a hintless read is its own row beside two hinted ones', () {
      // REVERSED IN T-0018-02 -- PLEASE DO NOT "FIX" THIS BACK.
      // T-0018-01 folded this read into the PS5 group, and picked that group
      // only because PS5 came first. That was the tell: with both copies on
      // the shelf the third read is as likely to be either, so the old rule
      // was a coin flip that deleted a row when it lost.
      final rows = dedupeDetections([
        _item('Nyxia', 'a.jpg', hint: 'PS5'),
        _item('Nyxia', 'b.jpg', hint: 'Switch'),
        _item('Nyxia', 'c.jpg'),
      ]);

      expect(rows.map((d) => d.platformHint), ['PS5', 'Switch', null]);
    });

    test('the text "null" written into a hint is an absence, not a platform',
        () {
      // T-0014: qwen2.5vl:7b answers "platform_hint": "null" when it cannot
      // tell, and the pre-T-0018 key interpolated Dart null into that same
      // four-character string and grouped on it.
      Detection fromModel(String photo) => Detection.fromJson({
            'raw_title': 'Duskhollow',
            'platform_hint': 'null',
            'media_type': 'disc',
            'confidence': 1.0,
            'source_photo': photo,
          });

      final bothAbsent =
          dedupeDetections([fromModel('left.jpg'), fromModel('right.jpg')]);
      expect(bothAbsent, hasLength(1));
      expect(bothAbsent.single.platformHint, isNull);

      // T-0018-01 merged this pair; see the reversal note above.
      final againstHint = dedupeDetections([
        _item('Duskhollow', 'left.jpg', hint: 'PS4'),
        fromModel('right.jpg'),
      ]);
      expect(againstHint, hasLength(2));
    });
  });

  group('a spine one photo cut short (T-0024)', () {
    // Scope here is ReadScope.acrossPhotos: only the LAST word may be cut,
    // because the candidate came off a shelf this photo need not show.
    test('a cut inside the last word is one row, keeping the whole title', () {
      final rows = dedupeDetections([
        _item('Frost W', 'left.jpg', hint: 'PS4'),
        _item('FROST WAKE™', 'right.jpg', hint: 'PS4'),
      ]);

      expect(rows.map((d) => d.rawTitle), ['FROST WAKE™'],
          reason: 'the fragment must never be the row the resolver searches');
      expect(rows.single.sourcePhoto, 'right.jpg');
    });

    test('the whole title wins even when the fragment was read first and '
        'scored higher', () {
      // Confidence decides between equal reads only. A cut read is not one:
      // the local model reports 1.0 uniformly (doc/measurements.md), so this
      // is the spread a cloud read would bring.
      final rows = dedupeDetections([
        _item('Frost W', 'left.jpg', hint: 'PS4', confidence: 0.9),
        _item('FROST WAKE™', 'right.jpg', hint: 'PS4', confidence: 0.3),
      ]);

      expect(rows.map((d) => d.rawTitle), ['FROST WAKE™']);
    });

    test('words missing after the cut keep it two rows', () {
      // The asymmetry, from the far side: this pair IS merged inside one
      // photo. Across photos "PATH OF EM" is as plausibly an Ashes this run
      // never read as the Endless Harvest it would be merged into.
      final rows = dedupeDetections([
        _item('PATH OF EM', 'left.jpg', hint: 'PS5'),
        _item('PATH OF EMBER: ENDLESS HARVEST™', 'right.jpg', hint: 'PS5'),
      ]);

      expect(rows, hasLength(2));
    });

    test('a cut that landed on a word boundary is NOT merged', () async {
      // A list, not a map: MOONLIGHT is the left half of two of these. Both
      // halves of both pairs were on a real shelf together, which is what
      // makes the refusal matter rather than being theoretical.
      const kept = <List<String>>[
        ['MOONLIGHT', 'MOONLIGHT 3'],
        ['MOONLIGHT', 'MOONLIGHT + MOONLIGHT 2'],
        [
          'Starweave Chronicles 2',
          'Starweave Chronicles 2: Kaira - The Hidden Country',
        ],
        ['CROWN', 'CROWN OF TIDEFALL'],
      ];

      for (final pair in kept) {
        expect(
          await _scanTwoPhotos(
              _item(pair.first, 'left.jpg'), _item(pair.last, 'right.jpg')),
          hasLength(2),
          reason: '"${pair.first}" and "${pair.last}" were merged',
        );
      }
    });

    test('a number further along the title is not where the cut is', () {
      // The sequel refusal (T-0055) is about the character the fragment stops
      // AT, not about the title carrying a number anywhere: this cut lands in
      // the middle of a word and still merges.
      expect(
        mergeAnalyses(
          PhotoAnalysis(items: [_item('COMICS WEAVER-MAN 2', 'p.jpg')]),
          PhotoAnalysis(items: [_item('COMICS WEAVER-M', 'p.jpg')]),
        ).items,
        hasLength(1),
      );
    });

    test('a short fragment does not merge into an arbitrary longer title', () {
      // Neither of these carries a complete word, and each is a prefix of a
      // great many real games -- the case _wholeWordFloor exists for.
      const tooShort = <String, String>{
        'CHRO': 'CHRONOS 3 REMADE™',
        'COM': 'COMICS WEAVER-MAN 2',
        'THE L': 'THE LAMPS OF ASH PART II',
      };

      for (final pair in tooShort.entries) {
        expect(
          dedupeDetections([
            _item(pair.key, 'left.jpg', hint: 'PS5'),
            _item(pair.value, 'right.jpg', hint: 'PS5'),
          ]),
          hasLength(2),
          reason: '"${pair.key}" merged into "${pair.value}"',
        );
      }
    });

    test('a fragment that fits two titles merges into neither', () {
      final rows = dedupeDetections([
        _item('Mythéon Shadow', 'left.jpg'),
        _item('Mythéon Storm', 'left.jpg'),
        _item('Mythéon S', 'right.jpg'),
      ]);

      expect(rows.map((d) => d.rawTitle),
          ['Mythéon Shadow', 'Mythéon Storm', 'Mythéon S']);
    });

    test('a spine whose HEAD is hidden is two rows, and that is the recorded '
        'decision (T-0054)', () {
      // Measured 2026-08-14 on the five control photos and checked against the
      // 1200x900 frame by eye: a black object standing in front of the shelf
      // covered the FIRST WORD of a two-word head, so the model read only what
      // was left of the spine. The reads below reproduce that shape; the title
      // it happened to is not published.
      expect(
        dedupeDetections([
          _item('SOLAR PILGRIM® VII REMAKE INTERBLOOM', 'right.jpg',
              hint: 'PS5'),
          _item('PILGRIM VII REMAKE INTERBLOOM', 'left.jpg', hint: 'PS5'),
        ]),
        hasLength(2),
      );

      // Refused rather than fixed because the relation that would catch it
      // reaches these, on this same shelf, where the row it deletes is a real
      // game sold on its own. See isTruncatedRead.
      expect(
        dedupeDetections([
          _item('MOONLIGHT + MOONLIGHT 2', 'left.jpg', hint: 'Switch'),
          _item('MOONLIGHT 2', 'right.jpg', hint: 'Switch'),
        ]),
        hasLength(2),
      );
      expect(
        dedupeDetections([
          _item('Starweave Chronicles 2: Kaira - The Hidden Country',
              'left.jpg'),
          _item('Kaira - The Hidden Country', 'right.jpg'),
        ]),
        hasLength(2),
      );

      for (final full in [
        'SOLAR PILGRIM VII RESURGE',
        'SOLAR PILGRIM VII REMAKE',
        'SOLAR PILGRIM® VII REMAKE INTERBLOOM',
      ]) {
        expect(
          dedupeDetections([
            _item(full, 'left.jpg', hint: 'PS5'),
            _item('PILGRIM VII', 'right.jpg', hint: 'PS5'),
          ]),
          hasLength(2),
          reason: '"PILGRIM VII" was swallowed by "$full"',
        );
      }
    });

    test('the hint gate still runs first', () {
      // A cut read is no more evidence about WHICH platform than a whole one,
      // so it cannot reach across two hints that name different ones
      // (T-0018-02). The one disagreement it may reach across since T-0146 is
      // the group below: same platform, described at two legibility levels.
      expect(
        dedupeDetections([
          _item('Frost W', 'left.jpg', hint: 'PS5'),
          _item('FROST WAKE™', 'right.jpg', hint: 'PS4'),
        ]),
        hasLength(2),
      );
    });
  });

  group('one platform read at two legibility levels (T-0146)', () {
    // T-0112 measured gpt-5.5 reading the printed Switch 2 band per spine, so
    // the same case now answers SWITCH 2 off a photo that shows the band and
    // SWITCH off one that does not -- and the photo that cannot see the band
    // is often the one that also cuts the title short.
    //
    // "COLD ARCHIVE req" is a constructed cut, not a measured one. The four
    // truncations T-0112 actually recorded are pinned further down, where the
    // measurement is that they do NOT merge.

    test('a cut SWITCH read joins its full SWITCH 2 twin, and the band '
        'survives the merge', () {
      for (final order in [
        ['a.jpg', 'b.jpg'],
        ['b.jpg', 'a.jpg'],
      ]) {
        final rows = dedupeDetections([
          _item('COLD ARCHIVE requiem', order.first, hint: 'SWITCH 2'),
          _item('COLD ARCHIVE req', order.last, hint: 'SWITCH'),
        ]);

        expect(rows.map((d) => d.rawTitle), ['COLD ARCHIVE requiem']);
        expect(rows.single.platformHint, 'SWITCH 2',
            reason: 'the merged row must keep the hint of the read that '
                'could see the band');
      }
    });

    test('the weaker hint must be on the CUT read, not the whole one', () {
      // The merge always keeps the fuller title, so the other direction would
      // publish SWITCH over a case another photo read as SWITCH 2 -- a wrong
      // platform id on a row the user keeps, against an extra row they tap
      // away. Refusing is the cheap failure.
      expect(
        dedupeDetections([
          _item('COLD ARCHIVE req', 'a.jpg', hint: 'SWITCH 2'),
          _item('COLD ARCHIVE requiem', 'b.jpg', hint: 'SWITCH'),
        ]),
        hasLength(2),
      );
    });

    test('two whole reads of one title still stay two rows', () {
      // T-0018-02, unmoved: only the truncation path crosses a refinement.
      // A collector really can own one title on both consoles, which is the
      // case this pins.
      final rows = dedupeDetections([
        _item('The Legend of Vireo: Ashes of the Kingdom', 'a.jpg',
            hint: 'SWITCH'),
        _item('The Legend of Vireo: Ashes of the Kingdom', 'b.jpg',
            hint: 'SWITCH 2'),
      ]);

      expect(rows, hasLength(2));
      expect(rows.map((d) => d.platformHint), ['SWITCH', 'SWITCH 2']);
    });

    test('the relation is over WORDS, so no one-character platform pair '
        'is touched', () {
      const split = <String, String>{
        'PS': 'PS5',
        'PS4': 'PS5',
        'PS5': 'PS4',
        'NINTENDO': 'SWITCH',
        'SWITCH': 'NINTENDO SWITCH',
        'SWITCH 2': 'SWITCH 3',
      };

      for (final pair in split.entries) {
        expect(
          dedupeDetections([
            _item('FROST WAKE™', 'a.jpg', hint: pair.value),
            _item('Frost W', 'b.jpg', hint: pair.key),
          ]),
          hasLength(2),
          reason: '"${pair.key}" reached across to "${pair.value}"',
        );
      }
    });

    test('nothing in the rule names Switch', () {
      final rows = dedupeDetections([
        _item('VELOX SKYLINE', 'a.jpg', hint: 'XBOX SERIES X'),
        _item('VELOX SKYL', 'b.jpg', hint: 'XBOX'),
      ]);

      expect(rows.map((d) => d.rawTitle), ['VELOX SKYLINE']);
      expect(rows.single.platformHint, 'XBOX SERIES X');
    });

    test('an absent hint is still refined by nothing', () {
      // T-0018-01's reversal is what the null case rests on; a missing hint
      // is not a weaker reading of a present one.
      expect(
        dedupeDetections([
          _item('FROST WAKE™', 'a.jpg', hint: 'PS5'),
          _item('Frost W', 'b.jpg'),
        ]),
        hasLength(2),
      );
      expect(
        dedupeDetections([
          _item('FROST WAKE™', 'a.jpg'),
          _item('Frost W', 'b.jpg', hint: 'PS5'),
        ]),
        hasLength(2),
      );
    });

    test('a fragment that now fits two hints merges into neither', () {
      // The widened candidate list can only make ambiguity MORE likely, and
      // ambiguity refuses (uniqueTruncationMatch).
      final rows = dedupeDetections([
        _item('Mythéon Storm', 'a.jpg', hint: 'SWITCH'),
        _item('Mythéon Shadow', 'b.jpg', hint: 'SWITCH 2'),
        _item('Mythéon S', 'c.jpg', hint: 'SWITCH'),
      ]);

      expect(rows, hasLength(3));
    });

    test('a later exact read finds the group under the hint it ended up with',
        () {
      // The group gates on its surviving row's hint, not on the first hint it
      // saw: once the SWITCH 2 read has taken the row, a third SWITCH 2 read
      // of the same case must join it rather than open a second group.
      final rows = dedupeDetections([
        _item('COLD ARCHIVE req', 'a.jpg', hint: 'SWITCH'),
        _item('COLD ARCHIVE requiem', 'b.jpg', hint: 'SWITCH 2'),
        _item('COLD ARCHIVE requiem', 'c.jpg', hint: 'SWITCH 2'),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.platformHint, 'SWITCH 2');
    });

    test("T-0112's four measured fragments stay two rows, and the hint gate "
        'was never what split them', () {
      // The finding this task ends on. All four cuts land on a WORD boundary,
      // which isTruncatedRead refuses at both scopes by design (T-0024,
      // T-0054) -- the same refusal that keeps MOONLIGHT out of MOONLIGHT 3
      // and Kaira out of Starweave Chronicles 2: Kaira. So these were two
      // rows before the band was read as well as after, whatever the hints
      // say, and the fix above does not reach them.
      const measured = <String, String>{
        'COLD': 'COLD ARCHIVE requiem',
        'The Legend of': 'The Legend of Vireo: Ashes of the Kingdom '
            'Nintendo Switch 2 Edition',
        'SOLAR PILGRIM': 'SOLAR PILGRIM I-VI COLLECTION',
        'WINTER': 'WINTER TIDE SOLAR PILGRIM VII REVERIE',
      };

      for (final pair in measured.entries) {
        for (final hint in ['SWITCH', 'SWITCH 2']) {
          expect(
            dedupeDetections([
              _item(pair.value, 'a.jpg', hint: 'SWITCH 2'),
              _item(pair.key, 'b.jpg', hint: hint),
            ]),
            hasLength(2),
            reason: '"${pair.key}" merged into "${pair.value}" on $hint',
          );
        }
      }
    });

    test('an omitted cutSides asks the plain question', () {
      // What the same-photo caller (mergeAnalyses) relies on being unchanged.
      expect(
        uniqueTruncationMatch('frost w', const ['frost wake'],
            scope: ReadScope.acrossPhotos),
        0,
      );
      expect(
        uniqueTruncationMatch('frost wake', const ['frost w'],
            scope: ReadScope.acrossPhotos),
        0,
      );
      expect(
        uniqueTruncationMatch('frost wake', const ['frost w'],
            scope: ReadScope.acrossPhotos, cutSides: const [CutSide.key]),
        isNull,
      );
    });
  });

  group('what must never be merged', () {
    test('a numbered sequel is a different game', () async {
      const distinct = <String, String>{
        'Starweave Chronicles 2': 'Starweave Chronicles 3',
        'Mythéon Shadow': 'Mythéon Storm',
        'MOONLIGHT': 'MOONLIGHT 3',
      };

      for (final pair in distinct.entries) {
        final titles = await _scanTwoPhotos(
          _item(pair.key, 'left.jpg'),
          _item(pair.value, 'right.jpg'),
        );

        expect(titles, hasLength(2),
            reason: '"${pair.value}" was swallowed by "${pair.key}"');
      }
    });

    test('a sequel number written against the word it follows is still a '
        'sequel (T-0055)', () {
      // One shape, three scripts. Latin spells the marker with a space, so the
      // word-count clauses catch it and T-0054 records MOONLIGHT / MOONLIGHT 3
      // as a duplicate the human taps away; Japanese writes it against the
      // word, so it arrives INSIDE the cut word and reads as a truncation.
      //
      // The そらのは spines all sit on ONE control photo on a PS2 hint, so
      // both dedupe steps can reach the pair, and _wholeWordFloor does not
      // hold it: そらのは is 4 characters and misses the floor by one, while
      // ホシノカケラ is 6 and clears it -- before T-0055 that second pair
      // merged and the sequel row was deleted with no trace in the review
      // list.
      const sequels = <List<String>>[
        ['そらのは 真', 'そらのは 真2'],
        ['そらのは 真', 'そらのは 真3 そらのは3 別伝 Grey Tides'],
        ['ホシノカケラ 真', 'ホシノカケラ 真2'],
        ['ホシノカケラ', 'ホシノカケラ2'],
        // titleKey keeps full-width digits, so a spine typeset this way must
        // read as the same marker.
        ['ホシノカケラ 真', 'ホシノカケラ 真２'],
        ['MOONLIGHT', 'MOONLIGHT 3'],
        ['Starweave Chronicles', 'Starweave Chronicles 2'],
      ];

      for (final pair in sequels) {
        expect(
          dedupeDetections([
            _item(pair.first, 'left.jpg', hint: 'PS2'),
            _item(pair.last, 'right.jpg', hint: 'PS2'),
          ]),
          hasLength(2),
          reason: 'across photos "${pair.last}" was swallowed by '
              '"${pair.first}"',
        );
        expect(
          mergeAnalyses(
            PhotoAnalysis(items: [_item(pair.last, 'p.jpg', hint: 'PS2')]),
            PhotoAnalysis(items: [_item(pair.first, 'p.jpg', hint: 'PS2')]),
          ).items,
          hasLength(2),
          reason: 'inside one photo "${pair.last}" was swallowed by '
              '"${pair.first}"',
        );
      }
    });

    test('a sequel numbered in roman letters is still a sequel (T-0059)', () {
      // The same shape as the digit case above, and the one most likely to be
      // on a shelf in numbered volumes. Every pair here merged before T-0059,
      // deleting a game that was really owned.
      const sequels = <List<String>>[
        ['SOLAR PILGRIM XV', 'SOLAR PILGRIM XVI'],
        ['SOLAR PILGRIM VI', 'SOLAR PILGRIM VII'],
        ['SOLAR PILGRIM VII', 'SOLAR PILGRIM VIII'],
        ['SOLAR PILGRIM X', 'SOLAR PILGRIM XI'],
        ['SOLAR PILGRIM X', 'SOLAR PILGRIM XII'],
        ['SOLAR PILGRIM XI', 'SOLAR PILGRIM XII'],
        ['SOLAR PILGRIM I', 'SOLAR PILGRIM II'],
        ['SOLAR PILGRIM II', 'SOLAR PILGRIM III'],
        // The numeral need not end the title, and the case survives T-0062's
        // apostrophe deletion joining the possessive into one word.
        ["FALCON'S CREED I", "FALCON'S CREED II: LONE ASCENT"],
      ];

      for (final pair in sequels) {
        expect(
          dedupeDetections([
            _item(pair.first, 'left.jpg', hint: 'PS5'),
            _item(pair.last, 'right.jpg', hint: 'PS5'),
          ]),
          hasLength(2),
          reason: 'across photos "${pair.last}" was swallowed by '
              '"${pair.first}"',
        );
        expect(
          mergeAnalyses(
            PhotoAnalysis(items: [_item(pair.last, 'p.jpg', hint: 'PS5')]),
            PhotoAnalysis(items: [_item(pair.first, 'p.jpg', hint: 'PS5')]),
          ).items,
          hasLength(2),
          reason: 'inside one photo "${pair.last}" was swallowed by '
              '"${pair.first}"',
        );
      }
    });

    test('a word that merely ends in roman letters is still a truncation '
        '(T-0059)', () {
      // The first three fragments ARE well-formed numerals -- civ is 104, mi
      // is 1001, div is 504 -- and merge anyway, because what they grow into
      // is not one. Keying on the fragment alone would lose all five of
      // these, and `i v x l c d m` is how a great many English words end.
      // Each carries a leading word only because _wholeWordFloor refuses a
      // one-word fragment outright.
      const cuts = <String, String>{
        'HAL MERIDAS CIV': 'HAL MERIDAS CIVITAS',
        "WANDERER'S CREST MI": "WANDERER'S CREST MINUET",
        'SAM HALLOWS THE DIV': 'SAM HALLOWS THE DIVIDEND',
        'NOVA MAN X': 'NOVA MAN XENITH',
        'VESPER CRYSTA': 'VESPER CRYSTAL',
      };

      for (final pair in cuts.entries) {
        for (final scope in ReadScope.values) {
          expect(
            isTruncatedRead(titleKey(pair.key), titleKey(pair.value),
                scope: scope),
            isTrue,
            reason: '"${pair.key}" stopped merging into "${pair.value}" at '
                '${scope.name}',
          );
        }
        expect(
          dedupeDetections([
            _item(pair.value, 'left.jpg', hint: 'PS5'),
            _item(pair.key, 'right.jpg', hint: 'PS5'),
          ]).map((d) => d.rawTitle),
          [pair.value],
        );
      }
    });

    test('an abbreviation that is accidentally a numeral is the measured cost '
        '(T-0059)', () {
      // Three truncations over the whole title corpus are of this
      // shape: DX is 510 and CD is 400, so a read cut before the last letter
      // is refused and stays a duplicate row. Recorded rather than fixed --
      // the direction of the failure is the cheap one (T-0018-02), and the
      // seventeen refusals it comes with each save a game.
      for (final pair in const [
        ["THE LEGEND OF VIREO WREN'S AWAKENING D",
          "THE LEGEND OF VIREO WREN'S AWAKENING DX"],
        ['TURBOGRAFX 16 PC ENGINE C', 'TURBOGRAFX 16 PC ENGINE CD'],
      ]) {
        expect(
          dedupeDetections([
            _item(pair.last, 'left.jpg', hint: 'Switch'),
            _item(pair.first, 'right.jpg', hint: 'Switch'),
          ]),
          hasLength(2),
        );
      }
    });
  });

  group('the merge itself', () {
    test('keeps first-seen order, so two identical runs diff clean', () {
      final rows = dedupeDetections([
        _item('Moor', 'a.jpg'),
        _item('Nyxia', 'a.jpg'),
        _item('MOOR', 'b.jpg'),
        _item('Vex', 'b.jpg'),
      ]);

      expect(rows.map((d) => d.rawTitle), ['Moor', 'Nyxia', 'Vex']);
    });

    test('keeps the higher-confidence read when the photos are equally good',
        () {
      // The local model reports 1.0 uniformly (doc/measurements.md), so this
      // only decides anything for a cloud read with a real spread. Both photos
      // yield one item, so T-0027's quality signal ties and confidence is
      // reached.
      final rows = dedupeDetections([
        _item('Vex', 'a.jpg', confidence: 0.4),
        _item('VEX', 'b.jpg', confidence: 0.9),
      ]);

      expect(rows.single.confidence, 0.9);
      expect(rows.single.sourcePhoto, 'b.jpg');
    });

    test('does not weigh a hint against confidence, having never grouped '
        'the two together', () {
      // REVERSED IN T-0018-02 -- PLEASE DO NOT "FIX" THIS BACK.
      // T-0018-01 merged these and let the PS2 row win on its hint despite
      // the lower confidence. Hinted and hintless reads no longer group at
      // all, so both survive and confidence is never consulted.
      final rows = dedupeDetections([
        _item('Vex', 'a.jpg', confidence: 0.9),
        _item('Vex', 'b.jpg', hint: 'PS2', confidence: 0.4),
      ]);

      expect(rows, hasLength(2));
      expect(rows.map((d) => d.platformHint), [null, 'PS2']);
    });

    test('nothing in, nothing out', () {
      expect(dedupeDetections([]), isEmpty);
    });
  });

  group('which read of a merged spine becomes the row (T-0027)', () {
    // A shelf photographed twice at different quality must still yield one
    // correct list, and the quality signal is the yield: a full-resolution
    // read finds more of a shelf than a downscaled one (decision 0005), and
    // the downscaled read is the one that glues a trademark sign to a title.
    // Every number here is invented like the titles beside it -- two yields
    // far enough apart to put one photo clearly ahead, of no measured size.
    const sharp = 'shelf-3.jpg';
    const blurred = 'lowres-2.jpg';
    const sharpYield = 12;
    const blurredYield = 3;

    List<Detection> pair(List<Detection> order) => dedupeDetections([
          ...order,
          ..._yieldOf(sharp, sharpYield, hint: 'PS5'),
          ..._yieldOf(blurred, blurredYield, hint: 'PS5'),
        ]);

    test('the read off the photo that saw more of the shelf wins', () {
      for (final order in [
        [
          _item('CHRONOS 3 REMADE', sharp, hint: 'PS5'),
          _item('CHRONOS 3 REMADE™', blurred, hint: 'PS5'),
        ],
        // Reversed, because before T-0027 this order alone decided it: with
        // every confidence at 1.0 the survivor was whichever photo the caller
        // listed first, and a user has no reason to list the good one first.
        [
          _item('CHRONOS 3 REMADE™', blurred, hint: 'PS5'),
          _item('CHRONOS 3 REMADE', sharp, hint: 'PS5'),
        ],
      ]) {
        final rows = pair(order);
        final merged =
            rows.where((d) => titleKey(d.rawTitle) == 'chronos 3 remade');

        expect(merged.single.sourcePhoto, sharp,
            reason: 'the small photo won for photo order '
                '${order.map((d) => d.sourcePhoto).toList()}');
      }
    });

    test('confidence cannot outvote photo quality', () {
      // The signal must not be confidence (T-0027): the local model pins it
      // at 1.0 for every read, including partial ones, so a provider that
      // reports a real spread must still not overrule the better photo.
      final rows = pair([
        _item('PATH OF EMBER: ENDLESS HARVEST™', blurred,
            hint: 'PS5', confidence: 1.0),
        _item('PATH OF EMBER: ENDLESS HARVEST', sharp,
            hint: 'PS5', confidence: 0.2),
      ]);

      expect(
        rows.singleWhere((d) => d.rawTitle.startsWith('PATH OF EMBER')).rawTitle,
        'PATH OF EMBER: ENDLESS HARVEST',
      );
    });

    test('equal confidence on equally good photos still resolves, and to the '
        'same row every run', () {
      // Determinism is the property, not the winner: two runs of one photo set
      // must write the same review file, so a tie keeps the row already held.
      List<Detection> tied() => dedupeDetections([
            _item('CROWN OF TIDEFALL', 'a.jpg', hint: 'PS5', confidence: 1.0),
            _item('Crown of Tidefall', 'b.jpg', hint: 'PS5', confidence: 1.0),
          ]);

      expect(tied(), hasLength(1));
      expect(tied().single.rawTitle, 'CROWN OF TIDEFALL');
      expect(tied().single.rawTitle, tied().single.rawTitle);
    });

    test('a cut-short read never wins on photo quality', () {
      // Completeness stays ahead of the new signal. Here the fragment comes
      // off the BETTER photo, which is the only arrangement that can tell the
      // two rules apart -- the review list and the IGDB search still want the
      // whole title (T-0024).
      final rows = dedupeDetections([
        _item('Frost W', sharp, hint: 'PS4'),
        _item('FROST WAKE™', blurred, hint: 'PS4'),
        ..._yieldOf(sharp, sharpYield, hint: 'PS4'),
        ..._yieldOf(blurred, blurredYield, hint: 'PS4'),
      ]);

      expect(rows.where((d) => d.rawTitle.toLowerCase().startsWith('frost')),
          hasLength(1));
      expect(
        rows.singleWhere((d) => d.rawTitle.toLowerCase().startsWith('frost'))
            .rawTitle,
        'FROST WAKE™',
      );
    });

    test('a photo good enough to read the whole shelf still merges nothing it '
        'should not', () {
      // T-0018-02's pair, with the quality gap added: a survivor rule may only
      // pick between reads already agreed to be one spine, never widen what
      // merges. Both halves were on a real shelf together.
      final rows = dedupeDetections([
        _item('Starweave Chronicles 2', blurred),
        _item('Starweave Chronicles 2: Kaira - The Hidden Country', sharp),
        ..._yieldOf(sharp, sharpYield),
        ..._yieldOf(blurred, blurredYield),
      ]);

      expect(
        rows.where((d) => d.rawTitle.startsWith('Starweave')).map((d) =>
            d.rawTitle),
        [
          'Starweave Chronicles 2',
          'Starweave Chronicles 2: Kaira - The Hidden Country',
        ],
      );
    });
  });

  group('one key, two callers', () {
    test('the two scopes differ in exactly one thing, and on purpose', () {
      // The whole of T-0024's asymmetry, pinned in one assertion so that
      // "they disagree" can never again be read as a bug. Within one photo
      // both reads cover the same spines; across photos the candidate came
      // off a shelf the fragment's photo need not show. See ReadScope.
      const fragment = 'PATH OF EM';
      const full = 'PATH OF EMBER: ENDLESS HARVEST™';

      expect(
        mergeAnalyses(
          PhotoAnalysis(items: [_item(full, 'p.jpg')]),
          PhotoAnalysis(items: [_item(fragment, 'p.jpg')]),
        ).items,
        hasLength(1),
        reason: 'inside one photo the cut must merge',
      );
      expect(
        dedupeDetections([
          _item(full, 'left.jpg'),
          _item(fragment, 'right.jpg'),
        ]),
        hasLength(2),
        reason: 'across photos the same cut must NOT merge',
      );

      // A cut inside the last word is the case both scopes accept.
      expect(
        mergeAnalyses(
          PhotoAnalysis(items: [_item('FROST WAKE™', 'p.jpg')]),
          PhotoAnalysis(items: [_item('Frost W', 'p.jpg')]),
        ).items,
        hasLength(1),
      );
      expect(
        dedupeDetections([
          _item('FROST WAKE™', 'left.jpg'),
          _item('Frost W', 'right.jpg'),
        ]),
        hasLength(1),
      );
    });

    test('the vision merge and stage 2 answer identically', () {
      // Equal keys and unrelated titles are answered the same by both, and
      // must stay that way: the scopes differ only over truncation, above.
      // If these two ever disagree here, one of the dedupe steps has grown a
      // second key implementation.
      const pairs = <String, String>{
        'MOONLIGHT': 'MOONLIGHT™',
        'Gilt Banner Three Spires': 'Gilt Banner: Three Spires',
        'EDGE OF THE SŌREN': 'Edge of the Soren',
        'Starweave Chronicles 2': 'Starweave Chronicles 3',
        'Mythéon Shadow': 'Mythéon Storm',
      };

      for (final pair in pairs.entries) {
        final sameKey = titleKey(pair.key) == titleKey(pair.value);

        final mergedOnOnePhoto = mergeAnalyses(
          PhotoAnalysis(items: [_item(pair.key, 'p.jpg')]),
          PhotoAnalysis(items: [_item(pair.value, 'p.jpg')]),
        ).items.length;
        final mergedAcrossPhotos = dedupeDetections([
          _item(pair.key, 'left.jpg'),
          _item(pair.value, 'right.jpg'),
        ]).length;

        expect(mergedOnOnePhoto, mergedAcrossPhotos,
            reason: '"${pair.key}" / "${pair.value}" is deduped differently '
                'on one photo than across two');
        expect(mergedAcrossPhotos, sameKey ? 1 : 2);
      }
    });
  });
}
