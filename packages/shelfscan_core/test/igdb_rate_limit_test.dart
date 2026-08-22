/// The documented 4 rps holds however many lanes ask for it (T-0064).
///
/// Live, before this: 8 lanes put 24 searches into one rolling second and had
/// a sixth of the run rejected. Nothing was lost -- a 429 is retried, and the
/// document came out byte-identical -- so the whole defect is invisible in the
/// run's own summary, which is why it is pinned here rather than left to the
/// next measurement. [igdbRequestsPerSecond] carries the table.
///
/// The two halves have to hold together: the client must not provoke a 429,
/// and it must still survive one that arrives anyway.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A search request with the millisecond it was issued at.
class _Issued {
  _Issued(this.body, this.at);

  final String body;
  final int at;
}

const _tokenBody = '{"access_token":"t","expires_in":3600}';

/// Enough of a game for the search to count as answered: a query that comes
/// back with nothing is retried on shortened forms since T-0065, and this file
/// counts requests per detection.
const _oneHit = [
  {
    'id': 1,
    'name': 'A Game',
    'platforms': [
      {'id': 130, 'name': 'Nintendo Switch'},
    ],
  },
];

/// Answers the token request and every search, recording when each search was
/// issued. [failFirstSearches] many searches are rejected with a 429 first.
class _CountingIgdb {
  _CountingIgdb({this.failFirstSearches = 0});

  final int failFirstSearches;
  final searches = <_Issued>[];
  var tokenRequests = 0;
  var rejected = 0;

  IgdbClient get client => IgdbClient(
        clientId: 'id',
        clientSecret: 'secret',
        client: MockClient((request) async {
          if (request.url.host == 'id.twitch.tv') {
            tokenRequests += 1;
            return http.Response(_tokenBody, 200);
          }
          searches.add(
              _Issued(request.body, DateTime.now().millisecondsSinceEpoch));
          if (rejected < failFirstSearches) {
            rejected += 1;
            return http.Response('rate limit', 429);
          }
          return http.Response(jsonEncode(_oneHit), 200);
        }),
      );

  /// Issue times relative to the first, for a failure that has to say what it
  /// saw rather than only that it was too many.
  List<int> get offsets =>
      [for (final s in searches) s.at - searches.first.at];
}

/// What the limiter guarantees, in its own terms: `_RequestWindow` grants a
/// slot only while fewer than `limit` grants sit inside the preceding rolling
/// second, so grant `k` cannot precede grant `k - limit` by less than 1000 ms.
/// Twelve rows at four a second are therefore three releases of four, a second
/// apart.
///
/// Both of those are statements about *grant* times on the limiter's monotonic
/// clock. What this file can see is *issue* times: the moment a request reaches
/// [MockClient], one scheduling hop later, and a hop that only ever delays.
/// That is the whole of the defect this constant replaces. Counting issues in a
/// sliding 950 ms window asked whether two releases could be seen inside one
/// window, and the answer moved with the machine rather than with the limiter:
/// the delay on the *first* request is subtracted from every period measured
/// after it, so a run whose first request lagged 65 ms showed its releases
/// 935 ms apart and reported six in a window. Nothing was wrong with the
/// limiter in any of the three red runs replayed below.
///
/// So group by release instead and check the size of one, which needs only
/// that a release be tighter than the space between two.
///
/// Half the limiter's second, and that is the midpoint of the usable band
/// rather than a fudge inside it. Smear does not lengthen a run: it eats the
/// gap it borrows from, so a release's own spread and the gap after it sum to
/// the period whatever the load. Measured over 52 resolve runs -- seven rounds
/// of concurrent full suites, up to 8 at once on 24 logical cores -- spread
/// plus gap stayed within a few ms of 1000 every time, at a median spread of
/// 6 ms and a worst of 190, against a median gap of 1000 ms and a worst of
/// 824. The band is therefore (spread, 1000 - spread) and 500 is its centre at
/// every load; the split moves only once a single release smears past 500 ms,
/// 2.6x the worst recorded here, and by then the run is not three releases of
/// four under any reading.
const _releaseGap = 500;

