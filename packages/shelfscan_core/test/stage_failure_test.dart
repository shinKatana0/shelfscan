/// A failure of the whole resolve stage is not N row failures (T-0144).
///
/// The defect measured on a real hi-res control document at
/// `resolverConcurrency` 4, with a Twitch 403 on the credentials: **one warning
/// per row, all carrying one explanation, a token request per wave of lanes,
/// and every row unresolved**. The token count is `rows / resolverConcurrency`
/// and so is stated as that rather than as a number (T-0267). The row count
/// below is a stand-in of the same order, not the control set's own size --
/// that is a count of a private collection and is in the working record
/// (T-0246).
/// The rows are right; the other two are what this pins.
///
/// Every response here is a `MockClient` literal and both credentials are
/// literals of this file: no IGDB or Twitch credential was available
/// (BYOK, decision 0011).
library;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _clientId = 'test-client-id';
const _clientSecret = 'test-client-secret';

/// A stand-in of the same order as the document the defect was measured on,
/// and the count the warning has to survive. Not that document's own size,
/// for the reason the header gives.
const _rows = 40;

const _goodToken = '{"access_token":"token-value","expires_in":3600}';

bool _isTokenRequest(http.Request request) =>
    request.url.host == 'id.twitch.tv';

/// The query a search carries, lower-cased by the resolver's normalization,
/// so a mock can answer one row differently from another.
String _query(http.Request request) => request.body;

List<Detection> _detections(int count) => [
      for (var i = 0; i < count; i++)
        Detection(
          rawTitle: 'SPINE $i',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf.jpg',
        ),
    ];

/// Counts what actually left, which is the figure the second defect is about:
/// the client asked Twitch again for every wave of lanes.
class _Counting {
  var tokenRequests = 0;
  var searches = 0;

  IgdbClient client(http.Response Function(http.Request) answer) =>
      IgdbClient(
        clientId: _clientId,
        clientSecret: _clientSecret,
        client: MockClient((request) async {
          if (_isTokenRequest(request)) {
            tokenRequests += 1;
          } else {
            searches += 1;
          }
          return answer(request);
        }),
      );
}

/// The token request is refused; the search is never reached.
IgdbClient _credentialsRejected(_Counting counter, {int status = 403}) =>
    counter.client((request) => _isTokenRequest(request)
        ? http.Response('{"status":$status,"message":"forbidden"}', status)
        : http.Response('[]', 200));

Future<(List<ResolvedGame>, List<String>)> _resolve(
  IgdbClient igdb,
  List<Detection> detections, {
  int concurrency = 4,
}) async {
  final warnings = <String>[];
  final games = await Orchestrator.resolveOnly(
    resolverWorker: ResolverWorker(igdb),
    resolverConcurrency: concurrency,
  ).runResolve(
    detections,
    progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
  );
  return (games, warnings);
}

