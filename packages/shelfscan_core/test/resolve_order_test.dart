/// Row order out of `Orchestrator.runResolve` (T-0068, T-0066).
///
/// The order has to be decided by the input alone, because everything else
/// available is either constant (the local model's confidence is 1.0 on every
/// detection) or a race (which IGDB answer arrives first).
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// Resolves nothing, but finishes in an order of the caller's choosing.
///
/// The delays exist to make the pool hand results back in an order the input
/// did not have: without that these tests pass on code that simply never
/// reorders anything.
class _ScrambledResolver extends SkipResolver {
  _ScrambledResolver(this.delays);

  /// Raw title -> how long that detection takes to resolve.
  final Map<String, int> delays;
  final completed = <String>[];

  @override
  Future<ResolvedGame> process(Detection task) async {
    await Future<void>.delayed(Duration(milliseconds: delays[task.rawTitle] ?? 0));
    completed.add(task.rawTitle);
    return ResolvedGame(detection: task);
  }
}

/// Fails on the titles it is given, so a fallback row is produced out of band.
class _FailingResolver extends SkipResolver {
  _FailingResolver(this.failing);

  final Set<String> failing;

  @override
  int get maxRetries => 0;

  @override
  Future<ResolvedGame> process(Detection task) async {
    if (failing.contains(task.rawTitle)) throw StateError('IGDB is down');
    return ResolvedGame(detection: task);
  }
}

Detection _read(String title, String photo, {double confidence = 1.0}) =>
    Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: confidence,
      sourcePhoto: photo,
    );

Future<List<String>> _order(List<Detection> detections,
    {ResolverWorker? resolver}) async {
  final resolved = await Orchestrator.resolveOnly(
    resolverWorker: resolver ?? SkipResolver(),
  ).runResolve(detections);
  return [for (final game in resolved) game.detection.rawTitle];
}

void main() {
  group('two resolves of one document', () {
    test('agree row for row however the answers come back', () async {
      final detections = [
        for (var i = 0; i < 12; i++)
          _read('TITLE $i', 'shelf_${i.isEven ? 'a' : 'b'}.jpg'),
      ];
      // Reverse-ordered delays: the last detection finishes first.
      final delays = {
        for (var i = 0; i < 12; i++) 'TITLE $i': (12 - i) * 4,
      };
      final first = _ScrambledResolver(delays);
      final second = _ScrambledResolver({
        for (final entry in delays.entries) entry.key: 48 - entry.value,
      });

      final a = await _order(detections, resolver: first);
      final b = await _order(detections, resolver: second);

      expect(first.completed, isNot(second.completed),
          reason: 'the two runs must resolve in different orders, or this '
              'proves nothing');
      expect(a, b);
    });

    test('write byte-identical documents', () async {
      final detections = [
        for (var i = 0; i < 10; i++) _read('TITLE $i', 'shelf_a.jpg'),
      ];
      String render(List<ResolvedGame> games) => jsonEncode(ReviewDocument(
            version: 1,
            created: 'pinned',
            photos: const ['shelf_a.jpg'],
            games: games,
          ).toJson());

      final orchestrator =
          Orchestrator.resolveOnly(resolverWorker: _ScrambledResolver({
        for (var i = 0; i < 10; i++) 'TITLE $i': (10 - i) * 3,
      }));
      final first = render(await orchestrator.runResolve(detections));
      final second = render(await orchestrator.runResolve(detections));

      expect(first, second);
    });
  });

  group('ordering key', () {
    test('groups by photo and keeps input order inside a photo', () async {
      final detections = [
        _read('B1', 'shelf_b.jpg'),
        _read('A1', 'shelf_a.jpg'),
        _read('B2', 'shelf_b.jpg'),
        _read('A2', 'shelf_a.jpg'),
      ];
      expect(await _order(detections), ['A1', 'A2', 'B1', 'B2']);
    });

    test('the input index is the tie-break, not completion order', () async {
      // Same photo, so the photo key ties and only the tie-break can decide.
      final detections = [
        _read('FIRST IN', 'shelf_a.jpg'),
        _read('SECOND IN', 'shelf_a.jpg'),
      ];
      final resolver =
          _ScrambledResolver({'FIRST IN': 30, 'SECOND IN': 0});

      final order = await _order(detections, resolver: resolver);

      expect(resolver.completed, ['SECOND IN', 'FIRST IN']);
      expect(order, ['FIRST IN', 'SECOND IN'],
          reason: 'drop the index tie-break and this is completion order');
    });

    test('confidence orders nothing: it is 1.0 for every local read',
        () async {
      final detections = [
        _read('LOW', 'shelf_a.jpg', confidence: 0.1),
        _read('HIGH', 'shelf_a.jpg', confidence: 0.9),
      ];
      expect(await _order(detections), ['LOW', 'HIGH']);
    });

    test('a row that failed to resolve keeps its place', () async {
      final detections = [
        _read('OK 1', 'shelf_a.jpg'),
        _read('BROKEN', 'shelf_a.jpg'),
        _read('OK 2', 'shelf_a.jpg'),
      ];
      final warnings = <String>[];

      final resolved = await Orchestrator.resolveOnly(
        resolverWorker: _FailingResolver({'BROKEN'}),
      ).runResolve(detections,
          progress: ScanProgress(onWarning: (w) => warnings.add(w.message)));

      expect([for (final game in resolved) game.detection.rawTitle],
          ['OK 1', 'BROKEN', 'OK 2']);
      expect(warnings.single, contains('BROKEN'));
    });
  });

  group('a hand-typed row (T-0066)', () {
    test('files under the photo it was typed from, not at the front',
        () async {
      final detections = [
        _read('A1', 'shelf_a.jpg'),
        _read('B1', 'shelf_b.jpg'),
        Detection.manual(rawTitle: 'TYPED', addedFromPhoto: 'shelf_a.jpg'),
        _read('A2', 'shelf_a.jpg'),
      ];
      expect(await _order(detections), ['A1', 'TYPED', 'A2', 'B1']);
    });

    test('typed with no photo in view, it goes last', () async {
      final detections = [
        Detection.manual(rawTitle: 'LOOSE'),
        _read('A1', 'shelf_a.jpg'),
        _read('B1', 'shelf_b.jpg'),
      ];
      expect(await _order(detections), ['A1', 'B1', 'LOOSE']);
    });

    test('a document row with no source photo goes last too', () async {
      final detections = [
        _read('NO PHOTO', ''),
        _read('A1', 'shelf_a.jpg'),
      ];
      expect(await _order(detections), ['A1', 'NO PHOTO']);
    });
  });
}
