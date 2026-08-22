/// Guards the second-reader path (T-0011, made unconditional by T-0032).
///
/// The expensive failure modes this pins down, in order of how much they
/// would cost if they regressed:
///   1. a run with no second reader configured must issue exactly the calls
///      it issued before the feature existed -- the feature is opt-in, and
///      "opt-in" is worth nothing if the off state still costs something;
///   2. the cloud must be unreachable from a local-only configuration
///      (decision 0011: cloud is an explicit opt-in, per run, by the human);
///   3. the cost is exactly one extra call per photo -- not two, and not a
///      number that depends on what the primary said about itself.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show FallbackConfigError, fallbackProviderFor, openAiProviderFor;

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1, 2, 3]));

Detection _item(String title, String photo, {String? hint}) => Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: photo,
      platformHint: hint,
    );

UnreadSpineReport _unread(String photo,
        {SpineScript script = SpineScript.japanese}) =>
    UnreadSpineReport(sourcePhoto: photo, script: script, reason: 'cannot read');

/// Counts calls and answers from a per-photo script.
class CountingProvider implements VisionProvider {
  CountingProvider(this.answers);

  /// Photo name -> what this provider claims to see on it.
  final Map<String, PhotoAnalysis> answers;
  final List<String> calls = [];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    calls.add(photo.name);
    return answers[photo.name] ?? const PhotoAnalysis();
  }
}

/// Fails the moment anything reaches the cloud.
class ForbiddenCloudProvider implements VisionProvider {
  var calls = 0;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    calls += 1;
    throw StateError('cloud provider reached without an opt-in');
  }
}

class ThrowingProvider implements VisionProvider {
  var calls = 0;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    calls += 1;
    throw Exception('fallback backend is down');
  }
}

