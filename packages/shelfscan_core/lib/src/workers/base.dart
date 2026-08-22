/// Worker base class and a bounded concurrency pool.
///
/// A worker is a small, stateless unit that processes exactly one task.
/// Concurrency, ordering and error aggregation are the orchestrator's job;
/// retries and backoff for transient failures are the worker's job.
library;

import 'dart:async';

/// Throw inside [Worker.process] for transient failures (rate limit, 5xx).
class RetryableException implements Exception {
  RetryableException(this.message);
  final String message;
  @override
  String toString() => 'RetryableException: $message';
}

abstract class Worker<T, R> {
  int get maxRetries => 3;
  Duration get backoffBase => const Duration(seconds: 2);

  /// Execute with simple exponential backoff on [RetryableException].
  Future<R> run(T task) async {
    var attempt = 0;
    while (true) {
      try {
        return await process(task);
      } on RetryableException {
        attempt += 1;
        if (attempt > maxRetries) rethrow;
        await Future<void>.delayed(backoffBase * (1 << (attempt - 1)));
      }
    }
  }

  /// Do the actual work for one task.
  Future<R> process(T task);
}

/// A run's stop switch: lanes finish what they hold and pull nothing more.
///
/// It cannot abandon a call in flight, and that is the design rather than a
/// limitation. Dropping a `Future` abandons the wait, not the socket (T-0104),
/// so a token that "cancelled" the in-flight request would report a stop while
/// the request was still being served and paid for. What bounds the wait is the
/// per-call timeout instead: `visionCallTimeout` 120 s, `igdbCallTimeout` 20 s.
///
/// One-way and per run. Nothing resets it: a reused token would silently stop
/// the next run before it started.
class StopToken {
  bool _stopped = false;
  bool get isStopped => _stopped;

  void stop() => _stopped = true;
}

/// Run [action] over [items] with at most [concurrency] tasks in flight.
///
/// Failures are reported through [onError] and excluded from the result
/// instead of failing the whole batch: one bad photo must not kill a run.
///
/// [stop] excludes items the same way, and is checked only between items: once
/// it is stopped no lane pulls another, so the result holds what finished and
/// the caller reads what never started off what is missing from it (T-0121).
Future<List<R>> runPool<T, R>(
  List<T> items,
  Future<R> Function(T item) action, {
  required int concurrency,
  void Function(T item, Object error)? onError,
  StopToken? stop,
}) async {
  final results = <R>[];
  final queue = List<T>.from(items);

  Future<void> lane() async {
    while (queue.isNotEmpty) {
      if (stop?.isStopped ?? false) return;
      final item = queue.removeAt(0);
      try {
        results.add(await action(item));
      } catch (e) {
        onError?.call(item, e);
      }
    }
  }

  await Future.wait(List.generate(concurrency, (_) => lane()));
  return results;
}
