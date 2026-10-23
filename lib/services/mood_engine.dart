import 'package:auramind/models/auramind_models.dart';

// Navigation guide:
//  [1] Mood scoring and classification rules
//  [2] Alert condition extraction for rule-based warnings

class MoodEngine {
  static MoodReading predict(
    SensorData d, {
    ComfortProfile profile = const ComfortProfile(),
    double lightLux = -1,
  }) {
    double score = 100;
    final issues = <String>[];

    if (d.temperature < profile.minTemperature - 4) {
      score -= 45;
      issues.add('very cold');
    } else if (d.temperature < profile.minTemperature - 2) {
      score -= 30;
      issues.add('too cold');
    } else if (d.temperature < profile.minTemperature) {
      score -= 15;
      issues.add('slightly cold');
    } else if (d.temperature > profile.maxTemperature + 6) {
      score -= 60;
      issues.add('dangerously hot');
    } else if (d.temperature > profile.maxTemperature + 3) {
      score -= 45;
      issues.add('very hot');
    } else if (d.temperature > profile.maxTemperature + 1) {
      score -= 30;
      issues.add('too warm');
    } else if (d.temperature > profile.maxTemperature) {
      score -= 15;
      issues.add('slightly warm');
    }

    if (d.humidity < profile.minHumidity - 15) {
      score -= 35;
      issues.add('very dry');
    } else if (d.humidity < profile.minHumidity - 10) {
      score -= 25;
      issues.add('air too dry');
    } else if (d.humidity < profile.minHumidity) {
      score -= 12;
      issues.add('slightly dry');
    } else if (d.humidity > profile.maxHumidity + 15) {
      score -= 35;
      issues.add('very humid');
    } else if (d.humidity > profile.maxHumidity + 10) {
      score -= 25;
      issues.add('air too humid');
    } else if (d.humidity > profile.maxHumidity) {
      score -= 12;
      issues.add('slightly humid');
    }

    // ── Light intensity scoring ──────────────────────────────────
    if (lightLux >= 0) {
      if (lightLux < profile.minLight * 0.3) {
        score -= 18;
        issues.add('very dim');
      } else if (lightLux < profile.minLight) {
        score -= 8;
        issues.add('slightly dim');
      } else if (lightLux > profile.maxLight * 1.5) {
        score -= 15;
        issues.add('glaring light');
      } else if (lightLux > profile.maxLight) {
        score -= 6;
        issues.add('slightly bright');
      }
    }

    score = score.clamp(0, 100);

    if (score >= 85) {
      return MoodReading(
        mood: 'Calm',
        confidence: score,
        level: MoodLevel.excellent,
        description:
            issues.isEmpty ? 'Optimal environment' : 'Good conditions overall',
        timestamp: d.timestamp,
      );
    }
    if (score >= 70) {
      return MoodReading(
        mood: 'Content',
        confidence: score,
        level: MoodLevel.good,
        description: issues.isEmpty ? 'Comfortable' : 'Minor: ${issues.first}',
        timestamp: d.timestamp,
      );
    }
    if (score >= 50) {
      return MoodReading(
        mood: 'Neutral',
        confidence: score,
        level: MoodLevel.neutral,
        description: issues.isNotEmpty
            ? 'Notice: ${issues.join(', ')}'
            : 'Moderate conditions',
        timestamp: d.timestamp,
      );
    }
    if (score >= 30) {
      return MoodReading(
        mood: 'Uneasy',
        confidence: score,
        level: MoodLevel.low,
        description: issues.isNotEmpty
            ? 'Issues: ${issues.join(', ')}'
            : 'Poor conditions',
        timestamp: d.timestamp,
      );
    }
    return MoodReading(
      mood: 'Stressed',
      confidence: score,
      level: MoodLevel.veryLow,
      description: issues.isNotEmpty
          ? 'Critical: ${issues.join(', ')}'
          : 'Very poor environment',
      timestamp: d.timestamp,
    );
  }

