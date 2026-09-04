/// The two shells register the same catalogues, and neither names a kind
/// while doing it (T-0369).
///
/// **Nothing else can pin this.** Which kind goes to which catalogue is a
/// property of the shell by decision 0016 -- `CatalogueRouter` holds a map the
/// shell builds, deliberately, so that a third catalogue is one entry and no
/// production line moves. That is the right shape and it has one cost: there
/// are two shells, so there are two places to edit and one of them can be
/// forgotten. It has been. T-0308 wired the film catalogue into the CLI and
/// could not wire it into the app, which had nowhere to keep a token, and the
/// two disagreed until T-0367 and T-0363 closed it.
///
/// So the guard is a source comparison, the way `galaxy_db_test.dart` guards
/// the other deliberate duplication across this boundary. Each shell's own
/// suite already asserts what its router comes out holding; what neither can
/// see is the other shell.
///
/// This suite runs from `app/`, which is why the CLI is reached with `../`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cliPath = 'packages/shelfscan_core/bin/shelfscan.dart';
const _appPath = 'app/lib/provider_config.dart';

/// Newlines folded, for the reason `galaxy_db_test.dart` folds them: the
/// repository has no `.gitattributes`, so on Windows these files check out
/// with CRLF and a whitespace-sensitive read would answer differently there.
String _read(String fromAppDir) =>
    File(fromAppDir).readAsStringSync().replaceAll('\r\n', '\n');

String _cli() => _read('../$_cliPath');
String _app() => _read('lib/provider_config.dart');

/// Every catalogue a shell registers, named by the expression that builds it.
///
/// Whitespace is flattened first so a wrapped argument list reads the same as
/// a short one -- the app's is wrapped and the CLI's is not, and that is
/// formatting rather than disagreement.
List<String> _registered(String source) => [
      for (final m in RegExp(r'registrationsOf\(\s*([A-Za-z_][\w.]*)\(')
          .allMatches(source.replaceAll(RegExp(r'\s+'), ' ')))
        m.group(1)!,
    ];

void main() {
  group('the CLI and the app register the same catalogues', () {
    test('the same three, in the same order', () {
      final cli = _registered(_cli());
      final app = _registered(_app());

      expect(cli, isNotEmpty,
          reason: 'a source scan of $_cliPath for `registrationsOf(` found '
              'nothing, so the two shells cannot be compared at all -- the '
              'CLI builds its catalogue map some other way now');
      expect(app, cli,
          reason: 'the shells have drifted: $_appPath registers $app and '
              '$_cliPath registers $cli. Both must move together, which is '
              'what T-0367 had just finished making true of the credentials');
    });

    test('and it is the set this task settled', () {
      // Named rather than merely compared, so that dropping the series
      // catalogue from BOTH shells is still a red test. Two files agreeing on
      // the wrong thing is the failure a symmetry check cannot see.
      expect(_registered(_cli()), [
        'ResolverWorker',
        'TmdbResolverWorker.movies',
        'TmdbResolverWorker.series',
      ]);
    });

    test('neither shell names a WorkKind while registering one', () {
      // The registration is derived from the catalogue's own `answers`, never
      // typed beside it. `{WorkKind.animationSeries: TmdbResolverWorker
      // .movies(c)}` is the one-line mistake this task exists to make
      // unwritable -- an animated series answered with a film's id, under the
      // same `tmdb:` namespace that decision 0016's export check compares.
      final asMapKey = RegExp(r'WorkKind\.\w+\s*:');

      expect(asMapKey.hasMatch(_cli()), isFalse,
          reason: '$_cliPath spells a WorkKind as a map key again');
      expect(asMapKey.hasMatch(_app()), isFalse,
          reason: '$_appPath spells a WorkKind as a map key again');
    });
  });
}
