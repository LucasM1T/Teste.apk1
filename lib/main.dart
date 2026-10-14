import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:image_picker/image_picker.dart';
import 'evidence/location_service.dart';
import 'evidence/watermark_service.dart';
import 'monitor/stability_controller.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  StabilityController.initService();
  runApp(const MaterialApp(home: HomePage(), debugShowCheckedModeBanner: false));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final c = StabilityController();
  final hostCtl = TextEditingController(text: '8.8.8.8');
  final osCtl = TextEditingController(text: '0001');
  final techCtl = TextEditingController(text: 'T-01');
  File? photo;
  String? msg;

  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      if (shot == null) return;
      setState(() => msg = 'Obtendo GPS...');
      final pos = await LocationService.capture();
      final f = await WatermarkService.stampAndSave(
        sourcePath: shot.path,
        data: WatermarkData(
          osId: osCtl.text, techId: techCtl.text, when: DateTime.now(),
          lat: pos.latitude, lon: pos.longitude,
          accuracyM: pos.accuracy, altitudeM: pos.altitude,
        ),
      );
      setState(() { photo = f; msg = 'Salva em ${f.path}'; });
    } catch (e) {
      setState(() => msg = 'Erro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ISP Field - Diagnóstico')),
      body: ListenableBuilder(
        listenable: c,
        builder: (_, __) {
          final s = c.stats;
          final spots = c.chartSpots();
          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Expanded(child: TextField(controller: hostCtl, decoration: const InputDecoration(labelText: 'Alvo (IP/host)'))),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: c.windowMin,
                items: [for (final m in StabilityController.windowOptionsMin) DropdownMenuItem(value: m, child: Text('$m min'))],
                onChanged: (v) => c.windowMin = v!,
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (c.running) { await c.stop(); } else {
                  final ok = await c.start(hostCtl.text.trim());
                  if (!ok) setState(() => msg = 'Falha ao iniciar o serviço');
                }
              },
              child: Text(c.running ? 'Parar monitoramento' : 'Iniciar monitoramento'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Perda', '${s.lossPct.toStringAsFixed(1)}%'),
              _chip('RTT atual', s.current == null ? 'timeout' : '${s.current!.toStringAsFixed(1)} ms'),
              _chip('RTT médio', s.avg == null ? '-' : '${s.avg!.toStringAsFixed(1)} ms'),
              _chip('Jitter', '${s.jitter.toStringAsFixed(1)} ms'),
              _chip('Desconexões', '${s.disconnects}'),
              _chip('Amostras', '${s.sent}'),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: spots.length < 2
                  ? const Center(child: Text('Aguardando amostras...'))
                  : LineChart(
                      duration: Duration.zero,
                      LineChartData(
                        minY: 0,
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        lineBarsData: [
                          LineChartBarData(spots: spots, isCurved: false, barWidth: 2, dotData: const FlDotData(show: false)),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 32),
            Row(children: [
              Expanded(child: TextField(controller: osCtl, decoration: const InputDecoration(labelText: 'OS'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: techCtl, decoration: const InputDecoration(labelText: 'Técnico'))),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.photo_camera), label: const Text('Foto com marca d\'água + GPS')),
            if (msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!, style: const TextStyle(fontSize: 12))),
            if (photo != null) Padding(padding: const EdgeInsets.only(top: 8), child: Image.file(photo!)),
          ]);
        },
      ),
    );
  }

  Widget _chip(String k, String v) => Chip(label: Text('$k: $v'));
}
