import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class WatermarkData {
  const WatermarkData({
    required this.osId, required this.techId, required this.when,
    required this.lat, required this.lon, required this.accuracyM, required this.altitudeM,
  });
  final String osId, techId;
  final DateTime when;
  final double lat, lon, accuracyM, altitudeM;
}

class _Job {
  _Job(this.bytes, this.data, this.maxWidth, this.quality);
  final Uint8List bytes;
  final WatermarkData data;
  final int maxWidth, quality;
}

class WatermarkService {
  /// Uso:
  ///   final shot = await ImagePicker().pickImage(source: ImageSource.camera);
  ///   final pos  = await LocationService.capture();
  ///   final file = await WatermarkService.stampAndSave(
  ///     sourcePath: shot!.path,
  ///     data: WatermarkData(osId: '12345', techId: 'T-07', when: DateTime.now(),
  ///       lat: pos.latitude, lon: pos.longitude, accuracyM: pos.accuracy, altitudeM: pos.altitude));
  static Future<File> stampAndSave({
    required String sourcePath,
    required WatermarkData data,
    int maxWidth = 1600,
    int jpgQuality = 88,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    // decode/resize/encode de foto de 12+ MP trava a UI: roda em isolate.
    final out = await compute(_render, _Job(bytes, data, maxWidth, jpgQuality));

    final base = await getApplicationDocumentsDirectory(); // não exige permissão de armazenamento
    final dir = Directory('${base.path}/evidencias');
    await dir.create(recursive: true);
    final name = 'OS${data.osId}_${DateFormat('yyyyMMdd_HHmmss').format(data.when)}.jpg';
    return File('${dir.path}/$name').writeAsBytes(out, flush: true);
    // Para aparecer na galeria: pacote `gal` -> Gal.putImage(file.path)
  }
}

Uint8List _render(_Job j) {
  var image = img.decodeImage(j.bytes);
  if (image == null) throw const FormatException('Imagem inválida');

  image = img.bakeOrientation(image); // aplica a rotação do EXIF antes de desenhar
  if (image.width > j.maxWidth) {
    image = img.copyResize(image, width: j.maxWidth, interpolation: img.Interpolation.average);
  }

  final d = j.data;
  // As fontes bitmap embutidas (arial14/24/48) só cobrem ASCII: sem acentos/ç nas linhas.
  final lines = <String>[
    'OS: ${d.osId}   TEC: ${d.techId}',
    DateFormat('dd/MM/yyyy HH:mm:ss').format(d.when),
    'LAT ${d.lat.toStringAsFixed(6)}  LON ${d.lon.toStringAsFixed(6)}',
    'Precisao ${d.accuracyM.toStringAsFixed(0)} m   Alt ${d.altitudeM.toStringAsFixed(0)} m',
  ];

  final font = img.arial24;
  const lineH = 30, pad = 12;
  final bannerH = lines.length * lineH + pad * 2;
  final top = image.height - bannerH;

  img.fillRect(image,
      x1: 0, y1: top, x2: image.width, y2: image.height,
      color: img.ColorRgba8(0, 0, 0, 170));

  for (var i = 0; i < lines.length; i++) {
    img.drawString(image, lines[i],
        font: font, x: pad, y: top + pad + i * lineH,
        color: img.ColorRgb8(255, 255, 255));
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: j.quality));
}
