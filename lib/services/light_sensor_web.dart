import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

typedef LightLevelCallback = void Function(double lux);

/// Browser ambient light reader for Flutter Web.
///
/// Strategy 1: AmbientLightSensor API (Chrome 79+ with
/// #enable-generic-sensor-extra-classes flag, or HTTPS context).
/// Strategy 2: Camera-based lux estimation — captures video frames from
/// the front camera and computes average brightness as a lux proxy.
///
/// The lux value is approximate, not a calibrated instrument. It is real
/// device-derived input suitable for environmental sensor fusion research.
class AmbientLightReader {
  JSObject? _sensor;
  Timer? _timer;
  web.MediaStream? _cameraStream;
  web.HTMLCanvasElement? _canvas;
  web.HTMLVideoElement? _video;
  bool _usingSensor = false;

  Future<bool> start(LightLevelCallback onLevel) async {
    stop();

    // ── Strategy 1: AmbientLightSensor API ──────────────────────────
    try {
      if (web.window.has('AmbientLightSensor')) {
        final ctor = web.window.getProperty<JSFunction>('AmbientLightSensor'.toJS);
        final sensor = ctor.callAsConstructor<JSObject>();
        sensor.callMethod(
          'addEventListener'.toJS,
          'reading'.toJS,
          ((JSAny? _) {
            final lux =
                sensor.getProperty<JSNumber?>('illuminance'.toJS)?.toDartDouble ?? 0;
            onLevel(lux.clamp(0, 100000));
          }).toJS,
        );
        sensor.callMethod('start'.toJS);
        _sensor = sensor;
        _usingSensor = true;
        return true;
      }
    } catch (_) {
      // AmbientLightSensor not available — try camera fallback.
    }

    // ── Strategy 2: Camera brightness estimation ────────────────────
    try {
      final constraints = {
        'video': {
          'facingMode': 'environment',
          'width': {'ideal': 64},
          'height': {'ideal': 64},
        },
        'audio': false,
      }.jsify() as web.MediaStreamConstraints;

      _cameraStream =
          await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

      _video = (web.document.createElement('video') as web.HTMLVideoElement)
        ..autoplay = true
        ..muted = true
        ..srcObject = _cameraStream
        ..style.display = 'none';
      web.document.body?.append(_video!);
      await _video!.play().toDart;

      _canvas = (web.document.createElement('canvas') as web.HTMLCanvasElement)
        ..width = 32
        ..height = 32;

      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (_video == null || _canvas == null) return;
        final ctx = _canvas!.getContext('2d') as web.CanvasRenderingContext2D;
        ctx.drawImage(_video!, 0, 0, 32, 32);
        final data = ctx.getImageData(0, 0, 32, 32).data.toDart;

        double totalBrightness = 0;
        int pixelCount = 0;
        for (int i = 0; i < data.length; i += 4) {
          final r = data[i];
          final g = data[i + 1];
          final b = data[i + 2];
          // Perceived brightness (ITU-R BT.709)
          totalBrightness += 0.2126 * r + 0.7152 * g + 0.0722 * b;
          pixelCount++;
        }

        final avgBrightness = totalBrightness / pixelCount; // 0–255
        // Map 0–255 brightness to approximate lux range (0–1000).
        // This is a rough logarithmic mapping suitable for mood analysis.
        final lux = (avgBrightness / 255.0) * 1000.0;
        onLevel(lux.clamp(0, 100000));
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;

    if (_usingSensor && _sensor != null) {
      try {
        _sensor!.callMethod('stop'.toJS);
      } catch (_) {}
      _sensor = null;
      _usingSensor = false;
    }

    for (final track in _cameraStream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _cameraStream = null;

    _video?.remove();
    _video = null;
    _canvas = null;
  }
}
