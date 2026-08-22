/// The lists the CLI publishes about itself, tied back to what it does
/// (T-0077, T-0078), and the treatment those variables get (T-0080).
///
/// Both defects were the same shape and neither was found by a test: the skip
/// banner printed `Accepted: .jpg, .jpeg, .png, .webp` in the very run whose
/// stdout said `CONVERTED: ...HEIC -> jpeg`, and `.env.example` -- a file whose
/// whole purpose is completeness -- omitted one of the ten variables the CLI
/// reads. A reader noticed each; nothing was watching.
///
/// So nothing below retypes either list. The accepted list is compared against
/// the extensions a run of [readPhotoDirectory] over one file per offered
/// extension actually took, and the environment list against the lookups the
/// CLI source actually performs. Adding a format to `photo_format.dart`, or a
/// variable to `bin/`, fails here until the message and the file follow.
///
/// The third group extends that from presence to behaviour. Enumerating the
/// variables was not enough on its own: T-0077 listed all ten correctly and
/// two of them still read an empty value as a value. A name found by the scan
/// with no probe beside it now fails, so the treatment cannot be left to
/// whoever adds the next one.
///
/// The last two groups hold the local defaults to the same standard (T-0087).
/// The code half is exact -- one string literal, in the file that declares the
/// constant. The prose half cannot be, because a model name in `.env.example`
/// or README.md is as often history as it is a claim, so it is anchored on the
/// sentences that state a default: `ollama pull ...` must move when the default
/// does, and the line comparing `gemma3:12b` against the model measured behind
/// it must not.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        FallbackConfigError,
        HeicConversion,
        PhotoDirectory,
        acceptedList,
        anthropicProviderFor,
        conversionReport,
        envValue,
        fallbackProviderFor,
        heicConversionUnsupported,
        igdbCredentialsFrom,
        noPhotosMessage,
        ollamaProviderFor,
        openAiProviderFor,
        readPhotoDirectory,
        skipReport,
        windowsHeicToJpeg;

final _signatures = <String, List<int>>{
  'image/jpeg': const [0xFF, 0xD8, 0xFF, 0xE0],
  'image/png': const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  'image/webp': [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
  heicMimeType: [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
};

/// The bytes a file named `shelf<extension>` holds when its name is honest.
List<int> _bytesFor(String extension) {
  final mimeType = photoMimeTypes[extension] ?? convertibleMimeTypes[extension];
  final signature = mimeType == null ? null : _signatures[mimeType];
  if (signature == null) {
    fail('$extension is offered to users but nothing here can write one, so '
        'no run below would ever exercise it');
  }
  return [...signature, ...List.filled(32, 0)];
}

Directory _dirOf(Map<String, List<int>> files) {
  final dir = Directory.systemTemp.createTempSync('shelfscan_lists_');
  // Swallowed for the reason photo_directory_test.dart gives: on Windows the
  // delete races the handles just closed (T-0048).
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });
  for (final entry in files.entries) {
    File('${dir.path}${Platform.pathSeparator}${entry.key}')
        .writeAsBytesSync(entry.value);
  }
  return dir;
}

/// One honest file per offered extension, plus one file the scan will not
/// take -- without a skip there is no banner to read.
Directory _oneOfEverything() => _dirOf({
      for (final extension in scannableExtensions)
        'shelf$extension': _bytesFor(extension),
      'notes.txt': const [0],
    });

Map<String, HeicConversion> _converts(List<String> paths) => {
      for (final path in paths)
        path: HeicConversion.ok(Uint8List.fromList(_bytesFor('.jpg')),
            const Duration(milliseconds: 500))
    };

Map<String, HeicConversion> _cannotConvert(List<String> paths) => {
      for (final path in paths)
        path: HeicConversion.failed(
            heicConversionUnsupported('linux')!, Duration.zero)
    };

/// The extensions actually read out of [listing], by name.
Set<String> _extensionsRead(PhotoDirectory listing) =>
    {for (final photo in listing.photos) extensionOf(photo.name)};