/// Issue times grouped into the limiter's releases, in order.
List<List<int>> _releases(List<int> offsets) {
  final grouped = <List<int>>[];
  for (final at in offsets) {
    if (grouped.isEmpty || at - grouped.last.last >= _releaseGap) {
      grouped.add([at]);
    } else {
      grouped.last.add(at);
    }
  }
  return grouped;
}

/// Retries as the real one does, without the real one's 2 s first backoff.
class _FastRetryResolver extends ResolverWorker {
  _FastRetryResolver(super.igdb);

  @override
  Duration get backoffBase => const Duration(milliseconds: 10);
}

List<Detection> _detections(int count) => [
      for (var i = 0; i < count; i++)
        Detection(
          rawTitle: 'TITLE $i',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf.jpg',
        ),
    ];

void main() {
  test('eight lanes still issue no more than four requests a second',
      () async {
    final igdb = _CountingIgdb();
    final started = Stopwatch()..start();

    await Orchestrator.resolveOnly(
      resolverWorker: ResolverWorker(igdb.client),
      resolverConcurrency: 8,
    ).runResolve(_detections(12));
    started.stop();

    expect(igdb.searches, hasLength(12), reason: 'one search per detection');
    expect(
        _releases(igdb.offsets).map((r) => r.length),
        everyElement(lessThanOrEqualTo(igdbRequestsPerSecond)),
        reason: 'issued at ms ${igdb.offsets}');
    // The lag-proof half of the same claim, and the one that cannot fail for
    // being slow: 12 requests at 4 a second take at least 2 s however many
    // lanes ask for them, where 8 unlimited lanes finish them in ~3 ms.
    expect(started.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)),
        reason: 'issued at ms ${igdb.offsets}');
  });

  test('the analysis reads a loaded machine and a broken limiter apart', () {
    // Issue times off the three runs that went red on the sliding window
    // (T-0219), which reported 7, 6 and 8. The limiter was correct in all
    // three; the analysis was not.
    for (final red in const [
      [0, 44, 45, 45, 955, 964, 977, 979, 1948, 1958, 1968, 1987],
      [0, 6, 6, 6, 935, 940, 955, 959, 1940, 1948, 1956, 1961],
      [0, 68, 68, 68, 888, 902, 920, 935, 1880, 1899, 1924, 1949],
    ]) {
      expect(_releases(red).map((r) => r.length), [4, 4, 4], reason: '$red');
    }
    // No limiter at all: 8 unlimited lanes finish 12 rows in ~3 ms.
    expect(_releases(const [0, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5]).single,
        hasLength(12));
    // Twice the rate, which is what a limit raised or a window halved looks
    // like from here.
    expect(
      _releases(const [0, 2, 3, 3, 4, 5, 6, 7, 1002, 1003, 1004, 1005]).map(
        (r) => r.length,
      ),
      [8, 4],
    );
  });

  test('the shipped default asks for no more than the documented rate', () {
    expect(
      Orchestrator.resolveOnly(resolverWorker: SkipResolver())
          .resolverConcurrency,
      lessThanOrEqualTo(igdbRequestsPerSecond),
    );
  });

  test('a 429 that arrives anyway is still retried, not lost', () async {
    final igdb = _CountingIgdb(failFirstSearches: 2);

    final resolved = await Orchestrator.resolveOnly(
      resolverWorker: _FastRetryResolver(igdb.client),
      resolverConcurrency: 1,
    ).runResolve(_detections(1));

    expect(resolved, hasLength(1));
    expect(resolved.single.detection.rawTitle, 'TITLE 0');
    expect(igdb.searches, hasLength(3), reason: 'two rejections, then the row');
    expect(igdb.tokenRequests, 1, reason: 'a retry reuses the token');
  });
}
