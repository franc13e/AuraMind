// Navigation guide:
//  [1] Domain models for sensor, mood, alerts, actions, and trend state

enum MoodLevel { veryLow, low, neutral, good, excellent }
enum AlertSeverity { info, warning, danger }
enum TrendMode { live, minutes, hours, week, month }

enum SelfMood { calm, good, neutral, uneasy, stressed }

extension SelfMoodLabel on SelfMood {
  String get label {
    switch (this) {
      case SelfMood.calm: return 'Calm';
      case SelfMood.good: return 'Good';
      case SelfMood.neutral: return 'Neutral';
      case SelfMood.uneasy: return 'Uneasy';
      case SelfMood.stressed: return 'Stressed';
    }
  }

  MoodLevel get level {
    switch (this) {
      case SelfMood.calm: return MoodLevel.excellent;
      case SelfMood.good: return MoodLevel.good;
      case SelfMood.neutral: return MoodLevel.neutral;
      case SelfMood.uneasy: return MoodLevel.low;
      case SelfMood.stressed: return MoodLevel.veryLow;
    }
  }
}

class MoodCheckIn {
  final SelfMood reportedMood;
  final MoodReading predictedMood;
  final SensorData sensorData;
  final DateTime timestamp;

  const MoodCheckIn({
    required this.reportedMood,
    required this.predictedMood,
    required this.sensorData,
    required this.timestamp,
  });

  int get difference =>
      (reportedMood.level.index - predictedMood.level.index).abs();

  bool get exactMatch => difference == 0;
  bool get closeMatch => difference <= 1;

  String get matchLabel {
    if (exactMatch) return 'Matched';
    if (closeMatch) return 'Close';
    return 'Needs review';
  }
}



class GeofencePlace {
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  const GeofencePlace({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  GeofencePlace copyWith({
    String? label,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    DateTime? createdAt,
  }) => GeofencePlace(
        label: label ?? this.label,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'created_at': createdAt.toIso8601String(),
      };

  static GeofencePlace? fromJson(Map<String, dynamic> json) {
    try {
      return GeofencePlace(
        label: json['label'] as String? ?? 'Saved place',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        radiusMeters: (json['radius_meters'] as num?)?.toDouble() ?? 50,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ComfortProfile {
  final double minTemperature;
  final double maxTemperature;
  final double minHumidity;
  final double maxHumidity;
  final double maxSound;
  final double minLight;
  final double maxLight;

  const ComfortProfile({
    this.minTemperature = 20,
    this.maxTemperature = 28,
    this.minHumidity = 40,
    this.maxHumidity = 70,
    this.maxSound = 70,
    this.minLight = 100,
    this.maxLight = 750,
  });

  ComfortProfile copyWith({
    double? minTemperature,
    double? maxTemperature,
    double? minHumidity,
    double? maxHumidity,
    double? maxSound,
    double? minLight,
    double? maxLight,
  }) => ComfortProfile(
        minTemperature: minTemperature ?? this.minTemperature,
        maxTemperature: maxTemperature ?? this.maxTemperature,
        minHumidity: minHumidity ?? this.minHumidity,
        maxHumidity: maxHumidity ?? this.maxHumidity,
        maxSound: maxSound ?? this.maxSound,
        minLight: minLight ?? this.minLight,
        maxLight: maxLight ?? this.maxLight,
      );
}

/// AuraMind now uses only tracked/declared inputs:
/// temperature + humidity from weather/device source, and optional sound dB.
/// Light and CO2 were removed from the app model to avoid simulated sensor claims.
class SensorData {
  final double temperature;
  final double humidity;
  final DateTime timestamp;

  SensorData({
    required this.temperature,
    required this.humidity,
    required this.timestamp,
  });
}

class InterventionRecord {
  final String actionId;
  final String message;
  final String type;
  final String? severity;
  final String? trigger;
  final DateTime startedAt;
  final double baselineScore;
  DateTime? completedAt;
  double? followUpScore;
  String? response;
  String? feedbackNote;

  InterventionRecord({
    required this.actionId,
    required this.message,
    required this.type,
    this.severity,
    this.trigger,
    required this.startedAt,
    required this.baselineScore,
    this.completedAt,
    this.followUpScore,
    this.response,
    this.feedbackNote,
  });

  bool get isComplete => completedAt != null;
  double? get scoreDelta =>
      followUpScore == null ? null : followUpScore! - baselineScore;
}

class ActionStep {
  final String id;
  final String title;
  final String description;
  final double estimatedImpact;
  final int estimatedMinutes;
  final String trigger;
  final int successCount;
  final int totalCount;
  final bool isCoping;
  bool completed;
  bool skipped;

  ActionStep({
    required this.id,
    required this.title,
    required this.description,
    required this.estimatedImpact,
    required this.estimatedMinutes,
    required this.trigger,
    this.successCount = 0,
    this.totalCount = 0,
    this.isCoping = false,
    this.completed = false,
    this.skipped = false,
  });

  bool get hasHistory => totalCount > 0;
  String get successLabel => '$successCount of $totalCount times';
}

class ActionPlan {
  final List<ActionStep> steps;
  final double currentScore;
  final double estimatedScore;
  final String? patternInsight;

  ActionPlan({
    required this.steps,
    required this.currentScore,
    required this.estimatedScore,
    this.patternInsight,
  });

  double get totalImpact => steps
      .where((s) => !s.skipped)
      .fold(0.0, (sum, s) => sum + s.estimatedImpact);

  double get remainingImpact => steps
      .where((s) => !s.skipped && !s.completed)
      .fold(0.0, (sum, s) => sum + s.estimatedImpact);

  bool get allDone => steps.every((s) => s.completed || s.skipped);
}

class MoodReading {
  final String mood;
  final double confidence;
  final String description;
  final MoodLevel level;
  final DateTime timestamp;

  MoodReading({
    required this.mood,
    required this.confidence,
    required this.description,
    required this.level,
    required this.timestamp,
  });
}

class AlertItem {
  final String key;
  final String title;
  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  bool isRead;
  String? feedback;
  String? feedbackNote;

  AlertItem({
    required this.key,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.isRead = false,
    this.feedback,
    this.feedbackNote,
  });
}
