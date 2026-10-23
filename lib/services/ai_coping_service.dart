import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/auramind_models.dart';

const _backendUrl = apiBase;

class AiCopingService {
  String? _lastKey;
  List<ActionStep>? _cache;

  List<String> buildConditionsPublic(
    SensorData s,
    ComfortProfile p,
    double soundDb,
    double lightLux,
  ) => _buildConditions(s, p, soundDb, lightLux);

  Future<List<ActionStep>> getCopingSteps({
    required SensorData sensor,
    required ComfortProfile profile,
    required double soundDb,
    required double lightLux,
  }) async {
    final conditions = _buildConditions(sensor, profile, soundDb, lightLux);
    if (conditions.isEmpty) return [];

    final key = conditions.join('|');
    if (key == _lastKey && _cache != null) return _cache!;

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/coping'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'conditions': conditions}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final data = jsonDecode(response.body);
      final rawSteps = data['steps'] as List;
      int id = 500;
      final steps = rawSteps.map((item) => ActionStep(
        id: 'ai_cope_${id++}',
        title: item['title'] as String,
        description: item['description'] as String,
        estimatedImpact: 8.0,
        estimatedMinutes: (item['minutes'] as num).toInt(),
        trigger: 'ai_coping',
        isCoping: true,
      )).toList();

      _lastKey = key;
      _cache = steps;
      return steps;
    } catch (e) {
      debugPrint('AiCopingService error: $e');
      return _fallback();
    }
  }

  List<String> _buildConditions(
    SensorData s,
    ComfortProfile p,
    double soundDb,
    double lightLux,
  ) {
    final c = <String>[];
    if (s.temperature > p.maxTemperature + 2) {
      c.add('too hot (${s.temperature.round()}°C, max ${p.maxTemperature.round()}°C)');
    }
    if (s.temperature < p.minTemperature - 2) {
      c.add('too cold (${s.temperature.round()}°C, min ${p.minTemperature.round()}°C)');
    }
    if (soundDb > p.maxSound) {
      c.add('too loud (${soundDb.round()} dB, limit ${p.maxSound.round()} dB)');
    }
    if (lightLux >= 0 && lightLux < p.minLight * 0.3) {
      c.add('very dim (${lightLux.round()} lux)');
    }
    if (lightLux >= 0 && lightLux > p.maxLight * 1.5) {
      c.add('glare (${lightLux.round()} lux)');
    }
    if (s.humidity > p.maxHumidity + 10) {
      c.add('very humid (${s.humidity.round()}%)');
    }
    return c;
  }

  List<ActionStep> _fallback() {
    int id = 500;
    return [
      ActionStep(
        id: 'fb_${id++}', title: 'Slow your breathing',
        description: 'Breathe in 4 counts, hold 2, out 6. Repeat 5 times.',
        estimatedImpact: 7, estimatedMinutes: 2,
        trigger: 'ai_coping', isCoping: true,
      ),
      ActionStep(
        id: 'fb_${id++}', title: 'Cool your wrists',
        description: 'Press something cool to your wrists for 20 seconds.',
        estimatedImpact: 6, estimatedMinutes: 1,
        trigger: 'ai_coping', isCoping: true,
      ),
      ActionStep(
        id: 'fb_${id++}', title: 'Focus anchor',
        description: 'Pick one nearby object and describe it mentally in full detail for 60 seconds.',
        estimatedImpact: 6, estimatedMinutes: 1,
        trigger: 'ai_coping', isCoping: true,
      ),
    ];
  }

  void invalidateCache() {
    _lastKey = null;
    _cache = null;
  }
}
