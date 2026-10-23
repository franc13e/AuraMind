import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/services/mood_engine.dart';
import 'package:flutter_test/flutter_test.dart';

SensorData reading(double temperature, double humidity) =>
    SensorData(temperature: temperature, humidity: humidity, timestamp: DateTime(2026, 1, 1, 10));

void main() {
  group('MoodEngine.predict', () {
    test('comfortable conditions score higher than uncomfortable ones', () {
      final comfy = MoodEngine.predict(reading(24, 50), lightLux: 400);
      final hot = MoodEngine.predict(reading(35, 85), lightLux: 400);
      expect(comfy.confidence, greaterThan(hot.confidence));
      expect(comfy.level.index, greaterThan(hot.level.index));
    });

    test('uses the personal comfort profile', () {
      const tolerant = ComfortProfile(maxTemperature: 36);
      final strict = MoodEngine.predict(reading(31, 50), lightLux: 400);
      final relaxed = MoodEngine.predict(reading(31, 50), profile: tolerant, lightLux: 400);
      expect(relaxed.confidence, greaterThan(strict.confidence));
    });
  });

  group('MoodEngine.buildActionPlan', () {
    test('suggests an environment step when it is too hot', () {
      final plan = MoodEngine.buildActionPlan(reading(34, 50), lightLux: 400);
      expect(plan.steps.where((s) => !s.isCoping), isNotEmpty);
      expect(plan.estimatedScore, greaterThanOrEqualTo(plan.currentScore));
    });

    test('suggests nothing when conditions are within the comfort profile', () {
      final plan = MoodEngine.buildActionPlan(reading(24, 50), lightLux: 400);
      expect(plan.steps.where((s) => !s.isCoping), isEmpty);
    });

    test('flags loud environments', () {
      final quiet = MoodEngine.buildActionPlan(reading(24, 50), soundDb: 40, lightLux: 400);
      final loud = MoodEngine.buildActionPlan(reading(24, 50), soundDb: 85, lightLux: 400);
      expect(loud.steps.length, greaterThan(quiet.steps.length));
    });
  });
}
