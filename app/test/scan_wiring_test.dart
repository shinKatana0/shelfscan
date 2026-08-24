/// How the app wires settings into the pipeline.
///
/// Two behaviours are pinned here, both of which used to be hardcoded in
/// the scan screen:
///   * no IGDB credentials -> the resolve stage is skipped outright, the
///     way the CLI has always behaved -- not attempted with empty ones;
///   * the platform policy decides what can be built, even if the stored
///     settings say otherwise.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/input_picker.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

/// Counts everything that would become IGDB/Twitch traffic.
class CountingIgdbClient extends IgdbClient {
  CountingIgdbClient() : super(clientId: 'id', clientSecret: 'secret');

  int searches = 0;

  @override
  Future<List<IgdbHit>> search(String query, {String? platformHint}) async {
    searches += 1;
    return [
      IgdbHit(
        igdbId: 1,
        title: query,
        platformId: 48,
        platformName: 'PlayStation 4',
      ),
    ];
  }
}

class FakeVisionProvider implements VisionProvider {
  FakeVisionProvider({this.unreadableSpines = 0});

  /// How many spines this provider claims to have seen but not read --
  /// the condition that makes an escalation eligible at all (T-0011).
  final int unreadableSpines;
  int calls = 0;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    calls += 1;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: 'DUSKHOLLOW',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
          platformHint: 'PS4',
        ),
        Detection(
          rawTitle: 'MOOR',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
          platformHint: 'PS4',
        ),
      ],
      unreadable: [
        for (var i = 0; i < unreadableSpines; i++)
          UnreadSpineReport(
            sourcePhoto: photo.name,
            script: SpineScript.japanese,
            reason: 'cannot read',
          ),
      ],
    );
  }
}

/// Lets a widget test "pick" photos without a real file dialog.
class FakeInputPicker extends InputPicker {
  FakeInputPicker([this.names = const ['shelf1.jpg'], Uint8List? bytes])
      : bytes = bytes ?? Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  final List<String> names;

  /// A JPEG signature and nothing else by default: enough for the scan screen
  /// to accept the file and label it `image/jpeg` (T-0039), not enough for
  /// Flutter to draw it -- only the tests that look at what the review screen
  /// draws need that.
  final Uint8List bytes;

  @override
  Future<List<PickedFile>?> pickPhotos() async =>
      [for (final name in names) (name: name, bytes: bytes)];

  @override
  Future<String?> pickFolder({required String prompt}) async => null;
}

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1, 2, 3]));

Future<ReviewDocument> _runScan(ResolverWorker resolver) => Orchestrator(
      visionWorker: VisionWorker(FakeVisionProvider()),
      resolverWorker: resolver,
    ).runScan([_photo('shelf1.jpg')]);

/// A detection of [kind], with every field the pipeline does not read here
/// at its emptiest. Invented titles throughout.
Detection _row(String title, WorkKind kind) => Detection(
      rawTitle: title,
      mediaType: MediaType.unknown,
      confidence: 1.0,
      sourcePhoto: '',
      workKind: kind,
    );

/// The IGDB resolver a keyed run registers for [WorkKind.game].
ResolverWorker gameCatalogueOf(ResolverWorker resolver) =>
    (resolver as CatalogueRouter).catalogues[WorkKind.game]! as ResolverWorker;