  /// Returns the alert conditions currently active. Each carries a stable
  /// `key` (for example "humidity_high") so the caller can tell whether a
  /// condition is the same one already showing, rather than a new occurrence.
  static List<({String key, AlertItem item})> checkAlerts(
    SensorData d, {
    ComfortProfile profile = const ComfortProfile(),
    double lightLux = -1,
  }) {
    final out = <({String key, AlertItem item})>[];
    final now = DateTime.now();

    if (d.temperature > profile.maxTemperature + 2) {
      out.add((
        key: 'temp_high',
        item: AlertItem(
          key: 'temp_high',
          title: 'High temperature',
          message:
              'Room is ${d.temperature.toStringAsFixed(1)}°C - above your comfort range.',
          severity: AlertSeverity.danger,
          timestamp: now,
        ),
      ));
    } else if (d.temperature < profile.minTemperature - 2) {
      out.add((
        key: 'temp_low',
        item: AlertItem(
          key: 'temp_low',
          title: 'Low temperature',
          message:
              'Room is ${d.temperature.toStringAsFixed(1)}°C - below your comfort range.',
          severity: AlertSeverity.warning,
          timestamp: now,
        ),
      ));
    }

    if (d.humidity > profile.maxHumidity) {
      out.add((
        key: 'humidity_high',
        item: AlertItem(
          key: 'humidity_high',
          title: 'High humidity',
          message:
              'Humidity at ${d.humidity.toStringAsFixed(0)}% - above your comfort range.',
          severity: AlertSeverity.warning,
          timestamp: now,
        ),
      ));
    } else if (d.humidity < profile.minHumidity) {
      out.add((
        key: 'humidity_low',
        item: AlertItem(
          key: 'humidity_low',
          title: 'Low humidity',
          message:
              'Humidity at ${d.humidity.toStringAsFixed(0)}% - below your comfort range.',
          severity: AlertSeverity.warning,
          timestamp: now,
        ),
      ));
    }

    // ── Light intensity alerts ───────────────────────────────────
    if (lightLux >= 0) {
      if (lightLux < profile.minLight * 0.3) {
        out.add((
          key: 'light_low',
          item: AlertItem(
            key: 'light_low',
            title: 'Very low light',
            message:
                'Light is ${lightLux.toStringAsFixed(0)} lux — well below your ${profile.minLight.toStringAsFixed(0)} lux minimum. Dim environments can affect mood and alertness.',
            severity: AlertSeverity.warning,
            timestamp: now,
          ),
        ));
      } else if (lightLux > profile.maxLight * 1.5) {
        out.add((
          key: 'light_high',
          item: AlertItem(
            key: 'light_high',
            title: 'Glaring light',
            message:
                'Light is ${lightLux.toStringAsFixed(0)} lux — well above your ${profile.maxLight.toStringAsFixed(0)} lux limit. Excessive brightness can cause eye strain and discomfort.',
            severity: AlertSeverity.warning,
            timestamp: now,
          ),
        ));
      }
    }

    return out;
  }