/// The extensions a user-facing message claims are accepted.
Set<String> _extensionsOffered(String message) {
  final marker = message.indexOf('Accepted: ');
  expect(marker, isNonNegative, reason: 'no accepted list in: $message');
  return RegExp(r'\.[a-z0-9]+')
      .allMatches(message.substring(marker))
      .map((match) => match.group(0)!)
      .toSet();
}

String _banner(PhotoDirectory listing, {required bool convertsHeic}) =>
    skipReport(listing, convertsHeic: convertsHeic).last;

/// Repository root, found by walking up: `dart test` runs in the package and
/// `.env.example` lives two levels above it.
Directory _repoRoot() {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}

/// The CLI source, which three groups below read rather than restate.
String _binSource() =>
    File('${_repoRoot().path}/packages/shelfscan_core/bin/shelfscan.dart')
        .readAsStringSync();

/// Variables the CLI looks up, read off its source in the two shapes it uses:
/// an [envValue] call naming the variable, and a `const` holding the name for
/// a call elsewhere.
Set<String> _environmentNamesIn(String source) => {
      ...RegExp(r"envValue\(\s*\w+\s*,\s*'([A-Z][A-Z0-9_]*)'\s*\)")
          .allMatches(source)
          .map((match) => match.group(1)!),
      ...RegExp(r"=\s*'([A-Z][A-Z0-9_]{3,})'\s*;")
          .allMatches(source)
          .map((match) => match.group(1)!),
    };

/// Every name `.env.example` lists, commented-out entries included: the file
/// is a reference list of names, and a name shown as an example is still shown.
Set<String> _documentedNames(String text) => {
      for (final line in const LineSplitter().convert(text))
        ...RegExp(r'^#?\s*([A-Z][A-Z0-9_]*)=')
            .allMatches(line)
            .map((match) => match.group(1)!),
    };

/// The Dart that ships: both shells and the package they share. Test files are
/// out, because a test naming a default it did not import is a failure of its
/// own assertions rather than a second definition.
List<File> _shippedDart() => [
      for (final relative in const [
        'packages/shelfscan_core/lib',
        'packages/shelfscan_core/bin',
        'app/lib',
      ])
        ...Directory('${_repoRoot().path}/$relative')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];

/// Where [value] is written as a Dart string, which is the only shape a second
/// definition can take. Quoted, so that naming the value in a comment -- which
/// `ollama_vision.dart` and `provider_config.dart` both do, about runs that
/// used it -- is not mistaken for one.
RegExp _asStringLiteral(String value) =>
    RegExp("['\"]${RegExp.escape(value)}['\"]");

/// A statement of a default in prose: the file, the phrase the sentence opens
/// with, and what it has to name. Three lines from the anchor, because
/// `.env.example` wraps its sentence and README's CLI quote sits under it.
const _defaultIsStatedIn = <(String, String, String)>[
  ('.env.example', 'built-in default', defaultOllamaModel),
  ('.env.example', 'built-in default', defaultOllamaUrl),
  ('README.md', 'ollama pull ', defaultOllamaModel),
  ('README.md', 'Vision: local Ollama', defaultOllamaModel),
  ('README.md', 'That server is', defaultOllamaUrl),
];

/// The lines from the first line containing [anchor] onwards, or null if no
/// line does.
String? _passageAt(String text, String anchor) {
  final lines = const LineSplitter().convert(text);
  final start = lines.indexWhere((line) => line.contains(anchor));
  return start < 0 ? null : lines.skip(start).take(3).join('\n');
}

/// The one ALL-CAPS name in `bin/` that is not a variable the user sets: the
/// CLI writes it into the environment of the PowerShell it starts.
const _setForAChildProcess = {'SHELFSCAN_HEIC_LIST'};

final _ownPhotos = Platform.environment['SHELFSCAN_PHOTOS'];

