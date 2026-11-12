import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/epg_widgets.dart';
import 'package:iptv_app/src/xtream.dart';

/// Records which channels were actually requested; a request stays open until [finish] is called.
class _SlowClient extends XtreamClient {
  _SlowClient() : super(Account(name: 't', host: 'http://x', username: 'u', password: 'p'));

  final started = <int>[];
  final _open = <int, Completer<List<Programme>>>{};
  int maxOpen = 0;

  @override
  Future<List<Programme>> shortEpg(int streamId) {
    started.add(streamId);
    final c = _open[streamId] = Completer();
    if (_open.length > maxOpen) maxOpen = _open.length;
    return c.future;
  }

  bool get busy => _open.isNotEmpty;

  void finish(int id) => _open.remove(id)!.complete(const []);

  void finishAll() {
    for (final id in _open.keys.toList()) {
      finish(id);
    }
  }
}

void main() {
  test('a request for a channel that is not cached yet completes when the server answers', () async {
    final client = _SlowClient();
    final cache = EpgCache(client);
    final programmes = cache.get(7);
    await pumpEventQueue();
    client.finish(7);

    expect(await programmes.timeout(const Duration(seconds: 1)), isEmpty);
    expect(cache.cached(7), isNotNull);
  });

  test('channels requested last (the ones on screen) are served before the ones scrolled past', () async {
    final client = _SlowClient();
    final cache = EpgCache(client);
    for (var id = 0; id < 100; id++) {
      unawaited(cache.get(id));
    }
    await pumpEventQueue();
    expect(client.started, [0, 1, 2, 3]);

    client.finish(0);
    await pumpEventQueue();

    expect(client.started, [0, 1, 2, 3, 99]);
  });

  test('a long scroll does not turn into one request per channel passed', () async {
    final client = _SlowClient();
    final cache = EpgCache(client);
    final all = [for (var id = 0; id < 500; id++) cache.get(id)];
    await pumpEventQueue();
    while (client.busy) {
      client.finishAll();
      await pumpEventQueue();
    }

    await Future.wait(all).timeout(const Duration(seconds: 2)); // every row gets an answer, also the skipped ones
    expect(client.started.length, lessThan(60));
    expect(client.started, contains(499));
    expect(client.started, isNot(contains(100)));
    expect(cache.cached(100), isNull, reason: 'a skipped channel is asked again when its row is shown again');
    expect(client.maxOpen, 4);
  });
}