  /// Builds a prioritised action plan by reverse-engineering the scoring
  /// penalties applied by [predict]. Each gap between current conditions
  /// and the comfort profile becomes a recovery step, ranked by impact.
  static ActionPlan buildActionPlan(
    SensorData data, {
    ComfortProfile profile = const ComfortProfile(),
    double soundDb = 0,
    double lightLux = -1,
    String place = 'Home',
    int minutesAtPlace = 0,
    List<InterventionRecord> history = const [],
    List<SensorData> recentReadings = const [],
  }) {
    final mood = predict(data, profile: profile, lightLux: lightLux);
    final steps = <ActionStep>[];
    int stepId = 0;

    // ── Temperature gap ─────────────────────────────────────────
    if (data.temperature > profile.maxTemperature + 2) {
      const impact = 20.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Cool down your space',
        description: 'It\'s ${data.temperature.toStringAsFixed(1)}°C — '
            '${place == "Home" ? "turn on a fan or open a window" : "move to a cooler spot"}. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 10,
        trigger: 'temp',
        successCount: _effectiveness(history, 'temp').$1,
        totalCount: _effectiveness(history, 'temp').$2,
      ));
    } else if (data.temperature > profile.maxTemperature) {
      const impact = 8.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Cool down a little',
        description: 'Temperature is ${data.temperature.toStringAsFixed(1)}°C — '
            'slightly above your comfort zone. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'temp',
      ));
    } else if (data.temperature < profile.minTemperature - 2) {
      const impact = 25.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Warm up your space',
        description: 'It\'s ${data.temperature.toStringAsFixed(1)}°C — '
            '${place == "Home" ? "put on a layer or adjust heating" : "head somewhere warmer"}. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 10,
        trigger: 'temp',
      ));
    } else if (data.temperature < profile.minTemperature) {
      const impact = 10.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Warm up a little',
        description: 'Temperature is ${data.temperature.toStringAsFixed(1)}°C — '
            'a bit below your comfort zone. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'temp',
      ));
    }

    // ── Humidity gap ─────────────────────────────────────────────
    if (data.humidity > profile.maxHumidity + 10) {
      const impact = 20.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Reduce humidity',
        description: 'Humidity is ${data.humidity.toStringAsFixed(0)}% — '
            '${place == "Home" ? "open windows for cross-ventilation" : "move to a drier area"}. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 15,
        trigger: 'humidity',
      ));
    } else if (data.humidity > profile.maxHumidity) {
      const impact = 8.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Improve air flow',
        description: 'Humidity at ${data.humidity.toStringAsFixed(0)}% — '
            'slightly above your comfort range. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'humidity',
      ));
    } else if (data.humidity < profile.minHumidity - 10) {
      const impact = 20.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Add moisture to the air',
        description: 'Air is very dry at ${data.humidity.toStringAsFixed(0)}%. '
            'A damp towel or bowl of water nearby can help. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'humidity',
      ));
    } else if (data.humidity < profile.minHumidity) {
      const impact = 8.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Add a little moisture',
        description: 'Humidity at ${data.humidity.toStringAsFixed(0)}% — '
            'slightly below your comfort range. '
            '${_impactPhrase(impact, mood.confidence)}',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'humidity',
      ));
    }

    // ── Sound gap ───────────────────────────────────────────────
    if (soundDb > profile.maxSound) {
      const impact = 12.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Reduce noise',
        description: 'Sound is ${soundDb.toStringAsFixed(0)} dB — '
            'above your ${profile.maxSound.toStringAsFixed(0)} dB limit. '
            '${place == "Home" ? "Close the window or door" : "Try headphones or a quieter spot"}.',
        estimatedImpact: impact,
        estimatedMinutes: 2,
        trigger: 'sound',
      ));
    }

    // ── Light gap ──────────────────────────────────────────────
    if (lightLux >= 0) {
      if (lightLux < profile.minLight * 0.3) {
        const impact = 18.0;
        steps.add(ActionStep(
          id: 'ap_${stepId++}',
          title: 'Brighten your environment',
          description: 'Light is ${lightLux.toStringAsFixed(0)} lux — '
              'very dim for your comfort range. '
              '${place == "Home" ? "Open curtains or turn on a lamp" : "Move closer to a window or lit area"}. '
              '${_impactPhrase(impact, mood.confidence)}',
          estimatedImpact: impact,
          estimatedMinutes: 2,
          trigger: 'light',
          successCount: _effectiveness(history, 'light').$1,
          totalCount: _effectiveness(history, 'light').$2,
        ));
      } else if (lightLux < profile.minLight) {
        const impact = 8.0;
        steps.add(ActionStep(
          id: 'ap_${stepId++}',
          title: 'Add a little light',
          description: 'Light at ${lightLux.toStringAsFixed(0)} lux — '
              'slightly dim for comfort. '
              '${_impactPhrase(impact, mood.confidence)}',
          estimatedImpact: impact,
          estimatedMinutes: 2,
          trigger: 'light',
        ));
      } else if (lightLux > profile.maxLight * 1.5) {
        const impact = 15.0;
        steps.add(ActionStep(
          id: 'ap_${stepId++}',
          title: 'Reduce glare',
          description: 'Light is ${lightLux.toStringAsFixed(0)} lux — '
              'very bright. '
              '${place == "Home" ? "Close blinds or adjust lamps" : "Move to a shaded area"}. '
              '${_impactPhrase(impact, mood.confidence)}',
          estimatedImpact: impact,
          estimatedMinutes: 2,
          trigger: 'light',
        ));
      } else if (lightLux > profile.maxLight) {
        const impact = 6.0;
        steps.add(ActionStep(
          id: 'ap_${stepId++}',
          title: 'Soften the lighting',
          description: 'Light at ${lightLux.toStringAsFixed(0)} lux — '
              'slightly above comfort range. '
              '${_impactPhrase(impact, mood.confidence)}',
          estimatedImpact: impact,
          estimatedMinutes: 2,
          trigger: 'light',
        ));
      }
    }

    // ── Sedentary break ─────────────────────────────────────────
    if (minutesAtPlace >= 45 && place != 'Outdoors') {
      const impact = 4.0;
      steps.add(ActionStep(
        id: 'ap_${stepId++}',
        title: 'Take a short break',
        description: 'You\'ve been at ${place.toLowerCase()} for '
            '$minutesAtPlace min. A 5-minute walk or stretch can help.',
        estimatedImpact: impact,
        estimatedMinutes: 5,
        trigger: 'sedentary',
      ));
    }

    // ── Coping steps: mood-aware, tiered by current score ───────
    // Each condition has 3 tiers:
    //   good  (score >= 70): still managing — light nudge
    //   low   (score >= 50): starting to struggle — active technique
    //   critical (score < 50): environment is actively harming — urgent action

    if (data.temperature > profile.maxTemperature + 2) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Stay ahead of the heat';
        desc = "You're managing well despite the temperature. "
            'Sip cold water and keep air moving — your comfort score is still good.';
        impact = 5.0;
      } else if (mood.confidence >= 50) {
        title = 'Cool yourself down';
        desc = 'The heat is starting to affect you. Run cold water over '
            'your wrists for 30 seconds and slow your breathing: '
            '4 counts in, 6 counts out.';
        impact = 8.0;
      } else {
        title = 'Heat is critically affecting your mood';
        desc = 'Your environment score is low and heat is a major cause. '
            'Leave this space if you can — even 5 minutes somewhere cooler '
            'will measurably improve how you feel.';
        impact = 14.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: impact > 10 ? 5 : 2,
        trigger: 'cope_temp', isCoping: true,
      ));
    } else if (data.temperature < profile.minTemperature - 2) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Keep the cold in check';
        desc = "You're coping fine. Add a layer if you have one — "
            'staying warm helps maintain focus and energy.';
        impact = 5.0;
      } else if (mood.confidence >= 50) {
        title = 'Warm up your body';
        desc = 'The cold is dragging your score down. Rub your palms together '
            'briskly, roll your shoulders back, and take a few deep breaths '
            'to get circulation going.';
        impact = 8.0;
      } else {
        title = 'Cold is critically affecting your mood';
        desc = 'Your score is low and the cold environment is a significant cause. '
            'Move somewhere warmer as soon as you can — this is not a good '
            'space to stay in right now.';
        impact = 14.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: impact > 10 ? 5 : 2,
        trigger: 'cope_temp', isCoping: true,
      ));
    }

    if (soundDb > profile.maxSound) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Noise is elevated';
        desc = 'Still managing well. Headphones or a white noise app can '
            'help you stay in the zone.';
        impact = 4.0;
      } else if (mood.confidence >= 50) {
        title = 'Anchor your focus';
        desc = 'The noise is affecting you. Try the 5-4-3-2-1 grounding: '
            'name 5 things you see, 4 you can touch, 3 you hear, '
            '2 you smell, 1 you taste. Shifts attention off the noise.';
        impact = 7.0;
      } else {
        title = 'Noise is overwhelming your focus';
        desc = 'Your score is critically low and noise is a key trigger. '
            'You need either isolation (headphones + lofi) or a quieter '
            'space — staying here without intervention will keep your '
            'mood suppressed.';
        impact = 11.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: 2,
        trigger: 'cope_sound', isCoping: true,
      ));
    }

    if (lightLux >= 0 && lightLux < profile.minLight * 0.3) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Light is low';
        desc = "You're still doing well. Turn on an overhead light or "
            'move closer to a window to keep your energy up.';
        impact = 4.0;
      } else if (mood.confidence >= 50) {
        title = 'Counter the dim-environment fatigue';
        desc = 'Low light is dulling your alertness. Look at the brightest '
            'point in the room for 20 seconds (not a screen), then '
            'sit up straight — light + posture together help reset your state.';
        impact = 7.0;
      } else {
        title = 'Dim light is significantly affecting your mood';
        desc = 'Your score is low and the lack of light is a major factor. '
            'Get natural light exposure immediately if possible — '
            'even stepping outside for 2 minutes makes a measurable difference.';
        impact = 12.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: impact > 10 ? 5 : 1,
        trigger: 'cope_light', isCoping: true,
      ));
    } else if (lightLux >= 0 && lightLux > profile.maxLight * 1.5) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Glare is high';
        desc = 'Still coping fine. Try angling your screen or closing a blind '
            'to reduce eye strain before it builds up.';
        impact = 3.0;
      } else if (mood.confidence >= 50) {
        title = 'Reduce eye strain now';
        desc = 'The brightness is wearing you down. Use the 20-20-20 rule: '
            'every 20 minutes, look at something 20 feet away for 20 seconds. '
            'Blink slowly 10 times to rehydrate your eyes.';
        impact = 6.0;
      } else {
        title = 'Glare is draining your energy';
        desc = 'Your score is low and excessive brightness is a cause. '
            'Move to a shaded spot or dim the room — your eyes and '
            'mood will both recover faster with reduced light exposure.';
        impact = 10.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: 1,
        trigger: 'cope_light', isCoping: true,
      ));
    }

    if (data.humidity > profile.maxHumidity + 10) {
      final String title;
      final String desc;
      final double impact;
      if (mood.confidence >= 70) {
        title = 'Humidity is high';
        desc = "You're managing. Breathe through your nose — it conditions "
            'humid air better than mouth breathing.';
        impact = 3.0;
      } else if (mood.confidence >= 50) {
        title = 'Ease the humidity discomfort';
        desc = 'Humidity is pulling your score down. Slow nasal breathing '
            'and a cold compress on your neck can meaningfully reduce '
            'how oppressive the air feels.';
        impact = 6.0;
      } else {
        title = 'Humidity is critically uncomfortable';
        desc = 'Your score is low and the humid air is a significant cause. '
            'This environment is not sustainable for focus or wellbeing — '
            'move somewhere drier as soon as possible.';
        impact = 10.0;
      }
      steps.add(ActionStep(
        id: 'ap_\${stepId++}', title: title, description: desc,
        estimatedImpact: impact, estimatedMinutes: 2,
        trigger: 'cope_humidity', isCoping: true,
      ));
    }

    // Sort: environmental fixes first (by impact), then coping steps (by impact)
    final envSteps = steps.where((s) => !s.isCoping).toList()
      ..sort((a, b) => b.estimatedImpact.compareTo(a.estimatedImpact));
    final copeSteps = steps.where((s) => s.isCoping).toList()
      ..sort((a, b) => b.estimatedImpact.compareTo(a.estimatedImpact));
    steps
      ..clear()
      ..addAll(envSteps)
      ..addAll(copeSteps);

    // Detect patterns from recent readings
    final pattern = _detectPattern(recentReadings, profile);

    final totalImpact = steps.fold(0.0, (s, e) => s + e.estimatedImpact);
    final estimated = (mood.confidence + totalImpact).clamp(0.0, 100.0);

    return ActionPlan(
      steps: steps,
      currentScore: mood.confidence,
      estimatedScore: estimated,
      patternInsight: pattern,
    );
  }

  static String _impactPhrase(double impact, double current) {
    final after = (current + impact).clamp(0, 100).toStringAsFixed(0);
    return 'Could bring your score to ~$after%.';
  }

  /// Rough success rate for a trigger type based on completed intervention records.
  static (int, int) _effectiveness(List<InterventionRecord> history, String trigger) {
    // Match interventions whose message mentions the trigger keyword.
    final related = history.where((r) {
      final msg = r.message.toLowerCase();
      switch (trigger) {
        case 'temp': return msg.contains('temp') || msg.contains('cool') || msg.contains('warm') || msg.contains('heat');
        case 'humidity': return msg.contains('humid') || msg.contains('dry') || msg.contains('moisture');
        case 'light': return msg.contains('light') || msg.contains('bright') || msg.contains('dim') || msg.contains('glare');
        default: return false;
      }
    }).toList();
    if (related.isEmpty) return (0, 0);
    final successes = related.where((r) =>
        r.isComplete && r.scoreDelta != null && r.scoreDelta! > 0).length;
    return (successes, related.length);
  }

  /// Looks for repeating conditions in recent readings and returns
  /// a human-readable insight based on tracked sensors only.
  static String? _detectPattern(
      List<SensorData> readings, ComfortProfile profile) {
    if (readings.length < 10) return null;

    // Check for time-of-day temperature spikes
    final hourTemp = <int, List<double>>{};
    for (final r in readings) {
      hourTemp.putIfAbsent(r.timestamp.hour, () => []).add(r.temperature);
    }
    for (final entry in hourTemp.entries) {
      if (entry.value.length >= 3) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        if (avg > profile.maxTemperature) {
          return 'Cooling the environment may help reduce discomfort. '
              'Try using a fan, improving ventilation, or moving to a cooler area.';
        }
      }
    }

    // Check for recurring high humidity in afternoons
    final afternoonHumidity = readings
        .where((r) => r.timestamp.hour >= 13 && r.timestamp.hour <= 17)
        .map((r) => r.humidity)
        .toList();
    if (afternoonHumidity.length >= 5) {
      final avg = afternoonHumidity.reduce((a, b) => a + b) / afternoonHumidity.length;
      if (avg > profile.maxHumidity) {
        return 'Humidity has been repeatedly above your comfort range. '
            'Improving ventilation or moving to a drier area may help.';
      }
    }

    return null;
  }
}