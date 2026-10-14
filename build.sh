#!/usr/bin/env bash
# Gera o projeto Flutter em ./app, aplica nosso código e compila o APK release.
set -euo pipefail
rm -rf app
flutter create --org br.isp --project-name ispfield --platforms android app
cd app
flutter pub add flutter_foreground_task dart_ping fl_chart geolocator image image_picker path_provider intl
rm -rf lib && cp -r ../lib lib
cp ../android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter build apk --release
echo "APK: $(pwd)/build/app/outputs/flutter-apk/app-release.apk"
