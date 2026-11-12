import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'xtream.dart';

/// Short-EPG cache with at most [_maxParallel] requests in flight. Every row of the channel list asks for its
/// channel, so while scrolling the newest requests (the rows on screen) go first and at most [_maxWaiting]
/// wait: older ones are answered with an empty list and asked again when their row is shown again.
class EpgCache {
  EpgCache(this.client);

  final XtreamClient client;
  static const _maxParallel = 4;
  static const _maxWaiting = 24;
  static const _ttl = Duration(minutes: 5);

  final Map<int, ({DateTime at, List<Programme> list})> _cache = {};
  final Map<int, Future<List<Programme>>> _inflight = {};
  final Queue<Completer<bool>> _waiting = Queue(); // completed with true when a request slot is handed over
  int _running = 0;

  List<Programme>? cached(int id) {
    final c = _cache[id];
    return c != null && DateTime.now().difference(c.at) < _ttl ? c.list : null;
  }

  Future<List<Programme>> get(int id) {
    final c = cached(id);
    if (c != null) return Future.value(c);
    // The block body matters: returning the removed future from whenComplete would make it wait for itself.
    return _inflight[id] ??= _fetch(id).whenComplete(() {
      _inflight.remove(id);
    });
  }

  Future<List<Programme>> _fetch(int id) async {
    if (_running < _maxParallel) {
      _running++;
    } else {
      final gate = Completer<bool>();
      _waiting.addLast(gate);
      if (_waiting.length > _maxWaiting) _waiting.removeFirst().complete(false);
      if (!await gate.future) return const []; // skipped, not cached
    }
    try {
      final list = await client.shortEpg(id);
      _cache[id] = (at: DateTime.now(), list: list);
      return list;
    } finally {
      // The slot goes straight to the newest waiter, if any.
      if (_waiting.isNotEmpty) {
        _waiting.removeLast().complete(true);
      } else {
        _running--;
      }
    }
  }
}

/// "Now playing" line with a progress bar for a live channel.
class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key, required this.cache, required this.item, required this.fallback});

  final EpgCache cache;
  final Item item;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final id = item.streamId;
    if (id == null) return Text(fallback, maxLines: 1, overflow: TextOverflow.ellipsis);
    return FutureBuilder<List<Programme>>(
      future: cache.get(id),
      initialData: cache.cached(id),
      builder: (context, snap) {
        final now = snap.data?.where((p) => p.isNow).firstOrNull;
        if (now == null) return Text(fallback, maxLines: 1, overflow: TextOverflow.ellipsis);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            LinearProgressIndicator(value: now.progress, minHeight: 2),
          ],
        );
      },
    );
  }
}