/// A run every variable is set for, so blanking one is the only difference
/// between the two environments each case below compares.
const _configured = {
  'ANTHROPIC_API_KEY': 'sk-ant-not-a-key',
  'SHELFSCAN_ANTHROPIC_MODEL': 'claude-opus-5',
  'SHELFSCAN_OLLAMA_URL': 'http://192.0.2.10:11500',
  'SHELFSCAN_OLLAMA_MODEL': 'qwen2.5vl:32b',
  'SHELFSCAN_OLLAMA_FALLBACK_MODEL': 'gemma3:12b',
  'SHELFSCAN_VISION_TIMEOUT': '900',
  'SHELFSCAN_OPENAI_BASE_URL': 'https://api.groq.com/openai/v1',
  'SHELFSCAN_OPENAI_MODEL': 'meta-llama/llama-4-scout',
  'SHELFSCAN_OPENAI_API_KEY': 'gsk-not-a-key',
  'IGDB_CLIENT_ID': 'twitch-id',
  'IGDB_CLIENT_SECRET': 'twitch-secret',
};

/// Everything about what [build] made that a variable could have moved, as one
/// string: two environments agree here exactly when they configure the same
/// run. A refusal is an outcome like any other -- for six of the ten it is the
/// outcome an unset variable produces.
String _built(Object? Function() build) {
  final Object? made;
  try {
    made = build();
  } on FallbackConfigError catch (e) {
    return 'refused: $e';
  }
  return switch (made) {
    null => 'nothing',
    OllamaVisionProvider p =>
      'ollama ${p.model} at ${p.baseUrl} within ${p.timeout}',
    AnthropicVisionProvider p =>
      'anthropic ${p.model} at temperature ${p.temperature} '
          'within ${p.timeout}',
    OpenAiCompatibleVisionProvider p =>
      'openai ${p.model} at ${p.baseUrl} with ${p.apiKey} within ${p.timeout}',
    _ => '$made',
  };
}

/// One probe per variable: what the CLI builds out of an environment along the
/// path that variable is read on. Keyed by name and checked against the source
/// scan, so a variable added to `bin/` has no treatment until someone states
/// one here.
final _probes = <String, String Function(Map<String, String> env)>{
  'ANTHROPIC_API_KEY': (env) =>
      _built(() => fallbackProviderFor('anthropic', env)),
  'SHELFSCAN_ANTHROPIC_MODEL': (env) =>
      _built(() => anthropicProviderFor('sk-ant-not-a-key', env)),
  'SHELFSCAN_OLLAMA_URL': (env) => _built(() => ollamaProviderFor(env)),
  'SHELFSCAN_OLLAMA_MODEL': (env) => _built(() => ollamaProviderFor(env)),
  'SHELFSCAN_OLLAMA_FALLBACK_MODEL': (env) =>
      _built(() => fallbackProviderFor(null, env)),
  'SHELFSCAN_VISION_TIMEOUT': (env) => _built(() => ollamaProviderFor(env)),
  for (final name in const [
    'SHELFSCAN_OPENAI_BASE_URL',
    'SHELFSCAN_OPENAI_MODEL',
    'SHELFSCAN_OPENAI_API_KEY',
  ])
    name: (env) => _built(() => openAiProviderFor(env)),
  for (final name in const ['IGDB_CLIENT_ID', 'IGDB_CLIENT_SECRET'])
    name: (env) => _built(() => igdbCredentialsFrom(env)),
};

