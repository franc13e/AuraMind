import 'dart:async';
import 'package:auramind/models/auramind_models.dart';

// Demo Scenario Engine
// Provides scripted temperature, humidity, and sound sequences for lecturer demos.
// Light and CO2 are intentionally not included because this app version avoids
// simulated environmental sensors that are not actually tracked.

class DemoKeyframe {
  final int minuteOffset;
  final double temperature;
  final double humidity;
  final double soundDb;
  final String? label;

  const DemoKeyframe({
    required this.minuteOffset,
    required this.temperature,
    required this.humidity,
    this.soundDb = 42,
    this.label,
  });

  SensorData toSensorData(DateTime base) => SensorData(
        temperature: temperature,
        humidity: humidity,
        timestamp: base.add(Duration(minutes: minuteOffset)),
      );
}

class DemoScenario {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final List<DemoKeyframe> keyframes;
  final bool loop;

  const DemoScenario({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.keyframes,
    this.loop = false,
  });
}

class DemoScenarios {
  static const studyDecline = DemoScenario(
    id: 'study_decline',
    title: 'Study Session Decline',
    subtitle: 'Warm, humid room → mood drop',
    description:
        'Simulates a student studying over 60 minutes as temperature and humidity rise. '
        'The app alerts only when tracked conditions pass the comfort range.',
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 23.5, humidity: 55.0, soundDb: 38, label: 'Session starts — comfortable'),
      DemoKeyframe(minuteOffset: 15, temperature: 24.4, humidity: 60.0, soundDb: 40, label: 'Room slowly warming'),
      DemoKeyframe(minuteOffset: 30, temperature: 26.8, humidity: 68.0, soundDb: 42, label: 'Comfort range nearly reached'),
      DemoKeyframe(minuteOffset: 45, temperature: 29.7, humidity: 76.0, soundDb: 44, label: '⚠ Humidity and temperature rising'),
      DemoKeyframe(minuteOffset: 55, temperature: 31.5, humidity: 82.0, soundDb: 45, label: '🚨 Uncomfortable study environment'),
      DemoKeyframe(minuteOffset: 60, temperature: 29.2, humidity: 72.0, soundDb: 43, label: 'Ventilation/cooling started'),
    ],
  );

  static const effectiveIntervention = DemoScenario(
    id: 'effective_intervention',
    title: 'Successful Intervention',
    subtitle: 'Bad conditions → action → recovery',
    description:
        'Starts with a warm and humid environment. After the user follows the suggested reset, '
        'the tracked conditions improve.',
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 29.5, humidity: 72.0, soundDb: 68, label: '🚨 Poor starting conditions'),
      DemoKeyframe(minuteOffset: 5, temperature: 30.5, humidity: 76.0, soundDb: 70, label: 'Mood: Uneasy — reset suggested'),
      DemoKeyframe(minuteOffset: 15, temperature: 28.5, humidity: 68.0, soundDb: 55, label: 'User acts — cooling/airflow improved'),
      DemoKeyframe(minuteOffset: 25, temperature: 26.5, humidity: 62.0, soundDb: 45, label: 'Conditions improving'),
      DemoKeyframe(minuteOffset: 35, temperature: 24.5, humidity: 57.0, soundDb: 40, label: '✅ Mood: Content — recovery confirmed'),
    ],
  );

  static const clinicalEscalation = DemoScenario(
    id: 'clinical_escalation',
    title: 'Persistent Discomfort',
    subtitle: 'Unchanged conditions → review flag',
    description:
        'Environment stays uncomfortable despite alerts. This demonstrates escalation wording without medical diagnosis.',
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 31.0, humidity: 78.0, soundDb: 72, label: '🚨 Uncomfortable environment'),
      DemoKeyframe(minuteOffset: 20, temperature: 31.5, humidity: 80.0, soundDb: 74, label: 'No improvement'),
      DemoKeyframe(minuteOffset: 40, temperature: 32.0, humidity: 82.0, soundDb: 76, label: 'Sustained discomfort'),
      DemoKeyframe(minuteOffset: 60, temperature: 32.5, humidity: 85.0, soundDb: 78, label: '🏥 Suggested for review/support'),
    ],
  );

  // ── Presentation modes (loop until stopped) ──

  static const hotRoom = DemoScenario(
    id: 'hot_room',
    title: 'Hot Room',
    subtitle: '32°C · High humidity',
    description: 'Simulates a hot, humid environment. Holds until stopped.',
    loop: true,
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 32.5, humidity: 78.0, soundDb: 45, label: 'Hot environment active'),
      DemoKeyframe(minuteOffset: 5, temperature: 33.0, humidity: 80.0, soundDb: 44, label: 'Hot environment'),
      DemoKeyframe(minuteOffset: 10, temperature: 32.8, humidity: 79.0, soundDb: 46, label: 'Hot environment'),
    ],
  );

  static const coldRoom = DemoScenario(
    id: 'cold_room',
    title: 'Cold Room',
    subtitle: '16°C · Low humidity',
    description: 'Simulates a cold, dry environment. Holds until stopped.',
    loop: true,
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 16.0, humidity: 30.0, soundDb: 35, label: 'Cold environment active'),
      DemoKeyframe(minuteOffset: 5, temperature: 15.5, humidity: 28.0, soundDb: 34, label: 'Cold environment'),
      DemoKeyframe(minuteOffset: 10, temperature: 16.2, humidity: 31.0, soundDb: 36, label: 'Cold environment'),
    ],
  );

  static const noisyRoom = DemoScenario(
    id: 'noisy_room',
    title: 'Noisy Environment',
    subtitle: '75 dB · Normal temp',
    description: 'Simulates a loud environment with normal temperature. Holds until stopped.',
    loop: true,
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 24.0, humidity: 55.0, soundDb: 75, label: 'Noisy environment active'),
      DemoKeyframe(minuteOffset: 5, temperature: 24.2, humidity: 56.0, soundDb: 78, label: 'Noisy environment'),
      DemoKeyframe(minuteOffset: 10, temperature: 24.1, humidity: 55.5, soundDb: 76, label: 'Noisy environment'),
    ],
  );

  static const perfectRoom = DemoScenario(
    id: 'perfect_room',
    title: 'Perfect Conditions',
    subtitle: '23°C · 55% · Quiet',
    description: 'Simulates ideal study conditions. Holds until stopped.',
    loop: true,
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 23.0, humidity: 55.0, soundDb: 38, label: 'Perfect conditions active'),
      DemoKeyframe(minuteOffset: 5, temperature: 23.2, humidity: 54.0, soundDb: 36, label: 'Perfect conditions'),
      DemoKeyframe(minuteOffset: 10, temperature: 22.8, humidity: 55.5, soundDb: 37, label: 'Perfect conditions'),
    ],
  );

  static const worstCase = DemoScenario(
    id: 'worst_case',
    title: 'Worst Case',
    subtitle: '34°C · 85% · 80 dB',
    description: 'Everything bad at once. Holds until stopped.',
    loop: true,
    keyframes: [
      DemoKeyframe(minuteOffset: 0, temperature: 34.0, humidity: 85.0, soundDb: 80, label: 'Worst case active'),
      DemoKeyframe(minuteOffset: 5, temperature: 34.5, humidity: 86.0, soundDb: 82, label: 'Worst case'),
      DemoKeyframe(minuteOffset: 10, temperature: 34.2, humidity: 85.5, soundDb: 81, label: 'Worst case'),
    ],
  );

  static const all = [studyDecline, effectiveIntervention, clinicalEscalation,
      hotRoom, coldRoom, noisyRoom, perfectRoom, worstCase];
}

