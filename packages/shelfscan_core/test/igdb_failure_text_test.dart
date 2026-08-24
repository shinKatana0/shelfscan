/// What a refused resolve tells the person who registered the Twitch
/// application (T-0107).
///
/// The defect was the resolve stage's half of T-0072: `IgdbClient` threw
/// `Exception('IGDB API 401: ...')` with the endpoint's body inside it and
/// `Exception('Twitch OAuth 403: ...')` for a failed token, and it caught no
/// `http.ClientException` at all, so an offline machine arrived as a socket's
/// own sentence.
///
/// Every response here is a `MockClient` literal. No IGDB or Twitch credential
/// was available (BYOK, decision 0011), so unlike T-0072's
/// and T-0097's bodies none of these is measured -- which is the whole reason no
/// branch quotes one.
///
/// T-0143 added the other half: what each status *costs* in attempts, counted
/// rather than asserted from the exception's type, because the two halves have
/// to agree -- a sentence saying the retries were spent is a lie the user
/// cannot check unless the requests actually left.
library;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _clientId = 'twitch-client-id-9f2a';
const _clientSecret = 'twitch-client-secret-0123456789abcdef';

/// A document big enough that one warning per row would be a wall. A stand-in
/// of the right order: the control set's own size is a count of a private
/// collection and is in the working record (T-0246).
const _rows = 40;

const _goodToken = '{"access_token":"token-value","expires_in":3600}';

/// A body carrying the secret the request itself sent. Twitch is not known to
/// answer like this and could not be asked; it is the shape T-0072 measured
/// from api.openai.com, whose 401 echoed the key back with both ends intact.
const _leakyBody = '{"status":403,"message":"invalid client secret '
    '$_clientSecret","cause":"Authorization Failure"}';

/// IGDB's documented error shape: a JSON ARRAY, which is why `providerDetail`
/// cannot read it and why nothing here quotes a body through it.
const _igdbArrayBody = '[{"title":"Unauthorized","status":401,'
    '"cause":"Authorization Failure. Access Token is invalid."}]';

/// Every status the two paths can answer with, plus one nobody expects.
const _statuses = [400, 401, 403, 404, 429, 500, 502, 503, 418];

bool _isTokenRequest(http.BaseRequest request) =>
    request.url.host == 'id.twitch.tv';

IgdbClient _client(http.Response Function(http.BaseRequest) answer) =>
    IgdbClient(
      clientId: _clientId,
      clientSecret: _clientSecret,
      // The token's retries are counted below, never slept through: at the
      // shipped 2+4+8 s the four statuses that retry would cost this file 14 s
      // per client and it builds one per test.
      tokenRetryBackoff: Duration.zero,
      client: MockClient((request) async => answer(request)),
    );

/// The token succeeds; the search answers [status].
IgdbClient _searchFails(int status, {String body = _igdbArrayBody}) =>
    _client((request) => _isTokenRequest(request)
        ? http.Response(_goodToken, 200)
        : http.Response(body, status));

/// The token request answers [status]; the search is never reached.
IgdbClient _tokenFails(int status, {String body = _leakyBody}) =>
    _client((request) => _isTokenRequest(request)
        ? http.Response(body, status)
        : http.Response('[]', 200));

Future<Object> _failure(Future<void> Function() call) async {
  try {
    await call();
  } catch (e) {
    return e;
  }
  throw StateError('the client did not fail');
}

/// The error one client raises for one search. Both paths are driven through
/// `search`, because that is the only way a caller reaches either: `_getToken`
/// is awaited inside the search, so a Twitch failure surfaces here too.
Future<Object> _errorFrom(IgdbClient client) =>
    _failure(() => client.search('duskhollow', platformHint: 'PS4'));

