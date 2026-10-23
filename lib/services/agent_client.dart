// lib/services/agent_client.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:auramind/config.dart';
import 'package:auramind/models/auramind_models.dart';

// Navigation guide:
//  [1] Agent action and history DTOs
//  [2] Backend API calls to snapshot, feedback, history, and report

class AgentAction {
  final String? id;
  final String tool;
  final Map<String, dynamic> args;
  AgentAction({this.id, required this.tool, required this.args});

  factory AgentAction.fromJson(Map<String, dynamic> j) => AgentAction(
        id: j['id'] as String?,
        tool: j['tool'] as String,
        args: Map<String, dynamic>.from(j['args'] as Map),
      );
}

/// One stored reading returned by /history.
class HistoryPoint {
  final DateTime ts;
  final String moodLevel;
  final double moodScore;
  final double temperature;
  final double humidity;
  final double sound;
  HistoryPoint({
    required this.ts, required this.moodLevel, required this.moodScore,
    required this.temperature, required this.humidity,
    required this.sound,
  });

  factory HistoryPoint.fromJson(Map<String, dynamic> j) => HistoryPoint(
        ts: DateTime.parse(j['ts'] as String),
        moodLevel: j['mood_level'] as String? ?? 'neutral',
        moodScore: (j['mood_score'] as num?)?.toDouble() ?? 50,
        temperature: (j['temperature_c'] as num?)?.toDouble() ?? 0,
        humidity: (j['humidity_pct'] as num?)?.toDouble() ?? 0,
        sound: (j['sound_db'] as num?)?.toDouble() ?? 0,
      );
}

/// Aggregated report returned by /report.
class ReportData {
  final int days;
  final int readingCount;
  final double avgScore;
  final Map<String, int> distribution;
  final List<Map<String, dynamic>> interventions;
  ReportData({
    required this.days, required this.readingCount, required this.avgScore,
    required this.distribution, required this.interventions,
  });

  factory ReportData.fromJson(Map<String, dynamic> j) => ReportData(
        days: j['days'] as int? ?? 7,
        readingCount: j['reading_count'] as int? ?? 0,
        avgScore: (j['avg_score'] as num?)?.toDouble() ?? 0,
        distribution: Map<String, int>.from(j['distribution'] as Map? ?? {}),
        interventions: ((j['interventions'] as List?) ?? [])
            .cast<Map<String, dynamic>>(),
      );
}

class AgentClient {
  static const String _backendBase = apiBase;

  String patientId;
  String? _authToken;

  AgentClient({this.patientId = 'demo-patient'});

  /// Update the patient ID (called when user logs in).
  void setPatientId(String id) {
    patientId = id;
  }

  /// Set the auth token for authenticated requests.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Build headers with optional auth token.
  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_authToken != null) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  Future<List<AgentAction>> sendSnapshot(SensorData data, {
    required String place,
    required int minutesAtPlace,
    required String timeOfDay,
    required double soundDb,
  }) async {
    final body = {
      'patient_id': patientId,
      'place': place,
      'minutes_at_place': minutesAtPlace,
      'time_of_day': timeOfDay,
      'sound_db': soundDb,
      'temperature_c': data.temperature,
      'humidity_pct': data.humidity,
    };
    try {
      final res = await http.post(
        Uri.parse('$_backendBase/snapshot'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('Server error: ${res.statusCode}');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final actions = (json['actions'] as List).cast<Map<String, dynamic>>();
      return actions.map(AgentAction.fromJson).toList();
    } catch (e) {
      rethrow; // Let caller handle the error
    }
  }

  Future<void> saveLocation(String place) async {
    try {
      await http.post(
        Uri.parse('$_backendBase/location'),
        headers: _headers,
        body: jsonEncode({
          'patient_id': patientId,
          'place': place,
        }),
      ).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<String?> loadLocation() async {
    try {
      final res = await http.get(
        Uri.parse('$_backendBase/location/$patientId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final place = json['place'] as String?;
      return (place != null && place.isNotEmpty) ? place : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendFeedback({
    required String actionId,
    required String response,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendBase/feedback'),
        headers: _headers,
        body: jsonEncode({
          'patient_id': patientId,
          'action_id': actionId,
          'response': response,
        }),
      ).timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch stored readings for the last [hours] hours.
  Future<List<HistoryPoint>> fetchHistory({int hours = 24}) async {
    try {
      final res = await http.get(
        Uri.parse('$_backendBase/history?patient_id=$patientId&hours=$hours'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return ((json['readings'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(HistoryPoint.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch the aggregated report for the last [days] days.
  Future<ReportData?> fetchReport({int days = 7}) async {
    try {
      final res = await http.get(
        Uri.parse('$_backendBase/report?patient_id=$patientId&days=$days'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      return ReportData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
