// Roda na UI isolate: configura/inicia o serviço, recebe 1 amostra/s e calcula métricas + pontos do gráfico.
import 'dart:collection';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'ping_task_handler.dart';

// main.dart:
//   void main() {
//     FlutterForegroundTask.initCommunicationPort();   // antes do runApp
//     runApp(const MyApp());
//   }

class PingSample {
  PingSample(this.time, this.rttMs);
  final DateTime time;
  final double? rttMs; // null = perda
  bool get lost => rttMs == null;
}

class PingStats {
  const PingStats({
    required this.sent, required this.lossPct, required this.current,
    required this.avg, required this.min, required this.max,
    required this.jitter, required this.disconnects,
  });
  final int sent;
  final double lossPct;
  final double? current, avg, min, max;
  final double jitter;
  final int disconnects;
  static const empty = PingStats(sent: 0, lossPct: 0, current: null, avg: null, min: null, max: null, jitter: 0, disconnects: 0);
}

class StabilityController extends ChangeNotifier {
  static const windowOptionsMin = [5, 10, 30, 60];
  static const outageThreshold = 3; // 3 perdas seguidas = 1 desconexão

  final ListQueue<PingSample> _buf = ListQueue();
  int _windowMin = 5;
  int _consecLoss = 0, _disconnects = 0;
  bool _inOutage = false;

  bool running = false;
  String host = '8.8.8.8';

  int get windowMin => _windowMin;
  set windowMin(int m) { // trocar a janela NÃO zera a coleta
    _windowMin = m;
    _trim();
    notifyListeners();
  }

  int get _cap => _windowMin * 60; // 1 amostra/s

  static void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ping_monitor',
        channelName: 'Monitoramento de estabilidade',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000), // << Timer de 1 s
        autoRunOnBoot: false,
        allowWakeLock: true, // PARTIAL_WAKE_LOCK
        allowWifiLock: true, // WifiLock
      ),
    );
  }

  Future<bool> start(String targetHost) async {
    host = targetHost;
    _reset();

    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.saveData(key: 'host', value: host);
    FlutterForegroundTask.addTaskDataCallback(_onData);

    final result = await FlutterForegroundTask.startService(
      serviceId: 4101,
      notificationTitle: 'Monitoramento ativo',
      notificationText: 'Ping $host a cada 1 s',
      callback: startCallback,
    );
    running = result is ServiceRequestSuccess;
    notifyListeners();
    return running;
  }

  Future<void> stop() async {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    await FlutterForegroundTask.stopService();
    running = false;
    notifyListeners();
  }

  void _onData(Object data) {
    if (data is! Map) return;
    final rtt = (data['rtt'] as num?)?.toDouble();
    final s = PingSample(DateTime.fromMillisecondsSinceEpoch(data['ts'] as int), rtt);

    if (s.lost) {
      _consecLoss++;
      if (_consecLoss >= outageThreshold && !_inOutage) {
        _inOutage = true;
        _disconnects++;
      }
    } else {
      _consecLoss = 0;
      _inOutage = false;
    }

    _buf.addLast(s);
    _trim();
    notifyListeners();
  }

  void _trim() {
    while (_buf.length > _cap) { _buf.removeFirst(); }
  }

  void _reset() {
    _buf.clear();
    _consecLoss = 0;
    _disconnects = 0;
    _inOutage = false;
  }

  PingStats get stats {
    if (_buf.isEmpty) return PingStats.empty;
    final ok = _buf.where((s) => !s.lost).map((s) => s.rttMs!).toList();
    final lost = _buf.length - ok.length;

    // jitter = média das variações absolutas entre RTTs consecutivos bem-sucedidos
    double jitterSum = 0; int jn = 0;
    double? prev;
    for (final s in _buf) {
      if (s.lost) { prev = null; continue; }
      if (prev != null) { jitterSum += (s.rttMs! - prev).abs(); jn++; }
      prev = s.rttMs;
    }

    return PingStats(
      sent: _buf.length,
      lossPct: lost / _buf.length * 100,
      current: _buf.last.rttMs,
      avg: ok.isEmpty ? null : ok.reduce((a, b) => a + b) / ok.length,
      min: ok.isEmpty ? null : ok.reduce((a, b) => a < b ? a : b),
      max: ok.isEmpty ? null : ok.reduce((a, b) => a > b ? a : b),
      jitter: jn == 0 ? 0 : jitterSum / jn,
      disconnects: _disconnects,
    );
  }

  /// Pontos para o fl_chart. Janela de 60 min = 3600 amostras: decimamos para ~maxPoints
  /// pegando o MAIOR RTT por bucket (picos não somem). Bucket 100% perdido vira buraco (nullSpot).
  List<FlSpot> chartSpots({int maxPoints = 300}) {
    final n = _buf.length;
    if (n == 0) return const [];
    final bucket = (n / maxPoints).ceil().clamp(1, 1 << 30);
    final list = _buf.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < n; i += bucket) {
      final end = (i + bucket) > n ? n : i + bucket;
      double? peak;
      for (var j = i; j < end; j++) {
        final v = list[j].rttMs;
        if (v != null && (peak == null || v > peak)) peak = v;
      }
      final x = i / bucket;
      spots.add(peak == null ? FlSpot.nullSpot : FlSpot(x, peak));
    }
    return spots;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onData);
    super.dispose();
  }
}
