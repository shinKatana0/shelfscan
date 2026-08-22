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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
class FakeFilePicker extends FilePicker {
  FakeFilePicker([this.names = const ['shelf1.jpg'], Uint8List? bytes])
      : bytes = bytes ?? Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  final List<String> names;

  /// A JPEG signature and nothing else by default: enough for the scan screen
  /// to accept the file and label it `image/jpeg` (T-0039), not enough for
  /// Flutter to draw it -- only the tests that look at what the review screen
  /// draws need that.
  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        for (final name in names)
          PlatformFile(name: name, size: bytes.length, bytes: bytes),
      ]);
}

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1, 2, 3]));

Future<ReviewDocument> _runScan(ResolverWorker resolver) => Orchestrator(
      visionWorker: VisionWorker(FakeVisionProvider()),
      resolverWorker: resolver,
    ).runScan([_photo('shelf1.jpg')]);

void main() {
  tearDown(() => ProviderPolicy.debugLocalAllowedOverride = null);

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
      expect(resolver.igdb.clientId, 'id');
      expect(resolver.igdb.clientSecret, 'secret');
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
    test('a cloud-only platform offers no local backend', () {
      ProviderPolicy.debugLocalAllowedOverride = false;

      expect(ProviderPolicy.available, isNot(contains(VisionBackend.local)));
      expect(ProviderPolicy.defaultBackend, VisionBackend.cloud);
    });

    test('an external endpoint is offered but never defaulted to', () {
      // Decision 0011: photos of a private home never leave the machine
      // because of a default -- only because the user picked an endpoint.
      for (final localAllowed in [true, false]) {
        ProviderPolicy.debugLocalAllowedOverride = localAllowed;

        expect(ProviderPolicy.available,
            contains(VisionBackend.openAiCompatible));
        expect(ProviderPolicy.defaultBackend,
            isNot(VisionBackend.openAiCompatible));
        expect(ProviderSettings().backend,
            isNot(VisionBackend.openAiCompatible));
      }
    });

    test('a local backend is not constructible on a cloud-only platform', () {
      ProviderPolicy.debugLocalAllowedOverride = false;
      // Stored settings still say "local" -- e.g. preferences restored from
      // a desktop backup.
      final settings = ProviderSettings(backend: VisionBackend.local);

      // It falls back to cloud, and cloud without a key is the friendly
      // error -- never an Ollama provider.
      expect(() => ProviderPolicy.build(settings), throwsA(isA<StateError>()));

      settings.anthropicApiKey = 'sk-ant-x';
      expect(ProviderPolicy.build(settings), isA<AnthropicVisionProvider>());
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
    setUp(() => FilePicker.platform = FakeFilePicker());

    testWidgets('a scan reads each photo exactly once, key stored, spines '
        'unread, and a stale cloud_fallback in preferences', (tester) async {
      // Everything the removed toggle used to need is present: a local run,
      // an Anthropic key, two spines the model admits it could not read, and
      // the preference an older build wrote when the switch was on. None of
      // it can produce a second call now.
      ProviderPolicy.debugLocalAllowedOverride = true;
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
    setUp(() => FilePicker.platform = FakeFilePicker());

    testWidgets('a cloud scan with no key explains itself and offers Settings',
        (tester) async {
      final settings = ProviderSettings(backend: VisionBackend.cloud);
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings,
          store: SettingsStore(
              secrets: RecordingStore(), prefs: RecordingStore()),
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
      FilePicker.platform = FakeFilePicker(
        ['shelf1.jpg', 'shelf2.jpg'],
        base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlE'
            'QVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
      );
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: ProviderSettings(backend: VisionBackend.local),
          store: SettingsStore(
              secrets: RecordingStore(), prefs: RecordingStore()),
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