void main() {
  group('the accepted list is the run, restated', () {
    test('a converting run offers exactly what it took', () {
      final listing =
          readPhotoDirectory(_oneOfEverything(), convertHeic: _converts);
      expect(_extensionsRead(listing), scannableExtensions.toSet(),
          reason: 'the fixture holds one file per offered extension, so a '
              'format the scan cannot actually read shows up here first');
      expect(_extensionsOffered(_banner(listing, convertsHeic: true)),
          _extensionsRead(listing));
    });

    test('a host that cannot convert offers exactly what it took', () {
      final listing =
          readPhotoDirectory(_oneOfEverything(), convertHeic: _cannotConvert);
      expect(_extensionsRead(listing), photoMimeTypes.keys.toSet());
      expect(_extensionsOffered(_banner(listing, convertsHeic: false)),
          _extensionsRead(listing));
    });

    test('the run that converts a HEIC never says HEIC is not accepted', () {
      // T-0077 itself: these two reports were printed by one run, three lines
      // apart, and disagreed.
      final listing = readPhotoDirectory(
          _dirOf({
            'shelf-1.HEIC': _bytesFor('.heic'),
            'notes.txt': const [0],
          }),
          convertHeic: _converts);

      expect(conversionReport(listing).join('\n'), contains('-> jpeg'));
      expect(_extensionsOffered(_banner(listing, convertsHeic: true)),
          containsAll(convertibleMimeTypes.keys));
    });

    test('both messages that name the list name the same one', () {
      final scanned =
          readPhotoDirectory(_oneOfEverything(), convertHeic: _converts);
      final nothing = readPhotoDirectory(_dirOf({'notes.txt': const [0]}));
      expect(
        _extensionsOffered(
            noPhotosMessage(nothing, 'photos', convertsHeic: true)),
        _extensionsOffered(_banner(scanned, convertsHeic: true)),
      );
    });

    test('a format added to core reaches the message with no second edit', () {
      for (final extension in photoMimeTypes.keys) {
        expect(acceptedList(convertsHeic: true), contains(extension));
        expect(acceptedList(convertsHeic: false), contains(extension));
      }
      for (final extension in convertibleMimeTypes.keys) {
        expect(acceptedList(convertsHeic: true), contains(extension));
        expect(acceptedList(convertsHeic: false), isNot(contains(extension)));
      }
    });
  });

  group('.env.example', () {
    late Set<String> read;
    late Set<String> documented;

    setUp(() {
      read = _environmentNamesIn(_binSource());
      documented = _documentedNames(
          File('${_repoRoot().path}/.env.example').readAsStringSync());
    });

    test('lists every variable the CLI reads', () {
      expect(read, isNotEmpty, reason: 'the source scan found nothing, so the '
          'comparison below would pass on an empty file');
      expect(documented, containsAll(read));
    });

    test('lists nothing the CLI has stopped reading', () {
      expect(read, containsAll(documented));
    });

    test('no environment name in bin/ escapes the scan above', () {
      // The scan keys on two code shapes; a third would go unseen, which is
      // how T-0078 lasted. Any ALL-CAPS literal that is neither a lookup nor
      // the child-process variable fails here rather than silently.
      final literals = RegExp(r"'([A-Z][A-Z0-9_]{5,})'")
          .allMatches(_binSource())
          .map((match) => match.group(1)!)
          .toSet();
      expect(literals.difference(read).difference(_setForAChildProcess),
          isEmpty);
    });
  });

  group('a set-but-empty variable is an unset variable', () {
    test('the accessor every variable is read through', () {
      expect(envValue(const {'SHELFSCAN_X': ''}, 'SHELFSCAN_X'), isNull);
      expect(envValue(const {}, 'SHELFSCAN_X'), isNull);
      // Empty, not blank: the eight variables that already had the check used
      // isEmpty, and widening it to whitespace here would change six of them.
      expect(envValue(const {'SHELFSCAN_X': ' '}, 'SHELFSCAN_X'), ' ');
    });

    test('no lookup escapes it', () {
      final lookups = RegExp(r'\b(?:env|Platform\.environment)\[([^\]]*)\]')
          .allMatches(_binSource())
          .map((match) => match.group(1)!.trim())
          .toSet();
      expect(lookups, {'name'},
          reason: "the only environment indexing left in bin/ is envValue's "
              'own, by its parameter name; anything else is a variable read '
              'without the empty check, which is the whole of T-0080');
    });

    test('every variable the CLI reads is probed below', () {
      expect(_probes.keys.toSet(), _environmentNamesIn(_binSource()));
      expect(_configured.keys.toSet(), _probes.keys.toSet());
    });

    for (final entry in _probes.entries) {
      test('${entry.key} empty configures the run unset does', () {
        final probe = entry.value;
        final unset = {..._configured}..remove(entry.key);
        expect(probe(_configured), isNot(probe(unset)),
            reason: 'this probe does not answer to ${entry.key}, so the '
                'comparison below would pass however it is read');
        expect(probe({..._configured, entry.key: ''}), probe(unset));
      });
    }
  });

  group('the local defaults are written once', () {
    for (final (name, value) in const [
      ('defaultOllamaUrl', defaultOllamaUrl),
      ('defaultOllamaModel', defaultOllamaModel),
    ]) {
      test('$name is a literal in one shipped file, the one declaring it', () {
        final files = _shippedDart();
        expect(files, hasLength(greaterThan(10)),
            reason: 'the file walk found almost nothing, so the search below '
                'would pass on an empty repository');

        final copies = files
            .where((file) =>
                _asStringLiteral(value).hasMatch(file.readAsStringSync()))
            .map((file) => file.path.replaceAll('\\', '/'))
            .toList();

        expect(copies, hasLength(1),
            reason: 'since T-0082 this string is what clearing the Ollama '
                'field in Settings means, and the field hint is the string '
                'itself, so a second copy changes what clearing it does: '
                '$copies');
        expect(File(copies.single).readAsStringSync(), contains('const $name'),
            reason: 'the only file holding $value does not declare $name, so '
                'the constant has been inlined somewhere');
      });
    }

    test('both shells reach the provider default without naming it', () {
      // The two callers T-0087 collapsed, through the paths their users take:
      // an unset environment (T-0080) and a cleared field (T-0082) are the
      // same run as a provider nobody configured.
      final unconfigured = OllamaVisionProvider();
      final cli = ollamaProviderFor(const {});
      expect([cli.baseUrl, cli.model],
          [unconfigured.baseUrl, unconfigured.model]);
    });
  });

  group('the prose states the current defaults', () {
    late String envExample;
    late String readme;

    setUp(() {
      envExample = File('${_repoRoot().path}/.env.example').readAsStringSync();
      readme = File('${_repoRoot().path}/README.md').readAsStringSync();
    });

    String textOf(String file) => file == 'README.md' ? readme : envExample;

    for (final (file, anchor, value) in _defaultIsStatedIn) {
      test('$file: "$anchor" names $value', () {
        final passage = _passageAt(textOf(file), anchor);
        expect(passage, isNotNull,
            reason: '"$anchor" is gone from $file, so nothing below reads the '
                'sentence that used to state the default');
        expect(passage, contains(value));
      });
    }

    test('no documented address points at another Ollama', () {
      // Anchored on the default's own port rather than on a list of hosts: an
      // address in these two files is always a claim about where the local
      // provider talks, never a measurement that has to keep its old value.
      final port = Uri.parse(defaultOllamaUrl).port;
      final addresses = RegExp(r'https?://[\w.\-]+:' '$port' r'(?:/[\w./\-]*)?');
      for (final file in const ['.env.example', 'README.md']) {
        for (final match in addresses.allMatches(textOf(file))) {
          expect(match.group(0), defaultOllamaUrl, reason: 'in $file');
        }
      }
    });
  });

  group("the control photo directory", () {
    // Gitignored and outside any worktree, so this runs only when
    // SHELFSCAN_PHOTOS points at it (the convention app/test/heic_wic_test.dart
    // already uses). It is the run the defect was reported from: three HEICs
    // and a .csv beside two JPEGs, on Windows, through the real converter.
    test('the real skip banner agrees with the real conversion report', () {
      final listing = readPhotoDirectory(Directory(_ownPhotos!),
          convertHeic: windowsHeicToJpeg);
      final offered = _extensionsOffered(_banner(listing, convertsHeic: true));

      expect(listing.converted, isNotEmpty,
          reason: 'no HEIC was converted, so this run cannot contradict '
              'itself and proves nothing');
      for (final photo in listing.converted) {
        expect(offered, contains(extensionOf(photo.name)));
      }
      // Containment, not equality: a real directory holds whatever it holds,
      // and the fixture above is what pins the list down exactly.
      expect(offered, containsAll(_extensionsRead(listing)));
    });
  },
      skip: Platform.isWindows && Directory(_ownPhotos ?? '').existsSync()
          ? null
          : 'needs SHELFSCAN_PHOTOS pointing at the photo directory, on '
              'Windows');
}
