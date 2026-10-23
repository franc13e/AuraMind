import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef SoundLevelCallback = void Function(double db);

/// Browser microphone noise reader for Flutter Web.
///
/// This asks the browser for microphone permission and converts the live audio
/// waveform RMS into an approximate 20–100 dB-style indicator. This is not a
/// calibrated sound meter, but it is real microphone-derived input.
class MicrophoneNoiseReader {
  web.MediaStream? _stream;
  web.AudioContext? _audioContext;
  Timer? _timer;

  Future<bool> start(SoundLevelCallback onLevel) async {
    stop();

    final constraints =
        {'audio': true, 'video': false}.jsify() as web.MediaStreamConstraints;
    _stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

    final audioContext = web.AudioContext();
    final source = audioContext.createMediaStreamSource(_stream!);
    final analyser = audioContext.createAnalyser()..fftSize = 2048;
    source.connect(analyser);
    _audioContext = audioContext;

    final bufferLength = analyser.fftSize;
    final dataArray = Float32List(bufferLength).toJS;

    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      analyser.getFloatTimeDomainData(dataArray);
      final samples = dataArray.toDart;
      double sumSq = 0;
      for (int i = 0; i < bufferLength; i++) {
        final v = samples[i];
        sumSq += v * v;
      }
      final rms = sqrt(sumSq / bufferLength);
      final dbfs = 20 * (log(rms.clamp(1e-8, 1.0)) / ln10);
      final db = (dbfs + 100).clamp(20.0, 100.0).toDouble();
      onLevel(db);
    });

    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    for (final track in _stream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
    try {
      _audioContext?.close();
    } catch (_) {}
    _audioContext = null;
  }
}