/// A client that counts what each host actually received (T-0143).
class _Counted {
  _Counted(http.Response Function(http.BaseRequest) answer) {
    client = IgdbClient(
      clientId: _clientId,
      clientSecret: _clientSecret,
      tokenRetryBackoff: Duration.zero,
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

  late final IgdbClient client;
  var tokenRequests = 0;
  var searches = 0;
}

_Counted _countedTokenFails(int status) =>
    _Counted((request) => _isTokenRequest(request)
        ? http.Response(_leakyBody, status)
        : http.Response('[]', 200));

_Counted _countedSearchFails(int status) =>
    _Counted((request) => _isTokenRequest(request)
        ? http.Response(_goodToken, 200)
        : http.Response(_igdbArrayBody, status));

/// The search's retries are `Worker.run`'s, so they are only visible through a
/// worker. Backoff of 1 ms for the reason `igdb_rate_limit_test.dart` overrides
/// it: this counts attempts, it does not measure the wait.
class _FastRetryResolver extends ResolverWorker {
  _FastRetryResolver(super.igdb);

  @override
  Duration get backoffBase => const Duration(milliseconds: 1);
}

Detection _detection(int index) => Detection(
      rawTitle: 'SPINE $index',
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: 'shelf.jpg',
    );

/// What one detection costs when the search refuses it, through the mechanism
/// that actually retries.
Future<Object> _workerFailure(IgdbClient igdb) =>
    _failure(() => _FastRetryResolver(igdb).run(_detection(0)));

/// Token requests per status, the whole of T-0143's decision on that path:
/// `Worker.maxRetries` + 1 for a status that can clear, one for the rest.
/// Asked once per run, so this is the run's total whatever the row count.
const _tokenAttempts = <int, int>{
  400: 1, 401: 1, 403: 1, 404: 1, 418: 1,
  429: 4, 500: 4, 502: 4, 503: 4,
};

/// Searches per detection. Only the 429 is retried, and it is the one measured
/// to clear: T-0064 saw a sixth of its live requests rejected and every row
/// still resolved. A 5xx costs `rows / concurrency` x 14 s if it joins this
/// set -- minutes on the hi-res control set, against a stage that finishes in
/// seconds.
const _searchAttempts = <int, int>{
  400: 1, 401: 1, 403: 1, 404: 1, 418: 1,
  429: 4, 500: 1, 502: 1, 503: 1,
};

typedef _Path = ({String name, IgdbClient Function(int) failingAt});

final _paths = <_Path>[
  (name: 'token', failingAt: _tokenFails),
  (name: 'search', failingAt: _searchFails),
];

/// Runs [body] once per path with the message that path produced for [status].
void _forBothPaths(
  String description,
  int status,
  void Function(String message, Object error) body,
) {
  for (final path in _paths) {
    test('$description (${path.name}, HTTP $status)', () async {
      final error = await _errorFrom(path.failingAt(status));
      body('$error', error);
    });
  }
}

void main() {
  group('every non-200 path produces an explained sentence', () {
    for (final status in _statuses) {
      _forBothPaths('names the status and what it costs', status,
          (message, _) {
        expect(message, contains('$status'));
        // The one thing true of every resolve failure: the photographs have
        // already been read and the row survives as an unmatched entry.
        expect(message, contains('in the review unmatched'));
        expect(message, endsWith('matched by hand there.'));
      });

      _forBothPaths('is a sentence, not the endpoint\'s JSON', status,
          (message, _) {
        expect(message, isNot(contains('{')));
        expect(message, isNot(contains('[{')));
        expect(message, isNot(contains('"status":')));
        expect(message, isNot(contains('Exception')));
      });
    }

    test('and no two statuses read the same on either path', () async {
      for (final path in _paths) {
        final messages = [
          for (final status in _statuses)
            '${await _errorFrom(path.failingAt(status))}',
        ];

        expect(messages.toSet(), hasLength(messages.length));
      }
    });
  });

  group('401 and 403 name both halves of the pair and where to fix them', () {
    for (final status in [401, 403]) {
      _forBothPaths('names the client id, the secret and the console', status,
          (message, _) {
        expect(message, contains('IGDB_CLIENT_ID'));
        expect(message, contains('IGDB_CLIENT_SECRET'));
        expect(message, contains('https://dev.twitch.tv/console/apps'));
      });

      _forBothPaths('does not blame the model id or a vision key', status,
          (message, _) {
        expect(message.toLowerCase(), isNot(contains('model')));
        expect(message.toLowerCase(), isNot(contains('api key')));
      });
    }

    test('the two hosts explain the same status differently', () async {
      // A rejected pair at the token step and a rejected token at the search
      // step are different facts: the second means the id and the secret came
      // from two different applications.
      final token = '${await _errorFrom(_tokenFails(403))}';
      final search = '${await _errorFrom(_searchFails(403))}';

      expect(token, isNot(search));
      expect(token, contains('not a working pair'));
      expect(search, contains('two different Twitch applications'));
    });
  });

  group('a token failure is Twitch and a search failure is IGDB', () {
    for (final status in _statuses) {
      test('the token path names Twitch and only Twitch (HTTP $status)',
          () async {
        final message = '${await _errorFrom(_tokenFails(status))}';

        expect(message, startsWith('Twitch at https://id.twitch.tv/oauth2/'));
        // Naming IGDB's host here would send the user to the wrong status page.
        expect(message, isNot(contains('api.igdb.com')));
      });

      test('the search path names IGDB and not the token host (HTTP $status)',
          () async {
        final message = '${await _errorFrom(_searchFails(status))}';

        expect(message, startsWith('IGDB at https://api.igdb.com/v4'));
        expect(message, isNot(contains('id.twitch.tv')));
      });
    }

    test('the host is on the exception, not only in the text', () async {
      expect((await _errorFrom(_tokenFails(500)) as IgdbApiException).host,
          IgdbHost.twitch);
      expect((await _errorFrom(_searchFails(500)) as IgdbApiException).host,
          IgdbHost.igdb);
    });
  });

  group('an unreachable host is a sentence, not a ClientException', () {
    IgdbClient _dropping({required bool onToken}) => _client((request) {
          if (_isTokenRequest(request) == onToken) {
            throw http.ClientException(
                "Failed host lookup: 'api.igdb.com'", request.url);
          }
          return http.Response(_goodToken, 200);
        });

    test('the token host that did not answer is named', () async {
      final error = await _errorFrom(_dropping(onToken: true));

      expect(error, isA<IgdbUnreachableException>());
      expect((error as IgdbUnreachableException).host, IgdbHost.twitch);
      expect('$error', startsWith('Cannot reach Twitch at '));
      expect('$error', contains('id.twitch.tv'));
      expect('$error', isNot(contains('api.igdb.com/v4')));
    });

    test('the search host that did not answer is named', () async {
      final error = await _errorFrom(_dropping(onToken: false));

      expect(error, isA<IgdbUnreachableException>());
      expect((error as IgdbUnreachableException).host, IgdbHost.igdb);
      expect('$error', startsWith('Cannot reach IGDB at '));
    });

    test('the socket\'s own line is kept, in parentheses at the end', () async {
      final message = '${await _errorFrom(_dropping(onToken: false))}';

      expect(message, isNot(startsWith('ClientException')));
      expect(message, contains('nothing to correct in your settings'));
      expect(message, endsWith("(Failed host lookup: 'api.igdb.com')"));
    });

    // T-0355. The cross-family wording is pinned in
    // `unreachable_supertype_test.dart`; what is this file's is that the
    // clause did not displace what a resolve failure has to say about itself.
    test('the browser check arrives before what the failure costs', () async {
      final message = '${await _errorFrom(_dropping(onToken: false))}';

      expect(message, contains('Open that address in a browser'));
      expect(message, contains('rather than at the lookup'));
      expect(message.indexOf('Open that address'),
          lessThan(message.indexOf('Nothing read off the photographs is lost')));
      expect(message, contains('matched by hand there'));
    });

    test('and it is not retried', () async {
      expect(await _errorFrom(_dropping(onToken: true)),
          isNot(isA<RetryableException>()));
    });
  });

  group('no response body is ever pasted into a message', () {
    for (final status in _statuses) {
      _forBothPaths('the secret in the body does not reach the user', status,
          (message, _) {
        expect(message, isNot(contains(_clientSecret)));
        expect(message, isNot(contains(_clientId)));
        expect(message, isNot(contains('invalid client secret')));
      });
    }

    test('the body stays on the exception for a bug report', () async {
      final error = await _errorFrom(_tokenFails(403)) as IgdbApiException;

      expect(error.body, contains(_clientSecret));
      expect(error.statusCode, 403);
      // Same rule the vision vocabulary follows: kept, never quoted.
      expect(error.message, isNot(contains(error.body)));
    });

    test('IGDB\'s array shape is not quoted either', () async {
      // `providerDetail` cannot read a JSON array: it would find no explanation
      // field, fall back to the body and paste it capped at 200 characters.
      final message = '${await _errorFrom(_searchFails(401))}';

      expect(message, isNot(contains('Authorization Failure')));
      expect(message, isNot(contains('Access Token is invalid')));
    });
  });

  group('what is retried, counted (T-0143)', () {
    test('the two tables cover every status this file drives', () {
      expect(_tokenAttempts.keys.toSet(), _statuses.toSet());
      expect(_searchAttempts.keys.toSet(), _statuses.toSet());
    });

    for (final status in _statuses) {
      final attempts = _tokenAttempts[status]!;
      test('a token $status costs $attempts request(s)', () async {
        final counted = _countedTokenFails(status);

        await _failure(() => counted.client.search('duskhollow'));

        expect(counted.tokenRequests, attempts);
        expect(counted.searches, 0, reason: 'no row can search without a token');
      });

      final searches = _searchAttempts[status]!;
      test('a search $status costs $searches attempt(s) per row', () async {
        final counted = _countedSearchFails(status);

        await _workerFailure(counted.client);

        expect(counted.searches, searches);
        expect(counted.tokenRequests, 1, reason: 'a retry reuses the token');
      });
    }

    test('no token failure is ever retryable to the worker as well', () async {
      // The guard on the whole design: T-0144 caches the first token failure,
      // so a RetryableException here would make every row sleep Worker's 14 s
      // to be handed that cached error with no request going out.
      for (final status in _statuses) {
        expect(await _errorFrom(_tokenFails(status)),
            isNot(isA<RetryableException>()),
            reason: 'HTTP $status');
      }
    });
  });

  group('the token is retried once for the run, not once per row (T-0144)', () {
    test('a whole document shares the four attempts and one warning', () async {
      final counted = _countedTokenFails(503);
      final warnings = <String>[];

      final games = await Orchestrator.resolveOnly(
        resolverWorker: ResolverWorker(counted.client),
        resolverConcurrency: 4,
      ).runResolve(
        [for (var i = 0; i < _rows; i++) _detection(i)],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      // 14 s once for the document. The same policy on the search would be
      // rows x 14 / concurrency seconds, which is why only this path has it.
      expect(counted.tokenRequests, 4);
      expect(counted.searches, 0);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('$_rows detection(s)'));
      expect(games, hasLength(_rows));
      expect(games.every((game) => game.best == null), isTrue);
    });

    test('a blip that clears is never remembered', () async {
      // The case T-0144 could not have: its remembering sees only failures that
      // have already survived the retries, so a host that comes back inside
      // them costs the run nothing at all.
      var tokenRequests = 0;
      final client = IgdbClient(
        clientId: _clientId,
        clientSecret: _clientSecret,
        tokenRetryBackoff: Duration.zero,
        client: MockClient((request) async {
          if (!_isTokenRequest(request)) return http.Response('[]', 200);
          tokenRequests += 1;
          return tokenRequests > 2
              ? http.Response(_goodToken, 200)
              : http.Response(_leakyBody, 503);
        }),
      );

      expect(await client.search('duskhollow'), isEmpty);
      expect(tokenRequests, 3);
      expect(await client.search('frost wake'), isEmpty);
      expect(tokenRequests, 3, reason: 'the token is now cached');
    });
  });

  group('no sentence claims retries that were not spent', () {
    test('a search 429 stays retryable and still explains itself', () async {
      final error = await _errorFrom(_searchFails(429));

      expect(error, isA<RetryableException>());
      expect('$error', contains('rate-limiting the search'));
      expect('$error', contains('retries did not clear it'));
      // The type name is not an explanation and used to be this whole line.
      expect('$error', isNot(contains('RetryableException')));
      expect('$error', isNot(contains('IGDB rate limit')));
    });

    test('a token 429 is retried now, and says so', () async {
      final message = '${await _errorFrom(_tokenFails(429))}';

      expect(message, contains('rate-limiting the token request'));
      expect(message, contains('retries did not clear it'));
    });

    for (final status in [500, 502, 503]) {
      test('a Twitch $status says the retries were spent', () async {
        final message = '${await _errorFrom(_tokenFails(status))}';

        expect(message, contains('failed on its own side'));
        expect(message, contains('retries did not clear it'));
        // What a token failure costs, which a search failure does not.
        expect(message, contains('none of them was searched for'));
      });

      test('an IGDB $status is not retried and does not claim it was', () async {
        final error = await _errorFrom(_searchFails(status));
        final message = '$error';

        expect(error, isNot(isA<RetryableException>()));
        expect(message, contains('failed on its own side'));
        expect(message, contains('try again later'));
        expect(message, isNot(contains('retries')));
      });
    }

    for (final status in [400, 401, 403, 404, 418]) {
      _forBothPaths('a $status mentions no retries at all', status,
          (message, _) {
        expect(message, isNot(contains('retries')));
      });
    }
  });

  group('the statuses that are neither the credentials nor the host', () {
    test('an IGDB 400 blames the query this build sent, not the user',
        () async {
      final message = '${await _errorFrom(_searchFails(400))}';

      expect(message, contains('rejected the query'));
      expect(message, contains('nothing to correct in your credentials'));
    });

    test('a Twitch 400 points at the client id rather than the secret',
        () async {
      final message = '${await _errorFrom(_tokenFails(400))}';

      expect(message, contains('IGDB_CLIENT_ID'));
      expect(message, contains('rather than the secret'));
    });

    _forBothPaths('a 404 says the address is fixed in this build', 404,
        (message, _) {
      expect(message, contains('nothing at that address is serving'));
      expect(message, contains('fixed in this build'));
    });

    _forBothPaths('a status nobody expects still says which host', 418,
        (message, _) {
      expect(message, contains('refused the request (HTTP 418)'));
    });
  });
}