void main() {
  group('no second reader configured', () {
    test('costs exactly one provider call per photo, as before', () async {
      final primary = CountingProvider({
        'a.jpg': PhotoAnalysis(
          items: [_item('Duskhollow', 'a.jpg')],
          unreadable: [_unread('a.jpg'), _unread('a.jpg')],
        ),
        'b.jpg': PhotoAnalysis(items: [_item('Moor', 'b.jpg')]),
      });

      final doc = await Orchestrator(
        visionWorker: VisionWorker(primary),
        resolverWorker: SkipResolver(),
      ).runScan([_photo('a.jpg'), _photo('b.jpg')]);

      // Two photos, two calls -- even though a.jpg reported unread spines.
      expect(primary.calls, ['a.jpg', 'b.jpg']);
      expect(doc.games.map((g) => g.detection.rawTitle),
          containsAll(<String>['Duskhollow', 'Moor']));
      // The count is still reported; only the second read is withheld.
      expect(doc.unreadable, hasLength(2));
    });

    test('a photo the primary read nothing on still costs one call', () async {
      // The state T-0032 turns on: nothing read, nothing reported unread.
      // Off, that must still buy no second call.
      final primary = CountingProvider({'a.jpg': const PhotoAnalysis()});

      final result = await VisionWorker(primary).run(_photo('a.jpg'));

      expect(primary.calls, ['a.jpg']);
      expect(result.items, isEmpty);
    });
  });

  group('with a second reader configured', () {
    late CountingProvider primary;
    late CountingProvider second;

    setUp(() {
      primary = CountingProvider({
        'jp.jpg': PhotoAnalysis(
          items: [_item('Vex', 'jp.jpg')],
          unreadable: [_unread('jp.jpg'), _unread('jp.jpg')],
        ),
        'latin.jpg': PhotoAnalysis(items: [_item('Moor', 'latin.jpg')]),
      });
      second = CountingProvider({
        'jp.jpg': PhotoAnalysis(items: [
          _item('Vex', 'jp.jpg'), // already read by the primary
          _item('ホシノミチビキXI', 'jp.jpg'),
        ]),
        'latin.jpg': PhotoAnalysis(items: [_item('Arca', 'latin.jpg')]),
      });
    });

    test('re-reads the photo exactly once', () async {
      await VisionWorker(primary, secondReader: second).run(_photo('jp.jpg'));

      expect(primary.calls, ['jp.jpg']);
      expect(second.calls, ['jp.jpg'], reason: 'exactly one extra call');
    });

    test('re-reads a photo the primary reported nothing unread on', () async {
      // The whole of T-0032: the primary saying nothing about its own misses
      // is the normal local answer, not evidence that it missed nothing, so
      // it can no longer decide which photos are worth a second call.
      final result = await VisionWorker(primary, secondReader: second)
          .run(_photo('latin.jpg'));

      expect(second.calls, ['latin.jpg']);
      expect(result.items.map((d) => d.rawTitle), ['Moor', 'Arca']);
    });

    test('re-reads a photo the primary read NOTHING on', () async {
      // 0 items and 0 unreadable is what the local model returns for a stack
      // it cannot read at all -- the case the feature exists for, and the one
      // the old trigger was blindest to.
      final blind = CountingProvider({'jp.jpg': const PhotoAnalysis()});

      final result =
          await VisionWorker(blind, secondReader: second).run(_photo('jp.jpg'));

      expect(second.calls, ['jp.jpg']);
      expect(result.items.map((d) => d.rawTitle), ['Vex', 'ホシノミチビキXI']);
    });

    test('merges without duplicating a title both models read', () async {
      final result =
          await VisionWorker(primary, secondReader: second).run(_photo('jp.jpg'));

      expect(result.items.map((d) => d.rawTitle),
          ['Vex', 'ホシノミチビキXI']);
    });

    test('the same title in different case or spacing is still one item',
        () async {
      final loose = CountingProvider({
        'jp.jpg': PhotoAnalysis(items: [_item('  VEX   II ', 'jp.jpg')]),
      });
      final result = await VisionWorker(
        CountingProvider({
          'jp.jpg': PhotoAnalysis(items: [_item('Vex II', 'jp.jpg')]),
        }),
        secondReader: loose,
      ).run(_photo('jp.jpg'));

      expect(result.items, hasLength(1));
      expect(result.items.single.rawTitle, 'Vex II',
          reason: 'the primary read wins; the re-read only adds');
    });

    test('the same spine formatted differently by the two models is one item',
        () async {
      // Every pair here is a real duplicate observed on the two T-0001
      // photos with qwen2.5vl:7b as primary and gemma3:12b as fallback.
      // They are the reason the merge key ignores punctuation and
      // diacritics rather than only case and spacing.
      const pairs = <String, String>{
        'MOONLIGHT': 'MOONLIGHT™',
        'MOONLIGHT + MOONLIGHT 2': 'MOONLIGHT™ + MOONLIGHT™ 2',
        'Gilt Banner Three Spires': 'Gilt Banner: Three Spires',
        'Lumen Chorus Sessions GB Encore':
            'LUMEN CHORUS SESSIONS #GB Encore',
        'Starweave Chronicles Definitive Edition':
            'Starweave Chronicles™: Definitive Edition',
        'Starweave Chronicles 2: Kaira - The Hidden Country':
            'Starweave Chronicles™ 2: Kaira - The Hidden Country',
        'CHRONOS 3 REMADE™': 'CHRONOS 3 REMADE',
        'EDGE OF THE SŌREN': 'Edge of the Soren',
        'Mythéon Legends Aurion': 'Mythéon Legends: Aurion',
        'PILGRIM VII REMAKE INTERBLOOM': 'PILGRIM® VII REMAKE INTERBLOOM',
      };

      for (final pair in pairs.entries) {
        final merged = mergeAnalyses(
          PhotoAnalysis(
            items: [_item(pair.key, 'p.jpg')],
            unreadable: [_unread('p.jpg')],
          ),
          PhotoAnalysis(items: [_item(pair.value, 'p.jpg')]),
        );

        expect(merged.items.map((d) => d.rawTitle), [pair.key],
            reason: '"${pair.value}" duplicated "${pair.key}"');
      }
    });

    test('a genuinely different title is still kept', () {
      // The other half of the same knob: normalization that swallowed
      // these would hide real items behind the ones already read.
      const distinct = <String, String>{
        'Mythéon Shadow': 'Mythéon Storm',
        'Starweave Chronicles 2': 'Starweave Chronicles 3',
        'HARBOUR STARBURST': 'HARBOUR STARBURT',
        'MOONLIGHT': 'MOONLIGHT 3',
      };

      for (final pair in distinct.entries) {
        final merged = mergeAnalyses(
          PhotoAnalysis(items: [_item(pair.key, 'p.jpg')]),
          PhotoAnalysis(items: [_item(pair.value, 'p.jpg')]),
        );

        expect(merged.items.map((d) => d.rawTitle), [pair.key, pair.value],
            reason: '"${pair.value}" was swallowed by "${pair.key}"');
      }
    });

    group('a spine one model cut short (T-0024)', () {
      // Scope here is ReadScope.samePhoto: both reads cover the same spines,
      // so a cut may be missing trailing words as well as part of one.
      test('the fallback cutting a spine the primary read whole is one item',
          () {
        final merged = mergeAnalyses(
          PhotoAnalysis(items: [_item('PATH OF EMBER: ENDLESS HARVEST™', 'p.jpg')]),
          PhotoAnalysis(items: [_item('PATH OF EM', 'p.jpg')]),
        );

        expect(merged.items.map((d) => d.rawTitle),
            ['PATH OF EMBER: ENDLESS HARVEST™']);
      });

      test('the primary cutting it instead gives the row the WHOLE title', () {
        // The one place a re-read rewrites a primary row rather than adding
        // one: leaving "PATH OF EM" would send that to IGDB. The row must not
        // move, so an item on each side of it pins the position.
        final merged = mergeAnalyses(
          PhotoAnalysis(items: [
            _item('DEEP SENTINEL', 'p.jpg'),
            _item('PATH OF EM', 'p.jpg'),
            _item('SOLAR PILGRIM XVI', 'p.jpg'),
          ]),
          PhotoAnalysis(items: [
            _item('PATH OF EMBER: ENDLESS HARVEST™', 'p.jpg'),
          ]),
        );

        expect(merged.items.map((d) => d.rawTitle), [
          'DEEP SENTINEL',
          'PATH OF EMBER: ENDLESS HARVEST™',
          'SOLAR PILGRIM XVI',
        ]);
      });

      test('every recorded cut that carries a whole word merges', () {
        // Left column: strings qwen2.5vl:7b actually returned for a clipped
        // spine under T-0003 strips. Right: what the same photo reads today.
        const cuts = <String, String>{
          'PATH OF EM': 'PATH OF EMBER: ENDLESS HARVEST™',
          'Frost W': 'FROST WAKE™',
          'MOONLIGHT ORIGINS: SELENE AND THE LOST EMB':
              'MOONLIGHT ORIGINS: SELENE AND THE LOST EMBER',
        };

        for (final cut in cuts.entries) {
          expect(
            mergeAnalyses(
              PhotoAnalysis(items: [_item(cut.value, 'p.jpg')]),
              PhotoAnalysis(items: [_item(cut.key, 'p.jpg')]),
            ).items.map((d) => d.rawTitle),
            [cut.value],
            reason: '"${cut.key}" stayed a second row beside "${cut.value}"',
          );
        }
      });

      test('a cut that landed on a word boundary is NOT merged', () {
        // The decision recorded on isTruncatedRead: editions and sequels are
        // exactly the whole-word case, and both halves of these pairs occur
        // together on a real shelf. MOONLIGHT really was a glare-occluded Moonlight 3 in
        // the T-0007 baseline, and it still leaks its duplicate row here --
        // deliberately, because it is indistinguishable from a real
        // Moonlight 1 case (T-0018-02: a lost item beats a duplicated one).
        const kept = <String, String>{
          'MOONLIGHT': 'MOONLIGHT 3',
          'Starweave Chronicles 2':
              'Starweave Chronicles 2: Kaira - The Hidden Country',
          'CROWN': 'CROWN OF TIDEFALL',
          'Starweave Chronicles Definitive Edition':
              'Starweave Chronicles X Definitive Edition',
        };

        for (final pair in kept.entries) {
          expect(
            mergeAnalyses(
              PhotoAnalysis(items: [_item(pair.key, 'p.jpg')]),
              PhotoAnalysis(items: [_item(pair.value, 'p.jpg')]),
            ).items,
            hasLength(2),
            reason: '"${pair.key}" swallowed or was swallowed by '
                '"${pair.value}"',
          );
        }
      });

      test('a fragment with no whole word of its own is below the floor', () {
        const tooShort = <String, String>{
          'CHRO': 'CHRONOS 3 REMADE™',
          'COM': 'COMICS WEAVER-MAN 2',
          'THE L': 'THE LAMPS OF ASH PART II',
        };

        for (final pair in tooShort.entries) {
          expect(
            mergeAnalyses(
              PhotoAnalysis(items: [_item(pair.value, 'p.jpg')]),
              PhotoAnalysis(items: [_item(pair.key, 'p.jpg')]),
            ).items,
            hasLength(2),
            reason: '"${pair.key}" merged into "${pair.value}"',
          );
        }
      });

      test('a fragment that fits two titles merges into neither', () {
        // Both are on the control set, and "Mythéon S" is as much
        // one as the other. Merging on first-come would delete whichever
        // lost the coin flip, so the fragment stays its own row.
        final merged = mergeAnalyses(
          PhotoAnalysis(items: [
            _item('Mythéon Shadow', 'p.jpg'),
            _item('Mythéon Storm', 'p.jpg'),
          ]),
          PhotoAnalysis(items: [_item('Mythéon S', 'p.jpg')]),
        );

        expect(merged.items.map((d) => d.rawTitle),
            ['Mythéon Shadow', 'Mythéon Storm', 'Mythéon S']);
      });
    });

    test('a Japanese title read twice is one item', () async {
      // The script this whole task exists for must survive the key: the
      // punctuation strip must not eat kana or kanji.
      final merged = mergeAnalyses(
        PhotoAnalysis(items: [_item('ホシノカケラ2', 'p.jpg')]),
        PhotoAnalysis(items: [_item(' ホシノカケラ2 ', 'p.jpg')]),
      );

      expect(merged.items, hasLength(1));
      expect(
        mergeAnalyses(
          PhotoAnalysis(items: [_item('ホシノカケラ2', 'p.jpg')]),
          PhotoAnalysis(items: [_item('ホシノカケラ3', 'p.jpg')]),
        ).items,
        hasLength(2),
      );
    });

    test('a platform hint disagreement does not split one game in two',
        () async {
      final result = await VisionWorker(
        CountingProvider({
          'p.jpg': PhotoAnalysis(items: [_item('Vex', 'p.jpg', hint: 'PS2')]),
        }),
        secondReader: CountingProvider({
          'p.jpg': PhotoAnalysis(items: [_item('Vex', 'p.jpg', hint: 'PS3')]),
        }),
      ).run(_photo('p.jpg'));

      expect(result.items, hasLength(1));
      expect(result.items.single.platformHint, 'PS2');
    });

    test('a spine the second reader managed to read stops being unreadable',
        () async {
      final result = await VisionWorker(
        CountingProvider({
          'jp.jpg': PhotoAnalysis(
            items: const [],
            unreadable: [_unread('jp.jpg'), _unread('jp.jpg')],
          ),
        }),
        secondReader: CountingProvider({
          'jp.jpg': PhotoAnalysis(
            items: [_item('そらのは', 'jp.jpg')],
            unreadable: [_unread('jp.jpg')],
          ),
        }),
      ).run(_photo('jp.jpg'));

      expect(result.items, hasLength(1));
      expect(result.unreadable, hasLength(1),
          reason: 'the second reader has the final say on what is unread');
    });

    test('a failing second reader costs the primary result nothing', () async {
      final broken = ThrowingProvider();

      final result = await VisionWorker(primary, secondReader: broken)
          .run(_photo('jp.jpg'));

      expect(broken.calls, 1);
      expect(result.items.map((d) => d.rawTitle), ['Vex']);
      expect(result.unreadable, hasLength(2),
          reason: 'nothing was re-read, so nothing became readable');
    });

    test('the whole scan costs one extra call per photo, no more', () async {
      final doc = await Orchestrator(
        visionWorker: VisionWorker(primary, secondReader: second),
        resolverWorker: SkipResolver(),
      ).runScan([_photo('jp.jpg'), _photo('latin.jpg')]);

      expect(primary.calls, hasLength(2));
      expect(second.calls, hasLength(2));
      expect(second.calls.toSet(), {'jp.jpg', 'latin.jpg'});
      // "Arca" is the price of the decision: a second model's mistakes now
      // reach the review list on every photo, not only on the photos the
      // primary confessed to. Review is where they are thrown out
      // (decision 0007), and a missed item cannot be thrown out at all.
      expect(
        doc.games.map((g) => g.detection.rawTitle).toSet(),
        {'Vex', 'ホシノミチビキXI', 'Moor', 'Arca'},
      );
      // The primary's two entries are gone because the second reader, having
      // re-read that photo, reported none.
      expect(doc.unreadable, isEmpty);
    });
  });

  group('unreadable spines in the review document', () {
    test('are counted per photo and never enter games', () async {
      final doc = await Orchestrator(
        visionWorker: VisionWorker(CountingProvider({
          'a.jpg': PhotoAnalysis(
            items: [_item('Moor', 'a.jpg')],
            unreadable: [
              _unread('a.jpg'),
              _unread('a.jpg', script: SpineScript.unknown),
            ],
          ),
          'b.jpg': PhotoAnalysis(items: [_item('Arca', 'b.jpg')]),
        })),
        resolverWorker: SkipResolver(),
      ).runScan([_photo('a.jpg'), _photo('b.jpg')]);

      expect(doc.games, hasLength(2));
      expect(doc.unreadableByPhoto, {'a.jpg': 2});
      expect(doc.unreadable.map((u) => u.script),
          [SpineScript.japanese, SpineScript.unknown]);
    });
  });

  group('review.json compatibility', () {
    /// Exactly the shape `scan` wrote before T-0011: no `unreadable` key.
    final legacy = <String, dynamic>{
      'version': 1,
      'created': '2026-08-13T17:25:31.019438Z',
      'photos': ['shelf_a.jpg'],
      'games': [
        {
          'detection': {
            'raw_title': 'COBALT CHIME',
            'platform_hint': null,
            'media_type': 'cartridge',
            'confidence': 1.0,
            'source_photo': 'shelf_a.jpg',
            'notes': null,
          },
          'best': null,
          'candidates': <dynamic>[],
          'status': 'approved',
        },
      ],
    };

    test('a document written before the field existed still parses', () {
      final doc = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>);

      expect(doc.unreadable, isEmpty);
      expect(doc.unreadableByPhoto, isEmpty);
      // Nothing else about it changed, including the human's approval.
      expect(doc.games.single.detection.rawTitle, 'COBALT CHIME');
      expect(doc.games.single.status, ReviewStatus.approved);
      expect(doc.version, 1, reason: 'an additive field is not a new format');
    });

    test('the field round-trips through the document', () {
      final original = ReviewDocument(
        version: 1,
        created: '2026-08-13T17:25:31.019438Z',
        photos: const ['shelf_a.jpg'],
        games: const [],
        unreadable: [
          UnreadSpineReport(
            sourcePhoto: 'shelf_a.jpg',
            script: SpineScript.japanese,
            reason: 'kanji too small',
          ),
          UnreadSpineReport(sourcePhoto: 'shelf_b.jpg'),
        ],
      );

      final once = original.toJson();
      final reparsed = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(once)) as Map<String, dynamic>);

      expect(reparsed.unreadable.map((u) => u.sourcePhoto),
          ['shelf_a.jpg', 'shelf_b.jpg']);
      expect(reparsed.unreadable.first.script, SpineScript.japanese);
      expect(reparsed.unreadable.first.reason, 'kanji too small');
      expect(reparsed.unreadable.last.script, SpineScript.unknown);
      expect(reparsed.unreadable.last.reason, isNull);
      // A second pass changes nothing.
      expect(reparsed.toJson(), once);
    });
  });

  group('CLI fallback selection', () {
    // The environment is passed in rather than read, so these are real
    // assertions about the policy and not about the host they run on.
    const noEnv = <String, String>{};
    const cloudKeyOnly = {'ANTHROPIC_API_KEY': 'sk-ant-x'};
    const openAiEnv = {
      'SHELFSCAN_OPENAI_BASE_URL': 'https://api.groq.com/openai/v1',
      'SHELFSCAN_OPENAI_MODEL': 'llama-4-scout',
      'SHELFSCAN_OPENAI_API_KEY': 'gsk-x',
    };

    test('absent flag and absent env variable -> no fallback at all', () {
      expect(fallbackProviderFor(null, noEnv), isNull);
      // Even with a cloud key sitting in the environment.
      expect(fallbackProviderFor(null, cloudKeyOnly), isNull);
    });

    test('the env variable alone selects a bigger LOCAL model', () {
      final provider = fallbackProviderFor(null, {
        ...cloudKeyOnly,
        'SHELFSCAN_OLLAMA_FALLBACK_MODEL': 'gemma3:12b',
        'SHELFSCAN_OLLAMA_URL': 'http://localhost:11434',
      });

      expect(provider, isA<OllamaVisionProvider>());
      expect((provider as OllamaVisionProvider).model, 'gemma3:12b');
      expect(provider.baseUrl, 'http://localhost:11434');
    });

    test('a local-only configuration can never reach the cloud', () {
      // The load-bearing test for the BYOK/opt-in decision: a key in the
      // environment plus a local fallback must stay entirely local.
      for (final flag in <String?>[null, 'ollama', 'none']) {
        final provider = fallbackProviderFor(flag, {
          ...cloudKeyOnly,
          ...openAiEnv,
          'SHELFSCAN_OLLAMA_FALLBACK_MODEL': 'gemma3:12b',
        });
        expect(provider, isNot(isA<AnthropicVisionProvider>()),
            reason: 'flag "$flag" reached the cloud');
        expect(provider, isNot(isA<OpenAiCompatibleVisionProvider>()),
            reason: 'flag "$flag" reached an external endpoint');
      }
    });

    test('the cloud takes the explicit flag, and the key with it', () {
      expect(fallbackProviderFor('anthropic', cloudKeyOnly),
          isA<AnthropicVisionProvider>());
      expect(() => fallbackProviderFor('anthropic', noEnv),
          throwsA(isA<FallbackConfigError>()));
    });

    test('--fallback none turns the env variable off', () {
      expect(
        fallbackProviderFor(
            'none', {'SHELFSCAN_OLLAMA_FALLBACK_MODEL': 'gemma3:12b'}),
        isNull,
      );
    });

    test('--fallback ollama without a model named is an error, not a '
        'pointless re-read of the same model', () {
      expect(() => fallbackProviderFor('ollama', noEnv),
          throwsA(isA<FallbackConfigError>()));
    });

    test('an unknown fallback name is rejected', () {
      expect(() => fallbackProviderFor('gemini', noEnv),
          throwsA(isA<FallbackConfigError>()));
    });

    test('an external endpoint takes the explicit flag, and its three '
        'variables with it', () {
      final provider = fallbackProviderFor('openai', openAiEnv)
          as OpenAiCompatibleVisionProvider;

      expect(provider.baseUrl, 'https://api.groq.com/openai/v1');
      expect(provider.model, 'llama-4-scout');
      expect(() => fallbackProviderFor('openai', noEnv),
          throwsA(isA<FallbackConfigError>()));
    });
  });

  group('CLI openai provider configuration (T-0006)', () {
    const full = {
      'SHELFSCAN_OPENAI_BASE_URL': 'https://openrouter.ai/api/v1',
      'SHELFSCAN_OPENAI_MODEL': 'qwen/qwen2.5-vl-72b-instruct',
      'SHELFSCAN_OPENAI_API_KEY': 'sk-or-x',
    };

    test('all three variables build the provider', () {
      final provider = openAiProviderFor(full);

      expect(provider.baseUrl, 'https://openrouter.ai/api/v1');
      expect(provider.model, 'qwen/qwen2.5-vl-72b-instruct');
      expect(provider.apiKey, 'sk-or-x');
    });

    test('each missing variable is named, and nothing is defaulted', () {
      // BYOK: no endpoint and no model may be assumed on the user's behalf,
      // so a half-configured run fails instead of picking a service.
      for (final variable in full.keys) {
        expect(
          () => openAiProviderFor({...full, variable: ''}),
          throwsA(isA<FallbackConfigError>().having(
              (e) => e.message, 'message', contains(variable))),
          reason: '$variable went unmentioned',
        );
      }
      expect(() => openAiProviderFor(const {}),
          throwsA(isA<FallbackConfigError>()));
    });
  });
}