void main() {
  group('one cause, one warning', () {
    test('a credentials failure on every row is one line naming the count',
        () async {
      final counter = _Counting();
      final (games, warnings) =
          await _resolve(_credentialsRejected(counter), _detections(_rows));

      expect(warnings, hasLength(1),
          reason: 'the defect is $_rows lines carrying one explanation');
      expect(warnings.single, contains('$_rows detection(s)'));
      // The explanation itself is T-0107's and is carried through unchanged.
      expect(warnings.single, contains('Twitch'));
      expect(warnings.single, contains('HTTP 403'));
      expect(games, hasLength(_rows));
    });

    test('the titles are in the review, not in the warning', () async {
      final counter = _Counting();
      final detections = _detections(_rows);
      final (games, warnings) =
          await _resolve(_credentialsRejected(counter), detections);

      // Anything the pipeline drops is named (decision 0012) -- and nothing is
      // dropped: every row is in the document, unmatched, with the spine read
      // intact, which is where the warning says the titles are.
      expect([for (final game in games) game.detection.rawTitle],
          [for (final detection in detections) detection.rawTitle]);
      expect(games.every((game) => game.best == null), isTrue);
      expect(games.every((game) => game.candidates.isEmpty), isTrue);
      for (final detection in detections) {
        expect(warnings.single, isNot(contains(detection.rawTitle)));
      }
    });

    test('a lone failure still names the row it lost', () async {
      // One row failing is not the repetition this fixes, and the title is
      // what makes that line actionable.
      final counter = _Counting();
      final igdb = counter.client((request) => _isTokenRequest(request)
          ? http.Response(_goodToken, 200)
          : http.Response(
              '[]', _query(request).contains('broken') ? 400 : 200));
      final (games, warnings) = await _resolve(igdb, [
        ..._detections(3),
        Detection(
          rawTitle: 'BROKEN SPINE',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf.jpg',
        ),
      ]);

      expect(warnings, hasLength(1));
      expect(warnings.single, contains('"BROKEN SPINE"'));
      expect(warnings.single, isNot(contains('detection(s)')));
      expect(games, hasLength(4));
    });
  });

  group('two causes are still two warnings', () {
    test('each names its own count and its own explanation', () async {
      final counter = _Counting();
      // Two different statuses from one host: same exception class, different
      // sentences. Grouping by type would fold these into one line and lose
      // the half of the answer that says what to do.
      final igdb = counter.client((request) => _isTokenRequest(request)
          ? http.Response(_goodToken, 200)
          : http.Response(
              '[]', _query(request).contains('spine 0') ? 404 : 500));
      // Concurrency 1 so the order the warnings come out in is the document's
      // and not a lane race.
      final (games, warnings) =
          await _resolve(igdb, _detections(4), concurrency: 1);

      expect(warnings, hasLength(2));
      // Input order, not the pool's completion order.
      expect(warnings.first, contains('"SPINE 0"'));
      expect(warnings.first, contains('HTTP 404'));
      expect(warnings.last, contains('3 detection(s)'));
      expect(warnings.last, contains('HTTP 500'));
      expect(games, hasLength(4));
    });
  });

  group('a rejected token is asked once', () {
    for (final concurrency in [1, 4, 16]) {
      test('$_rows rows at concurrency $concurrency cost one token request',
          () async {
        final counter = _Counting();
        final (games, warnings) = await _resolve(
          _credentialsRejected(counter),
          _detections(_rows),
          concurrency: concurrency,
        );

        expect(counter.tokenRequests, 1,
            reason: 'a wrong secret cannot become right inside one run');
        expect(counter.searches, 0,
            reason: 'no row can search without a token');
        expect(warnings, hasLength(1));
        expect(games, hasLength(_rows));
      });
    }

    test('every row still fails with the sentence that explains it', () async {
      // Remembering the failure must not turn a named failure into a silent
      // one: the rows degrade exactly as they did, they are simply not paid
      // for twice.
      final counter = _Counting();
      final igdb = _credentialsRejected(counter, status: 401);
      final errors = <Object>[];
      for (var i = 0; i < 3; i++) {
        try {
          await igdb.search('duskhollow');
        } catch (e) {
          errors.add(e);
        }
      }

      expect(counter.tokenRequests, 1);
      expect(errors, hasLength(3));
      expect(errors.map((e) => '$e').toSet(), hasLength(1));
      expect('${errors.first}', contains('HTTP 401'));
      expect(errors.every((e) => e is IgdbApiException), isTrue);
    });

    test('a working token is still fetched once and reused', () async {
      final counter = _Counting();
      final igdb = counter.client((request) => _isTokenRequest(request)
          ? http.Response(_goodToken, 200)
          : http.Response('[]', 200));
      final (games, warnings) = await _resolve(igdb, _detections(8));

      expect(counter.tokenRequests, 1);
      expect(warnings, isEmpty);
      expect(games, hasLength(8));
    });
  });
}
