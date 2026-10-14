// Roda DENTRO do Foreground Service (isolate separado). Sobrevive a app minimizado/tela apagada.
import 'dart:async';
import 'package:dart_ping/dart_ping.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PingTaskHandler());
}

class PingTaskHandler extends TaskHandler {
  String _host = '8.8.8.8';
  bool _busy = false;
  int _sent = 0, _lost = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _host = await FlutterForegroundTask.getData<String>(key: 'host') ?? _host;
  }

  /// Disparado a cada 1000 ms (ForegroundTaskOptions.eventAction = repeat(1000)).
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_busy) return; // evita empilhar pings se um demorar
    _busy = true;
    _pingOnce().then((rtt) {
      _sent++;
      if (rtt == null) _lost++;
      FlutterForegroundTask.sendDataToMain({
        'ts': timestamp.millisecondsSinceEpoch,
        'rtt': rtt, // null = perda
      });
      if (_sent % 5 == 0) {
        final loss = (_lost / _sent * 100).toStringAsFixed(1);
        FlutterForegroundTask.updateService(
          notificationTitle: 'Monitorando $_host',
          notificationText: 'Último: ${rtt == null ? 'timeout' : '${rtt.toStringAsFixed(1)} ms'} | perda $loss%',
        );
      }
    }).whenComplete(() => _busy = false);
  }

  Future<double?> _pingOnce() async {
    final ping = Ping(_host, count: 1, timeout: 1);
    try {
      // dart_ping 10.x: Stream<PingEvent> selado (PingResponse | PingError | PingSummary)
      final ev = await ping.stream.first.timeout(const Duration(milliseconds: 1500));
      if (ev is PingResponse) {
        final t = ev.time;
        return t == null ? null : t.inMicroseconds / 1000.0;
      }
      return null; // PingError / timeout = perda
    } catch (_) {
      return null;
    } finally {
      await ping.stop();
    }
  }

  // flutter_foreground_task v9+: onDestroy(timestamp, isTimeout)
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