class DemoController {
  Timer? _timer;
  int _frameIndex = 0;
  bool _isPlaying = false;
  DemoScenario? _activeScenario;

  bool get isPlaying => _isPlaying;
  DemoScenario? get activeScenario => _activeScenario;

  void play({
    required DemoScenario scenario,
    required void Function(SensorData data, double soundDb) onFrame,
    void Function(String label)? onLabel,
    void Function()? onDone,
    int tickSeconds = 2,
  }) {
    stop();
    _activeScenario = scenario;
    _isPlaying = true;
    _frameIndex = 0;

    final base = DateTime.now();
    final frames = scenario.keyframes;

    _timer = Timer.periodic(Duration(seconds: tickSeconds), (t) {
      if (_frameIndex >= frames.length) {
        if (scenario.loop) {
          _frameIndex = 0;
        } else {
          stop();
          onDone?.call();
          return;
        }
      }

      final frame = frames[_frameIndex];
      final data = _frameIndex == 0
          ? frame.toSensorData(base)
          : _interpolate(frames[_frameIndex - 1], frame, 0.5, base);

      onFrame(data, frame.soundDb);
      if (frame.label != null) onLabel?.call(frame.label!);
      _frameIndex++;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPlaying = false;
    _activeScenario = null;
    _frameIndex = 0;
  }

  SensorData _interpolate(DemoKeyframe a, DemoKeyframe b, double t, DateTime base) {
    double lerp(double x, double y) => x + (y - x) * t;
    final offsetMins = (a.minuteOffset + (b.minuteOffset - a.minuteOffset) * t).round();
    return SensorData(
      temperature: lerp(a.temperature, b.temperature),
      humidity: lerp(a.humidity, b.humidity),
      timestamp: base.add(Duration(minutes: offsetMins)),
    );
  }
}