void main() {
  tearDown(() => ProviderPolicy.debugLocalServerIsThisMachineOverride = null);

  group('resolver wiring', () {
    test('no IGDB credentials -> the shared SkipResolver', () {
      expect(ProviderPolicy.buildResolver(ProviderSettings()),
          isA<SkipResolver>());
      // Half a pair is not a pair.
      expect(
        ProviderPolicy.buildResolver(ProviderSettings(igdbClientId: 'id')),
        isA<SkipResolver>(),
      );
      expect(
        ProviderPolicy.buildResolver(
            ProviderSettings(igdbClientSecret: 'secret')),
        isA<SkipResolver>(),
      );
    });

    test('both halves present -> a real resolver with those credentials', () {
      final resolver = ProviderPolicy.buildResolver(
          ProviderSettings(igdbClientId: 'id', igdbClientSecret: 'secret'));

      expect(resolver, isNot(isA<SkipResolver>()));
      // Since T-0308 the credentials are one entry down: what a keyed run
      // gets is a router, and IGDB is what it registered for one kind.
      expect(gameCatalogueOf(resolver).igdb.clientId, 'id');
      expect(gameCatalogueOf(resolver).igdb.clientSecret, 'secret');
    });

    // The defect T-0308 fixed: with credentials, ONE resolver answered every
    // row, and it was the IGDB one -- so a film was searched in the games
    // catalogue. These assert on where a row is sent, which is the only place
    // that failure was ever visible.
    test('a keyed run routes each kind, and only games reach IGDB', () {
      final resolver = ProviderPolicy.buildResolver(
          ProviderSettings(igdbClientId: 'id', igdbClientSecret: 'secret'));

      expect(resolver, isA<CatalogueRouter>());
      final router = resolver as CatalogueRouter;
      expect(router.catalogues.keys, [WorkKind.game]);
      expect(router.fallback, isA<SkipResolver>());
      for (final kind in WorkKind.values.where((k) => k != WorkKind.game)) {
        expect(router.catalogues[kind], isNull,
            reason: '$kind has no catalogue in this shell, so it must fall to '
                'the keyless resolver rather than to IGDB');
      }
    });

    // The path most people will be on, and the one a new field could quietly
    // move (T-0363). It is the same assertion the test above makes about the
    // registration, carried through to what a film row actually comes back
    // as -- the half a user would notice.
    test('with no TMDB token a film row is keyless, exactly as before',
        () async {
      final resolver = ProviderPolicy.buildResolver(
          ProviderSettings(igdbClientId: 'id', igdbClientSecret: 'secret'));

      final router = resolver as CatalogueRouter;
      expect(router.catalogues.containsKey(WorkKind.movie), isFalse);

      // Reaches SkipResolver, so nothing is asked of any catalogue and no
      // client is built that could ask.
      final film =
          await resolver.process(_row('The Harbour Lantern', WorkKind.movie));
      expect(film.best, isNull);
      expect(film.candidates, isEmpty);
      expect(film.detection.rawTitle, 'The Harbour Lantern');
    });

    test('a stored TMDB token registers the film catalogue with that token',
        () {
      final resolver = ProviderPolicy.buildResolver(ProviderSettings(
        igdbClientId: 'id',
        igdbClientSecret: 'secret',
        tmdbToken: 'tmdb-not-a-token',
      ));

      final router = resolver as CatalogueRouter;
      expect(router.catalogues.keys, [WorkKind.game, WorkKind.movie]);
      final films = router.catalogues[WorkKind.movie]! as TmdbResolverWorker;
      expect(films.tmdb.token, 'tmdb-not-a-token');
      // Games still go to IGDB, which is the failure T-0308's router exists
      // to prevent, asserted from the other side.
      expect(gameCatalogueOf(resolver).igdb.clientId, 'id');
    });

    // Two limitations, pinned rather than described, because both are what a
    // reader would otherwise call a bug: the token rides on the IGDB-shaped
    // mode this shell asks about, so it does nothing in a run that is keyless
    // for either reason. The CLI resolves films on a TMDB token alone.
    // T-0367 holds the difference.
    test('a TMDB token alone does not key a run in this shell', () {
      expect(
        ProviderPolicy.buildResolver(
            ProviderSettings(tmdbToken: 'tmdb-not-a-token')),
        isA<SkipResolver>(),
      );
      expect(
        ProviderPolicy.buildResolver(
          ProviderSettings(
            igdbClientId: 'id',
            igdbClientSecret: 'secret',
            tmdbToken: 'tmdb-not-a-token',
          ),
          matching: TitleMatching.keyless,
        ),
        isA<SkipResolver>(),
        reason: 'Keyless is a mode the user chose and it says every row keeps '
            'the title it was read with -- a stored token may not overrule it',
      );
    });

    test('a film row in a keyed run asks IGDB nothing and comes back '
        'unresolved', () async {
      // The owner's decision, and the one path anyone can run: no TMDB token
      // can exist in this shell, so this is what a film row does today.
      final igdb = CountingIgdbClient();
      final resolver = CatalogueRouter(
        catalogues: {WorkKind.game: ResolverWorker(igdb)},
        fallback: SkipResolver(),
      );

      final resolvedFilm =
          await resolver.process(_row('The Harbour Lantern', WorkKind.movie));
      expect(igdb.searches, 0);
      expect(resolvedFilm.best, isNull);
      expect(resolvedFilm.candidates, isEmpty);
      expect(resolvedFilm.detection.rawTitle, 'The Harbour Lantern');

      // The other half of the same claim: games are unaffected.
      await resolver.process(_row('Nocturne 5 Gold', WorkKind.game));
      expect(igdb.searches, 1);
    });

    test('a keyless scan issues zero IGDB requests and leaves games '
        'unresolved', () async {
      final igdb = CountingIgdbClient();

      final doc = await _runScan(SkipResolver(igdbForTest: igdb));

      expect(igdb.searches, 0);
      expect(doc.games, hasLength(2));
      for (final game in doc.games) {
        expect(game.best, isNull);
        expect(game.candidates, isEmpty);
        expect(game.status, ReviewStatus.pending);
      }
    });

    test('control: the same scan with credentials does call IGDB', () async {
      final igdb = CountingIgdbClient();

      final doc = await _runScan(ResolverWorker(igdb));

      expect(igdb.searches, 2);
      expect(doc.games.where((g) => g.best != null), isNotEmpty);
    });

    test('SkipResolver cannot reach the network even if someone tries',
        () async {
      // The default client refuses, so "zero IGDB traffic" is a property of
      // the type rather than of caller discipline.
      await expectLater(
          SkipResolver().igdb.search('moor'), throwsA(isA<StateError>()));
    });
  });

  group('platform policy', () {
    test('a phone offers local too, and still defaults to cloud', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;

      // T-0361: the phone runs no model, it names one on the network. Which
      // is why the second line did not move -- an option is not a preference,
      // and a default needing an address nobody has typed is a broken first
      // launch.
      expect(ProviderPolicy.available, contains(VisionBackend.local));
      expect(ProviderPolicy.defaultBackend, VisionBackend.cloud);
    });

    test('an external endpoint is offered but never defaulted to', () {
      // Decision 0011: photos of a private home never leave the machine
      // because of a default -- only because the user picked an endpoint.
      for (final onThisMachine in [true, false]) {
        ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;

        expect(ProviderPolicy.available,
            contains(VisionBackend.openAiCompatible));
        expect(ProviderPolicy.defaultBackend,
            isNot(VisionBackend.openAiCompatible));
        expect(ProviderSettings().backend,
            isNot(VisionBackend.openAiCompatible));
      }
    });

    test('on a phone local is built from the address, and refused without one',
        () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      final settings = ProviderSettings(backend: VisionBackend.local);

      // Nothing was typed and nothing was substituted for it (T-0361): the
      // default is loopback and loopback here is the phone.
      expect(settings.ollamaUrl, isEmpty);
      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));

      // The one address that is wrong without asking the network -- which is
      // what preferences restored from a desktop backup carry onto a phone.
      settings.ollamaUrl = 'http://127.0.0.1:11434';
      expect(ProviderPolicy.check(settings).blocker, contains('this device'));
      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));

      settings.ollamaUrl = 'http://a-desktop.invalid:11434';
      expect(ProviderPolicy.check(settings).blocker, isNull);
      final provider =
          ProviderPolicy.build(settings) as OllamaVisionProvider;
      expect(provider.baseUrl, 'http://a-desktop.invalid:11434');
    });

    test('the endpoint backend is built from the three fields the user typed',
        () {
      final provider = ProviderPolicy.build(ProviderSettings(
        backend: VisionBackend.openAiCompatible,
        openAiBaseUrl: 'https://openrouter.ai/api/v1',
        openAiModel: 'qwen/qwen2.5-vl-72b-instruct',
        openAiApiKey: 'sk-or-x',
      )) as OpenAiCompatibleVisionProvider;

      expect(provider.baseUrl, 'https://openrouter.ai/api/v1');
      expect(provider.model, 'qwen/qwen2.5-vl-72b-instruct');
      expect(provider.apiKey, 'sk-or-x');
    });

    test('each missing endpoint field is its own friendly error', () {
      final settings = ProviderSettings(
          backend: VisionBackend.openAiCompatible);

      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));
      settings.openAiBaseUrl = 'https://api.groq.com/openai/v1';
      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));
      settings.openAiModel = 'llama-4-scout';
      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));
      settings.openAiApiKey = 'gsk-x';
      expect(ProviderPolicy.build(settings),
          isA<OpenAiCompatibleVisionProvider>());
    });
  });

  group('one reader per photo (T-0061)', () {
    testWidgets('a scan reads each photo exactly once, key stored, spines '
        'unread, and a stale cloud_fallback in preferences', (tester) async {
      // Everything the removed toggle used to need is present: a local run,
      // an Anthropic key, two spines the model admits it could not read, and
      // the preference an older build wrote when the switch was on. None of
      // it can produce a second call now.
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final prefs = RecordingStore();
      await prefs.write('cloud_fallback', 'true');
      final secrets = RecordingStore()
        ..values[SettingsStore.keyAnthropicApiKey] = 'sk-ant-x';
      final store = SettingsStore(secrets: secrets, prefs: prefs);
      final vision = FakeVisionProvider(unreadableSpines: 2);

      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: await store.load(),
          store: store,
          picker: FakeInputPicker(),
          debugVisionProvider: vision,
        ),
      ));
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(vision.calls, 1);
      // Withheld second reading is not withheld information: the unread
      // spines still reach review.
      expect(find.byKey(const Key('unreadable-prompt')), findsOneWidget);
    });
  });

  group('scan screen', () {
    testWidgets('a cloud scan with no key explains itself and offers Settings',
        (tester) async {
      final settings = ProviderSettings(backend: VisionBackend.cloud);
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings,
          store: SettingsStore(
              secrets: RecordingStore(), prefs: RecordingStore()),
          picker: FakeInputPicker(),
        ),
      ));

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);

      // ... and the message is actionable.
      await tester.tap(find.byKey(const Key('status-open-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const Key('settings-anthropic-key')), findsOneWidget);
    });

    testWidgets('the key entered in Settings is the one the next scan uses',
        (tester) async {
      final settings = ProviderSettings(backend: VisionBackend.cloud);
      final secrets = RecordingStore();
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings,
          store: SettingsStore(secrets: secrets, prefs: RecordingStore()),
          picker: FakeInputPicker(),
        ),
      ));

      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('settings-anthropic-key')), 'sk-ant-typed');
      // The save button sits below the fold in the test viewport, and the
      // field just typed into scrolls the view back to itself unless focus
      // is dropped first.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(find.text('shelfscan'), findsOneWidget); // back on the scan screen
      expect(settings.anthropicApiKey, 'sk-ant-typed');
      expect(secrets.values['anthropic_api_key'], 'sk-ant-typed');
      expect(ProviderPolicy.build(settings), isA<AnthropicVisionProvider>());
    });

    testWidgets('the photos the scan ran on reach the review screen (T-0042)',
        (tester) async {
      // The bytes exist only here: the document carries photo names, so if
      // the scan screen does not hand its list over, review has no images
      // and no way to get them.
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: ProviderSettings(backend: VisionBackend.local),
          store: SettingsStore(
              secrets: RecordingStore(), prefs: RecordingStore()),
          picker: FakeInputPicker(
            ['shelf1.jpg', 'shelf2.jpg'],
            base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlE'
                'QVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
          ),
          debugVisionProvider: FakeVisionProvider(),
        ),
      ));
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      for (final name in ['shelf1.jpg', 'shelf2.jpg']) {
        final header =
            tester.widget<InkWell>(find.byKey(Key('photo-group-$name')));
        expect(header.onTap, isNotNull,
            reason: 'the group can be enlarged, so its bytes arrived');
      }
      expect(find.byType(Image), findsNWidgets(2));
    });
  });
}
