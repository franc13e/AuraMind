import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:auramind/services/microphone_noise_reader_stub.dart'
    if (dart.library.js_interop) 'package:auramind/services/microphone_noise_reader_web.dart';
import 'package:auramind/services/light_sensor_stub.dart'
    if (dart.library.js_interop) 'package:auramind/services/light_sensor_web.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auramind/models/auramind_models.dart';
import 'mood_engine.dart';
import 'agent_client.dart';
import 'demo_scenario.dart';

// Trends screen chart mode.
enum ChartKind { line, bar, wheel }

const String _persistentDataKey = 'auramind_persistent_data_v1';
const String _geofencePlacesKey = 'auramind_geofence_places_v1';
const int _maxHistoryPoints = 1500;

class SensorService extends ChangeNotifier {
  final _rng = Random();
  Timer? _timer;
  Timer? _weatherTimer;
  bool _critical = false;
  bool _backendHistoryImporting = false;
  DateTime? lastBackendImportAt;
  int backendImportedCount = 0;
  String? backendImportStatus;
  bool get backendHistoryImporting => _backendHistoryImporting;
  int updateInterval = 3;
  int alertCooldownMinutes = 10;
  TrendMode trendMode = TrendMode.live;
  ChartKind chartKind = ChartKind.line;

  final DateTime _startedAt = DateTime.now();
  final AgentClient _agent = AgentClient();
  bool _isRunning = false;
  bool _sendingSnapshot = false;
  bool get isRunning => _isRunning;
  AgentClient get agent => _agent;

  /// Update patient ID when user logs in.
  void setPatientId(String id) {
    _agent.setPatientId(id);
  }

  /// Update auth token for authenticated API calls.
  void setAuthToken(String? token) {
    _agent.setAuthToken(token);
  }

  ComfortProfile comfortProfile = const ComfortProfile();
  void updateComfortProfile(ComfortProfile profile) {
    comfortProfile = profile;
    _saveSettings();
    _refreshAlerts(_current);
    _rebuildActionPlan();
    notifyListeners();
    _sendToAgent(force: true);
  }

  // Location context can be manual or GPS/geofence matched.
  // Manual remains the fallback so the app still works if GPS permission fails.
  String currentPlace = 'Home';
  bool autoGeofenceEnabled = false;
  String locationSource = 'Manual';
  String geofenceStatus = 'Manual location selected';
  double? lastLatitude;
  double? lastLongitude;
  double? lastLocationAccuracyMeters;
  double? distanceToMatchedPlaceMeters;
  DateTime? lastLocationFixAt;

  final List<GeofencePlace> geofencePlaces = [];

  final List<String> locationOptions = const [
    'Home', 'Campus', 'Library', 'Hostel', 'Office', 'Café', 'Outdoors', 'Custom'
  ];

  String get locationScopeLabel {
    if (autoGeofenceEnabled && locationSource == 'GPS geofence') {
      final distance = distanceToMatchedPlaceMeters == null
          ? ''
          : ' · ${distanceToMatchedPlaceMeters!.round()}m from saved point';
      final accuracy = lastLocationAccuracyMeters == null
          ? ''
          : ' · GPS ±${lastLocationAccuracyMeters!.round()}m';
      return 'GPS geofence$distance$accuracy';
    }
    return 'Manual context';
  }

  void setPlace(String p) {
    final cleaned = p.trim().isEmpty ? 'Custom' : p.trim();
    currentPlace = cleaned;
    locationSource = 'Manual';
    geofenceStatus = 'Manual location selected';
    distanceToMatchedPlaceMeters = null;
    _saveLocationLocal(cleaned);
    notifyListeners();
    _sendToAgent(force: true);
    _agent.saveLocation(cleaned);
  }

  Future<void> setAutoGeofenceEnabled(bool enabled) async {
    autoGeofenceEnabled = enabled;
    if (!enabled) {
      locationSource = 'Manual';
      geofenceStatus = 'GPS geofence off. Manual context is used.';
      distanceToMatchedPlaceMeters = null;
      await _saveGeofenceSettings();
      notifyListeners();
      return;
    }
    await _saveGeofenceSettings();
    notifyListeners();
    await refreshGeofenceNow();
  }

  Future<String> addGeofenceFromCurrentLocation({
    required String label,
    required double radiusMeters,
  }) async {
    final cleaned = label.trim().isEmpty ? 'Custom' : label.trim();
    try {
      final pos = await _getCurrentPositionForGeofence();
      if (pos == null) return geofenceStatus;

      final place = GeofencePlace(
        label: cleaned,
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusMeters: radiusMeters,
        createdAt: DateTime.now(),
      );

      final existing = geofencePlaces.indexWhere(
        (p) => p.label.toLowerCase() == cleaned.toLowerCase(),
      );
      if (existing >= 0) {
        geofencePlaces[existing] = place;
      } else {
        geofencePlaces.add(place);
      }

      autoGeofenceEnabled = true;
      _applyPositionToGeofences(pos, forceUnknown: false);
      await _saveGeofenceSettings();
      await _saveLocationLocal(currentPlace);
      notifyListeners();
      _sendToAgent(force: true);
      await _agent.saveLocation(currentPlace);
      return 'Saved $cleaned geofence (${radiusMeters.round()}m radius).';
    } catch (e) {
      geofenceStatus = 'Could not save geofence: ${e.toString().split('\n').first}';
      notifyListeners();
      return geofenceStatus;
    }
  }

  Future<String> refreshGeofenceNow() async {
    if (!autoGeofenceEnabled) {
      geofenceStatus = 'GPS geofence off. Manual context is used.';
      notifyListeners();
      return geofenceStatus;
    }
    if (geofencePlaces.isEmpty) {
      geofenceStatus = 'No saved geofence places yet.';
      notifyListeners();
      return geofenceStatus;
    }
    final pos = await _getCurrentPositionForGeofence();
    if (pos == null) return geofenceStatus;
    _applyPositionToGeofences(pos, forceUnknown: true);
    await _saveLocationLocal(currentPlace);
    notifyListeners();
    _sendToAgent(force: true);
    await _agent.saveLocation(currentPlace);
    return geofenceStatus;
  }

  Future<void> removeGeofencePlace(String label) async {
    geofencePlaces.removeWhere((p) => p.label == label);
    if (locationSource == 'GPS geofence' && currentPlace == label) {
      currentPlace = 'Outdoors';
      locationSource = 'Manual';
      distanceToMatchedPlaceMeters = null;
      geofenceStatus = 'Removed matched place. Manual fallback is now Outdoors.';
    }
    await _saveGeofenceSettings();
    await _saveLocationLocal(currentPlace);
    notifyListeners();
  }

  List<AgentAction> latestAgentActions = [];
  final List<AgentAction> recentSuggestions = [];
  final Map<String, String> feedbackByAction = {};
  final List<InterventionRecord> interventionRecords = [];

  // Mood check-in state.
  final List<MoodCheckIn> moodCheckIns = [];
  MoodCheckIn? get latestMoodCheckIn => moodCheckIns.isEmpty ? null : moodCheckIns.first;
  int get checkInCount => moodCheckIns.length;
  double get predictionAccuracy {
    if (moodCheckIns.isEmpty) return 0;
    final close = moodCheckIns.where((c) => c.closeMatch).length;
    return close / moodCheckIns.length * 100;
  }
  int get calibrationProgress => moodCheckIns.length.clamp(0, 7);
  bool get calibrationComplete => calibrationProgress >= 7;

  void submitMoodCheckIn(SelfMood mood) {
    final predicted = MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux);
    moodCheckIns.insert(0, MoodCheckIn(
      reportedMood: mood,
      predictedMood: predicted,
      sensorData: _current,
      timestamp: DateTime.now(),
    ));
    if (moodCheckIns.length > 50) moodCheckIns.removeRange(50, moodCheckIns.length);
    notifyListeners();
    _savePersistentData();
  }

  // Suggested reset state.
  ActionPlan? _actionPlan;
  ActionPlan? get actionPlan => _actionPlan;
  ActionStep? _activeResetStep;
  ActionStep? get activeResetStep => _activeResetStep;

  InterventionRecord? _latestResetImpact;
  InterventionRecord? get latestResetImpact => _latestResetImpact;

  void clearLatestResetImpact() {
    _latestResetImpact = null;
    notifyListeners();
  }

  final Map<String, DateTime> _suppressedResetUntilByTrigger = {};

  bool _isSuppressed(ActionStep step) {
    final until = _suppressedResetUntilByTrigger[step.trigger];
    return until != null && DateTime.now().isBefore(until);
  }

  /// Returns a short string that captures the meaningful state that should
  /// cause the action plan to regenerate. Only rebuild when this changes.
  String _planSignature() {
    final mood = MoodEngine.predict(_current, profile: comfortProfile,
        lightLux: currentLightLux);
    final tempBucket = mood.level.index;
    final tooHot  = _current.temperature > comfortProfile.maxTemperature + 2;
    final tooCold = _current.temperature < comfortProfile.minTemperature - 2;
    final tooHumid = _current.humidity > comfortProfile.maxHumidity + 10;
    final tooDry   = _current.humidity < comfortProfile.minHumidity - 10;
    final tooLoud  = hasSoundData && currentSoundDb > comfortProfile.maxSound;
    final tooDim   = currentLightLux >= 0 && currentLightLux < comfortProfile.minLight * 0.3;
    final tooGlary = currentLightLux >= 0 && currentLightLux > comfortProfile.maxLight * 1.5;
    return '\$tempBucket|\$tooHot|\$tooCold|\$tooHumid|\$tooDry|\$tooLoud|\$tooDim|\$tooGlary';
  }

  String _lastPlanSignature = '';

  void _rebuildActionPlan() {
    final sig = _planSignature();
    if (sig == _lastPlanSignature && _actionPlan != null) return;
    _lastPlanSignature = sig;
    final minutes = DateTime.now().difference(_startedAt).inMinutes;
    final raw = MoodEngine.buildActionPlan(
      _current,
      profile: comfortProfile,
      soundDb: hasSoundData ? currentSoundDb : 0,
      lightLux: currentLightLux,
      place: currentPlace,
      minutesAtPlace: minutes,
      history: interventionRecords,
      recentReadings: _history,
    );
    final filtered = raw.steps.where((s) => !_isSuppressed(s)).toList();
    _actionPlan = ActionPlan(
      steps: filtered,
      currentScore: raw.currentScore,
      estimatedScore: raw.estimatedScore,
      patternInsight: raw.patternInsight,
    );
  }

  ActionStep? _findStep(String stepId) {
    final plan = _actionPlan;
    if (plan == null) return null;
    for (final step in plan.steps) {
      if (step.id == stepId) return step;
    }
    return null;
  }

  void startCopingStep(ActionStep step) {
    _activeResetStep = step;
    _recordInterventionForStep(step, response: 'started');
    notifyListeners();
  }

  void startResetStep(String stepId) {
    final step = _findStep(stepId);
    if (step == null) return;
    _activeResetStep = step;
    _recordInterventionForStep(step, response: 'started');
    notifyListeners();
    _savePersistentData();
  }

  void completeActiveReset({String response = 'done', String? note}) {
    final step = _activeResetStep;
    if (step == null) return;
    step.completed = true;
    _latestResetImpact = _completeInterventionForStep(step, response, note: note);
    _suppressedResetUntilByTrigger[step.trigger] = DateTime.now().add(const Duration(minutes: 10));
    _activeResetStep = null;
    _rebuildActionPlan();
    notifyListeners();
    _savePersistentData();
  }

  void markActiveResetNotHelpful({String? note}) {
    final step = _activeResetStep;
    if (step == null) return;
    _latestResetImpact = _completeInterventionForStep(step, 'not_helpful', note: note);
    // Suppress both the tapped trigger and its paired env/coping counterpart
    // so neither version of the same problem reappears immediately.
    final until = DateTime.now().add(const Duration(minutes: 5));
    _suppressedResetUntilByTrigger[step.trigger] = until;
    final paired = _pairedTrigger(step.trigger);
    if (paired != null) _suppressedResetUntilByTrigger[paired] = until;
    _activeResetStep = null;
    _rebuildActionPlan();
    notifyListeners();
    _savePersistentData();
  }

  /// Returns the paired trigger for a given trigger key.
  /// Environmental fixes and their coping counterparts are paired so that
  /// dismissing one also suppresses the other temporarily.
  String? _pairedTrigger(String trigger) {
    const pairs = {
      'temp': 'cope_temp',
      'cope_temp': 'temp',
      'humidity': 'cope_humidity',
      'cope_humidity': 'humidity',
      'sound': 'cope_sound',
      'cope_sound': 'sound',
      'light': 'cope_light',
      'cope_light': 'light',
    };
    return pairs[trigger];
  }

  void notNowActionStep(String stepId) {
    final step = _findStep(stepId);
    if (step == null) return;
    _suppressedResetUntilByTrigger[step.trigger] = DateTime.now().add(const Duration(minutes: 2));
    _recordInterventionForStep(step, response: 'not_now');
    _rebuildActionPlan();
    notifyListeners();
    _savePersistentData();
  }

  void remindActionStep(String stepId) {
    final step = _findStep(stepId);
    if (step == null) return;
    _suppressedResetUntilByTrigger[step.trigger] = DateTime.now().add(Duration(minutes: alertCooldownMinutes));
    _recordInterventionForStep(step, response: 'remind');
    _rebuildActionPlan();
    notifyListeners();
    _savePersistentData();
  }

  void dismissActionPlan() {
    final plan = _actionPlan;
    if (plan != null && plan.steps.isNotEmpty) {
      final step = plan.steps.first;
      _suppressedResetUntilByTrigger[step.trigger] = DateTime.now().add(const Duration(minutes: 10));
    }
    _actionPlan = null;
    notifyListeners();
  }

  void _recordInterventionForStep(ActionStep step, {String? response}) {
    final id = 'plan_${step.trigger}_${DateTime.now().millisecondsSinceEpoch}';
    interventionRecords.insert(0, InterventionRecord(
      actionId: id,
      message: step.title,
      type: 'suggested_reset',
      trigger: step.trigger,
      startedAt: DateTime.now(),
      baselineScore: MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux).confidence,
      response: response,
    ));
    if (interventionRecords.length > 50) interventionRecords.removeRange(50, interventionRecords.length);
  }

  InterventionRecord _completeInterventionForStep(ActionStep step, String response, {String? note}) {
    final index = interventionRecords.indexWhere((r) =>
        r.type == 'suggested_reset' && r.trigger == step.trigger && !r.isComplete);
    final record = index == -1 ? null : interventionRecords[index];
    if (record == null) {
      _recordInterventionForStep(step, response: response);
      interventionRecords.first.completedAt = DateTime.now();
      interventionRecords.first.followUpScore = MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux).confidence;
      interventionRecords.first.feedbackNote = note;
      return interventionRecords.first;
    }
    record.response = response;
    record.feedbackNote = note;
    record.completedAt = DateTime.now();
    record.followUpScore = MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux).confidence;
    return record;
  }

  // Agent and sampling throttle state.
  SensorData? _lastSentData;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastSentSound = -1;
  static const _dTemp = 1.5;
  static const _dHum = 7.0;
  static const _dSound = 18.0;
  static const _heartbeat = Duration(minutes: 5);

  double? _realTemp;
  double? _realHumidity;
  double? _realSoundDb;

  final MicrophoneNoiseReader _micReader = MicrophoneNoiseReader();
  String _micStatus = 'Microphone not started';
  String get micStatus => _micStatus;

  final AmbientLightReader _lightReader = AmbientLightReader();
  String _lightStatus = 'Light sensor not started';
  String get lightStatus => _lightStatus;
  double? _realLightLux;

  /// Sound uses the device/browser microphone when permission is granted.
  /// No microphone reading means sound is not used for alerts, resets, reports,
  /// or agent decisions.
  double? get currentSoundDbValue => _realSoundDb;
  double get currentSoundDb => currentSoundDbValue ?? 0;
  bool get hasSoundData => currentSoundDbValue != null;
  String get soundSourceLabel => hasSoundData ? 'Device microphone' : _micStatus;

  /// Light uses the device ambient light sensor or camera-based estimation.
  double? get currentLightLuxValue => _realLightLux;
  double get currentLightLux => currentLightLuxValue ?? -1;
  bool get hasLightData => currentLightLuxValue != null;
  String get lightSourceLabel => hasLightData ? 'Device sensor' : _lightStatus;

  Future<void> requestLightAccess() async {
    await _initLight(forcePrompt: true);
  }

  Future<void> requestMicrophoneAccess() async {
    await _initMic(forcePrompt: true);
  }

  SensorData _current = SensorData(
    temperature: 24.0,
    humidity: 62.0,
    timestamp: DateTime.now(),
  );

  final List<SensorData> _history = [];
  final List<AlertItem> _alerts = [];
  final Set<String> _activeAlertKeys = {};
  final Map<String, DateTime> _lastAlertAtByKey = {};

  SensorData get current => _current;
  List<SensorData> get history => List.unmodifiable(_history);
  List<AlertItem> get alerts => List.unmodifiable(_alerts);
  bool get criticalMode => _critical;
  int get unreadAlerts => _alerts.where((a) => !a.isRead).length;

  final DemoController _demo = DemoController();
  bool get isDemoPlaying => _demo.isPlaying;
  DemoScenario? get activeDemoScenario => _demo.activeScenario;
  String? demoLabel;

  void startDemo(DemoScenario scenario) {
    _timer?.cancel();
    _demo.play(
      scenario: scenario,
      onFrame: (data, soundDb) {
        _realSoundDb = soundDb;
        _current = data;
        _push(_current);
        notifyListeners();
        _sendToAgent(force: true);
      },
      onLabel: (label) { demoLabel = label; notifyListeners(); },
      onDone: () {
        demoLabel = '✅ Scenario complete';
        notifyListeners();
        _timer = Timer.periodic(Duration(seconds: updateInterval), (_) => _tick());
      },
    );
    notifyListeners();
  }

  void stopDemo() {
    _demo.stop();
    demoLabel = null;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: updateInterval), (_) => _tick());
    notifyListeners();
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _loadSavedSettings();
    _loadGeofenceSettings().then((_) => _loadSavedLocation());
    _loadPersistentData().then((_) {
      if (_history.isEmpty) {
        _push(_current);
      } else {
        _current = _history.last;
        _refreshAlerts(_current);
        _rebuildActionPlan();
        notifyListeners();
      }
      _sendToAgent(force: true);
    });
    _initRealSensors();
    _timer = Timer.periodic(Duration(seconds: updateInterval), (_) => _tick());
  }

  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tempLow = prefs.getDouble('comfort_temp_min');
      final tempHigh = prefs.getDouble('comfort_temp_max');
      final humLow = prefs.getDouble('comfort_humidity_min');
      final humHigh = prefs.getDouble('comfort_humidity_max');
      final soundMax = prefs.getDouble('comfort_sound_max');
      if (tempLow != null && tempHigh != null && humLow != null && humHigh != null && soundMax != null) {
        comfortProfile = ComfortProfile(
          minTemperature: tempLow,
          maxTemperature: tempHigh,
          minHumidity: humLow,
          maxHumidity: humHigh,
          maxSound: soundMax,
        );
      }
      updateInterval = prefs.getInt('update_interval') ?? updateInterval;
      alertCooldownMinutes = prefs.getInt('alert_cooldown_minutes') ?? alertCooldownMinutes;
      final chartKindStr = prefs.getString('chart_kind');
      if (chartKindStr != null) {
        try { chartKind = ChartKind.values.firstWhere((k) => k.name == chartKindStr); } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('comfort_temp_min', comfortProfile.minTemperature);
      await prefs.setDouble('comfort_temp_max', comfortProfile.maxTemperature);
      await prefs.setDouble('comfort_humidity_min', comfortProfile.minHumidity);
      await prefs.setDouble('comfort_humidity_max', comfortProfile.maxHumidity);
      await prefs.setDouble('comfort_sound_max', comfortProfile.maxSound);
      await prefs.setInt('update_interval', updateInterval);
      await prefs.setInt('alert_cooldown_minutes', alertCooldownMinutes);
      await prefs.setString('chart_kind', chartKind.name);
    } catch (_) {}
  }

  Future<void> _loadGeofenceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      autoGeofenceEnabled = prefs.getBool('auto_geofence_enabled') ?? false;
      final rawPlaces = prefs.getString(_geofencePlacesKey);
      geofencePlaces.clear();
      if (rawPlaces != null && rawPlaces.isNotEmpty) {
        final decoded = jsonDecode(rawPlaces) as List;
        geofencePlaces.addAll(decoded
            .whereType<Map>()
            .map((e) => GeofencePlace.fromJson(Map<String, dynamic>.from(e)))
            .whereType<GeofencePlace>());
      }
      geofenceStatus = autoGeofenceEnabled
          ? (geofencePlaces.isEmpty ? 'GPS geofence on, but no saved places yet.' : 'GPS geofence ready.')
          : 'Manual location selected';
      notifyListeners();
    } catch (e) {
      debugPrint('Geofence settings load failed: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _saveGeofenceSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_geofence_enabled', autoGeofenceEnabled);
      await prefs.setString(
        _geofencePlacesKey,
        jsonEncode(geofencePlaces.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Geofence settings save failed: ${e.toString().split('\n').first}');
    }
  }

  Future<Position?> _getCurrentPositionForGeofence() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        geofenceStatus = 'Location permission denied. Manual context is still available.';
        notifyListeners();
        return null;
      }
      if (perm == LocationPermission.deniedForever) {
        geofenceStatus = 'Location permission permanently denied. Enable it in browser/device settings.';
        notifyListeners();
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      lastLatitude = pos.latitude;
      lastLongitude = pos.longitude;
      lastLocationAccuracyMeters = pos.accuracy;
      lastLocationFixAt = DateTime.now();
      return pos;
    } catch (e) {
      geofenceStatus = 'Could not read GPS location: ${e.toString().split('\n').first}';
      notifyListeners();
      return null;
    }
  }

  void _applyPositionToGeofences(Position pos, {required bool forceUnknown}) {
    if (geofencePlaces.isEmpty) {
      geofenceStatus = 'No saved geofence places yet.';
      return;
    }

    GeofencePlace? bestPlace;
    double? bestDistance;
    for (final place in geofencePlaces) {
      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        place.latitude,
        place.longitude,
      );
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestPlace = place;
      }
    }

    if (bestPlace != null && bestDistance != null && bestDistance <= bestPlace.radiusMeters) {
      currentPlace = bestPlace.label;
      locationSource = 'GPS geofence';
      distanceToMatchedPlaceMeters = bestDistance;
      geofenceStatus = 'Matched ${bestPlace.label}: ${bestDistance.round()}m within ${bestPlace.radiusMeters.round()}m radius.';
    } else {
      distanceToMatchedPlaceMeters = bestDistance;
      locationSource = forceUnknown ? 'GPS geofence' : locationSource;
      if (forceUnknown) currentPlace = 'Outdoors';
      final nearest = bestPlace == null || bestDistance == null
          ? 'No saved place nearby.'
          : 'Nearest saved place is ${bestDistance.round()}m away from ${bestPlace.label}.';
      geofenceStatus = '$nearest Outside all saved radii, using ${currentPlace == 'Outdoors' ? 'Outdoors' : 'manual fallback'}.';
    }
  }

  Future<void> _loadSavedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('current_place');
      if (local != null && local.isNotEmpty) currentPlace = local;
      final saved = await _agent.loadLocation();
      if (!autoGeofenceEnabled && saved != null && saved.isNotEmpty) currentPlace = saved;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveLocationLocal(String place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_place', place);
    } catch (_) {}
  }

  Future<void> _loadPersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistentDataKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      _history
        ..clear()
        ..addAll(((data['history'] as List?) ?? [])
            .map((e) => _sensorFromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<SensorData>());
      if (_history.length > 200) {
        _history.removeRange(0, _history.length - 200);
      }

      _alerts
        ..clear()
        ..addAll(((data['alerts'] as List?) ?? [])
            .map((e) => _alertFromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<AlertItem>());
      if (_alerts.length > 50) {
        _alerts.removeRange(50, _alerts.length);
      }

      moodCheckIns
        ..clear()
        ..addAll(((data['mood_checkins'] as List?) ?? [])
            .map((e) => _checkInFromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<MoodCheckIn>());
      if (moodCheckIns.length > 50) {
        moodCheckIns.removeRange(50, moodCheckIns.length);
      }

      interventionRecords
        ..clear()
        ..addAll(((data['interventions'] as List?) ?? [])
            .map((e) => _interventionFromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<InterventionRecord>());
      if (interventionRecords.length > 50) {
        interventionRecords.removeRange(50, interventionRecords.length);
      }

      if (_history.isNotEmpty) _current = _history.last;
      notifyListeners();
    } catch (e) {
      debugPrint('Persistent data load failed: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _savePersistentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'history': _history.map(_sensorToJson).toList(),
        'alerts': _alerts.map(_alertToJson).toList(),
        'mood_checkins': moodCheckIns.map(_checkInToJson).toList(),
        'interventions': interventionRecords.map(_interventionToJson).toList(),
      };
      await prefs.setString(_persistentDataKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Persistent data save failed: ${e.toString().split('\n').first}');
    }
  }

  Future<void> clearPersistentWellbeingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistentDataKey);
    } catch (_) {}
    _history.clear();
    _alerts.clear();
    moodCheckIns.clear();
    interventionRecords.clear();
    _activeAlertKeys.clear();
    _lastAlertAtByKey.clear();
    _latestResetImpact = null;
    _push(_current);
    notifyListeners();
    _savePersistentData();
  }

  Map<String, dynamic> _sensorToJson(SensorData d) => {
    'temperature': d.temperature,
    'humidity': d.humidity,
    'timestamp': d.timestamp.toIso8601String(),
  };

  SensorData? _sensorFromJson(Map<String, dynamic> j) {
    try {
      return SensorData(
        temperature: (j['temperature'] as num?)?.toDouble() ?? 24.0,
        humidity: (j['humidity'] as num?)?.toDouble() ?? 62.0,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) { return null; }
  }

  Map<String, dynamic> _alertToJson(AlertItem a) => {
    'key': a.key,
    'title': a.title,
    'message': a.message,
    'severity': a.severity.name,
    'timestamp': a.timestamp.toIso8601String(),
    'is_read': a.isRead,
    'feedback': a.feedback,
    'feedback_note': a.feedbackNote,
  };

  AlertItem? _alertFromJson(Map<String, dynamic> j) {
    try {
      final severityName = j['severity'] as String? ?? AlertSeverity.info.name;
      return AlertItem(
        key: j['key'] as String? ?? 'saved_alert',
        title: j['title'] as String? ?? 'Saved alert',
        message: j['message'] as String? ?? '',
        severity: AlertSeverity.values.firstWhere(
          (v) => v.name == severityName,
          orElse: () => AlertSeverity.info,
        ),
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
        isRead: j['is_read'] as bool? ?? false,
        feedback: j['feedback'] as String?,
        feedbackNote: j['feedback_note'] as String?,
      );
    } catch (_) { return null; }
  }

  Map<String, dynamic> _checkInToJson(MoodCheckIn c) => {
    'reported_mood': c.reportedMood.name,
    'predicted_mood': c.predictedMood.mood,
    'predicted_confidence': c.predictedMood.confidence,
    'predicted_description': c.predictedMood.description,
    'predicted_level': c.predictedMood.level.name,
    'sensor': _sensorToJson(c.sensorData),
    'timestamp': c.timestamp.toIso8601String(),
  };

  MoodCheckIn? _checkInFromJson(Map<String, dynamic> j) {
    try {
      final reportedName = j['reported_mood'] as String? ?? SelfMood.neutral.name;
      final levelName = j['predicted_level'] as String? ?? MoodLevel.neutral.name;
      final sensorRaw = j['sensor'];
      final sensor = sensorRaw is Map
          ? _sensorFromJson(Map<String, dynamic>.from(sensorRaw))
          : null;
      return MoodCheckIn(
        reportedMood: SelfMood.values.firstWhere(
          (v) => v.name == reportedName,
          orElse: () => SelfMood.neutral,
        ),
        predictedMood: MoodReading(
          mood: j['predicted_mood'] as String? ?? 'Neutral',
          confidence: (j['predicted_confidence'] as num?)?.toDouble() ?? 50,
          description: j['predicted_description'] as String? ?? '',
          level: MoodLevel.values.firstWhere(
            (v) => v.name == levelName,
            orElse: () => MoodLevel.neutral,
          ),
          timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
        ),
        sensorData: sensor ?? _current,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) { return null; }
  }

  Map<String, dynamic> _interventionToJson(InterventionRecord r) => {
    'action_id': r.actionId,
    'message': r.message,
    'type': r.type,
    'severity': r.severity,
    'trigger': r.trigger,
    'started_at': r.startedAt.toIso8601String(),
    'baseline_score': r.baselineScore,
    'completed_at': r.completedAt?.toIso8601String(),
    'follow_up_score': r.followUpScore,
    'response': r.response,
    'feedback_note': r.feedbackNote,
  };

  InterventionRecord? _interventionFromJson(Map<String, dynamic> j) {
    try {
      return InterventionRecord(
        actionId: j['action_id'] as String? ?? 'saved_${DateTime.now().millisecondsSinceEpoch}',
        message: j['message'] as String? ?? '',
        type: j['type'] as String? ?? 'suggested_reset',
        severity: j['severity'] as String?,
        trigger: j['trigger'] as String?,
        startedAt: DateTime.tryParse(j['started_at'] as String? ?? '') ?? DateTime.now(),
        baselineScore: (j['baseline_score'] as num?)?.toDouble() ?? 0,
        completedAt: DateTime.tryParse(j['completed_at'] as String? ?? ''),
        followUpScore: (j['follow_up_score'] as num?)?.toDouble(),
        response: j['response'] as String?,
        feedbackNote: j['feedback_note'] as String?,
      );
    } catch (_) { return null; }
  }

  void stop() {
    _timer?.cancel();
    _weatherTimer?.cancel();
    _micReader.stop();
    _lightReader.stop();
    _demo.stop();
    _isRunning = false;
  }

  void setInterval(int s) {
    updateInterval = s;
    _saveSettings();
    if (!isDemoPlaying) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(seconds: updateInterval), (_) => _tick());
    }
    notifyListeners();
  }

  void setAlertCooldownMinutes(int minutes) {
    alertCooldownMinutes = minutes;
    _saveSettings();
    notifyListeners();
  }

  void setTrendMode(TrendMode m) { trendMode = m; notifyListeners(); }
  void setChartKind(ChartKind k) { chartKind = k; _saveSettings(); notifyListeners(); }

  void triggerCritical() {
    _critical = true;
    _current = SensorData(
      temperature: 32.5,
      humidity: 85.0,
      timestamp: DateTime.now(),
    );
    _push(_current);
    notifyListeners();
    _sendToAgent(force: true);
  }

  void resetCritical() {
    _critical = false;
    _push(_current);
    notifyListeners();
    _sendToAgent(force: true);
  }

  void markAllRead() {
    for (final a in _alerts) { a.isRead = true; }
    notifyListeners();
    _savePersistentData();
  }

  void markAlertRead(AlertItem alert) {
    alert.isRead = true;
    notifyListeners();
    _savePersistentData();
  }

  void submitAlertFeedback(AlertItem alert, String feedback, {String? note}) {
    alert.isRead = true;
    alert.feedback = feedback;
    alert.feedbackNote = note;
    notifyListeners();
    _savePersistentData();
  }

  void clearReadAlerts() {
    _alerts.removeWhere((a) => a.isRead);
    notifyListeners();
    _savePersistentData();
  }

  Future<void> submitFeedback(AgentAction action, String response, {String? note}) async {
    if (action.id == null) return;
    feedbackByAction[action.id!] = response;
    _recordFeedback(action, response, note: note);
    notifyListeners();
    _savePersistentData();
    await _agent.sendFeedback(actionId: action.id!, response: response);
  }

  ReportData buildLocalReport({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final readings = _history.where((d) => d.timestamp.isAfter(cutoff)).toList();
    if (readings.isEmpty) {
      return ReportData(days: days, readingCount: 0, avgScore: 0, distribution: const {}, interventions: const []);
    }
    final moods = readings.map((d) => MoodEngine.predict(d, profile: comfortProfile)).toList();
    final distribution = <String, int>{};
    double total = 0;
    for (final mood in moods) {
      total += mood.confidence;
      distribution[mood.level.name] = (distribution[mood.level.name] ?? 0) + 1;
    }
    final interventions = interventionRecords.map<Map<String, dynamic>>((r) => {
      'tool': r.type,
      'message': r.message,
      'severity': r.severity,
      'feedback': r.response,
      'feedback_note': r.feedbackNote,
      'baseline_score': r.baselineScore,
      'follow_up_score': r.followUpScore,
      'score_delta': r.scoreDelta,
    }).toList();
    return ReportData(
      days: days,
      readingCount: readings.length,
      avgScore: total / moods.length,
      distribution: distribution,
      interventions: interventions,
    );
  }

  Future<void> _initRealSensors() async {
    await _initWeather();
    await _initMic();
    await _initLight();
  }

  Future<void> _initMic({bool forcePrompt = false}) async {
    try {
      _micStatus = forcePrompt ? 'Requesting microphone permission...' : 'Starting microphone...';
      notifyListeners();

      final started = await _micReader.start((db) {
        if (isDemoPlaying) return;
        _realSoundDb = db;
        _refreshAlerts(_current);
        _rebuildActionPlan();
        notifyListeners();
        _sendToAgent(force: true);
      });

      if (started) {
        _micStatus = 'Listening';
      } else {
        _micStatus = 'Microphone unavailable';
      }
      notifyListeners();
    } catch (e) {
      _micStatus = 'Microphone permission needed';
      debugPrint('Microphone init failed: ${e.toString().split('\n').first}');
      notifyListeners();
    }
  }

  Future<void> _initLight({bool forcePrompt = false}) async {
    try {
      _lightStatus = forcePrompt ? 'Requesting light sensor permission...' : 'Starting light sensor...';
      notifyListeners();

      final started = await _lightReader.start((lux) {
        if (isDemoPlaying) return;
        _realLightLux = lux;
        _refreshAlerts(_current);
        _rebuildActionPlan();
        notifyListeners();
      });

      if (started) {
        _lightStatus = 'Listening';
      } else {
        _lightStatus = 'Light sensor unavailable';
      }
      notifyListeners();
    } catch (e) {
      _lightStatus = 'Light sensor permission needed';
      debugPrint('Light sensor init failed: ${e.toString().split('\n').first}');
      notifyListeners();
    }
  }

  Future<void> _initWeather() async {
    await _fetchWeatherOnce();
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) => _fetchWeatherOnce());
  }

  Future<void> _fetchWeatherOnce() async {
    if (isDemoPlaying) return;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      lastLatitude = pos.latitude;
      lastLongitude = pos.longitude;
      lastLocationAccuracyMeters = pos.accuracy;
      lastLocationFixAt = DateTime.now();
      if (autoGeofenceEnabled && geofencePlaces.isNotEmpty) {
        _applyPositionToGeofences(pos, forceUnknown: false);
        await _saveLocationLocal(currentPlace);
      }
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}&longitude=${pos.longitude}'
        '&current=temperature_2m,relative_humidity_2m',
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return;
      final current = (jsonDecode(res.body) as Map<String, dynamic>)['current'] as Map<String, dynamic>;
      _realTemp = (current['temperature_2m'] as num?)?.toDouble();
      _realHumidity = (current['relative_humidity_2m'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('Weather fetch failed: ${e.toString().split('\n').first}');
    }
  }

  void _tick() {
    if (_critical || isDemoPlaying) return;
    // No light/CO2 simulation. Only update tracked data: weather values when
    // available, otherwise keep the previous displayed value with a tiny drift
    // so the demo remains readable until API permission is granted.
    _current = SensorData(
      temperature: _realTemp ?? _clamp(_current.temperature + _d(0.15), 18, 32),
      humidity: _realHumidity ?? _clamp(_current.humidity + _d(0.5), 30, 90),
      timestamp: DateTime.now(),
    );
    _push(_current);
    notifyListeners();
    _sendToAgent();
  }

  static const _minSendInterval = Duration(seconds: 15);

  void _sendToAgent({bool force = false}) {
    final now = DateTime.now();
    final timeSince = now.difference(_lastSentAt);

    // Never send if already in-flight.
    if (_sendingSnapshot) return;

    // Enforce a minimum interval even for forced sends to avoid Groq 429s.
    if (timeSince < _minSendInterval) return;

    if (!force) {
      final last = _lastSentData;
      final sound = hasSoundData ? currentSoundDb : 0;
      final changed = last == null ||
          (_current.temperature - last.temperature).abs() >= _dTemp ||
          (_current.humidity - last.humidity).abs() >= _dHum ||
          (_lastSentSound < 0 ? false : (sound - _lastSentSound).abs() >= _dSound);
      final heartbeatDue = timeSince >= _heartbeat;
      if (!changed && !heartbeatDue) return;
    }

    _lastSentData = _current;
    _lastSentAt = now;
    _lastSentSound = hasSoundData ? currentSoundDb : 0;
    final minutes = now.difference(_startedAt).inMinutes;

    _sendingSnapshot = true;
    _agent.sendSnapshot(
      _current,
      place: currentPlace,
      minutesAtPlace: minutes,
      timeOfDay: _timeOfDay(),
      soundDb: hasSoundData ? currentSoundDb : 0,
    ).then((actions) {
      _sendingSnapshot = false;
      latestAgentActions = actions;
      for (final a in actions) {
        _ensureInterventionRecord(a);
        if (a.tool == 'suggest_activity') {
          recentSuggestions.insert(0, a);
          if (recentSuggestions.length > 10) recentSuggestions.removeRange(10, recentSuggestions.length);
        }
      }
      notifyListeners();
    }).catchError((e) {
      _sendingSnapshot = false;
      debugPrint('Agent snapshot failed: ${e.toString().split('\n').first}');
    });
  }

  String _timeOfDay() {
    final h = DateTime.now().hour;
    if (h < 6) return 'night';
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    if (h < 21) return 'evening';
    return 'night';
  }

  void _push(SensorData data) {

    _history.add(data);
    if (_history.length > _maxHistoryPoints) {
      _history.removeRange(0, _history.length - _maxHistoryPoints);
    }
    _refreshAlerts(data);
    _rebuildActionPlan();
    _savePersistentData();
  }

  void _refreshAlerts(SensorData data) {
    final current = [
      ...MoodEngine.checkAlerts(data, profile: comfortProfile, lightLux: currentLightLux),
      if (hasSoundData && currentSoundDb > comfortProfile.maxSound)
        (
          key: 'sound_high',
          item: AlertItem(
            key: 'sound_high',
            title: 'High sound level',
            message: 'Sound is ${currentSoundDb.toStringAsFixed(0)} dB — above your comfort limit.',
            severity: AlertSeverity.warning,
            timestamp: DateTime.now(),
          ),
        ),
    ];
    final currentKeys = current.map((c) => c.key).toSet();
    final now = DateTime.now();

    var changed = false;
    for (final condition in current) {
      final lastAt = _lastAlertAtByKey[condition.key];
      final cooled = lastAt == null || now.difference(lastAt).inMinutes >= alertCooldownMinutes;
      final wasInactive = !_activeAlertKeys.contains(condition.key);
      if (cooled || wasInactive) {
        _alerts.insert(0, condition.item);
        _lastAlertAtByKey[condition.key] = now;
        changed = true;
      }
    }

    _activeAlertKeys
      ..clear()
      ..addAll(currentKeys);

    if (_alerts.length > 50) {
      _alerts.removeRange(50, _alerts.length);
      changed = true;
    }
    if (changed) _savePersistentData();
  }


  /// Imports old backend SQLite readings into Flutter local storage.
  /// Trends/Report call this so older backend readings can appear beside
  /// new locally-persistent readings. It is safe to call repeatedly because
  /// readings are deduplicated by timestamp.
  Future<int> importBackendHistory({int hours = 24 * 30, bool force = false}) async {
    if (_backendHistoryImporting) return 0;
    final now = DateTime.now();
    if (!force && lastBackendImportAt != null &&
        now.difference(lastBackendImportAt!).inMinutes < 5) {
      return 0;
    }

    _backendHistoryImporting = true;
    backendImportStatus = 'Importing previous readings...';
    notifyListeners();

    try {
      final points = await _agent.fetchHistory(hours: hours);
      final added = mergeBackendHistoryPoints(points);
      lastBackendImportAt = DateTime.now();
      backendImportedCount += added;
      backendImportStatus = points.isEmpty
          ? 'No previous backend readings found.'
          : 'Imported $added previous reading${added == 1 ? '' : 's'}.';
      return added;
    } catch (e) {
      backendImportStatus = 'Backend import unavailable.';
      debugPrint('Backend history import failed: ${e.toString().split('\n').first}');
      return 0;
    } finally {
      _backendHistoryImporting = false;
      notifyListeners();
    }
  }

  /// Merges backend /history records into local persistent reading history.
  int mergeBackendHistoryPoints(List<HistoryPoint> points) {
    if (points.isEmpty) return 0;
    final existingKeys = _history.map((d) => d.timestamp.toIso8601String()).toSet();
    var added = 0;

    for (final p in points) {
      final key = p.ts.toIso8601String();
      if (existingKeys.contains(key)) continue;
      _history.add(SensorData(
        temperature: p.temperature,
        humidity: p.humidity,
        timestamp: p.ts,
      ));
      existingKeys.add(key);
      added++;
    }

    if (added > 0) {
      _history.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (_history.length > _maxHistoryPoints) {
        _history.removeRange(0, _history.length - _maxHistoryPoints);
      }
      _current = _history.last;
      _savePersistentData();
      _refreshAlerts(_current);
      _rebuildActionPlan();
      notifyListeners();
    }
    return added;
  }

  List<HistoryPoint> buildLocalHistoryPoints({required int hours}) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final readings = _history.where((d) => d.timestamp.isAfter(cutoff)).toList();
    return readings.map((d) {
      final m = MoodEngine.predict(d, profile: comfortProfile);
      return HistoryPoint(
        ts: d.timestamp,
        moodLevel: m.level.name,
        moodScore: m.confidence,
        temperature: d.temperature,
        humidity: d.humidity,
        sound: hasSoundData ? currentSoundDb : 0,
      );
    }).toList();
  }

  List<MoodReading> get trendReadings {
    final moods = _history.map((d) => MoodEngine.predict(d, profile: comfortProfile)).toList();
    switch (trendMode) {
      case TrendMode.live: return moods;
      case TrendMode.minutes: return _aggregateBy(moods, _history, (t) => '${t.hour}:${t.minute.toString().padLeft(2,'0')}');
      case TrendMode.hours: return _aggregateBy(moods, _history, (t) => '${t.hour}');
      case TrendMode.week:
      case TrendMode.month:
        return moods;
    }
  }

  List<MoodReading> _aggregateBy(List<MoodReading> moods, List<SensorData> data, String Function(DateTime) key) {
    final map = <String, List<MoodReading>>{};
    for (int i = 0; i < moods.length; i++) {
      final k = key(data[i].timestamp);
      map.putIfAbsent(k, () => []).add(moods[i]);
    }
    return map.values.map((group) {
      final avg = group.map((r) => r.confidence).reduce((a, b) => a + b) / group.length;
      final best = group.reduce((a, b) => a.confidence > b.confidence ? a : b);
      return MoodReading(
        mood: best.mood,
        confidence: avg,
        description: best.description,
        level: best.level,
        timestamp: best.timestamp,
      );
    }).toList();
  }

  double _d(double r) => (_rng.nextDouble() - 0.5) * r;
  double _clamp(double v, double mn, double mx) => v.clamp(mn, mx).toDouble();

  void _ensureInterventionRecord(AgentAction action) {
    if (action.id == null) return;
    if (action.tool != 'send_alert' && action.tool != 'suggest_activity') return;
    final exists = interventionRecords.any((r) => r.actionId == action.id);
    if (exists) return;
    interventionRecords.insert(0, InterventionRecord(
      actionId: action.id!,
      message: (action.args['message'] as String?) ?? '',
      type: action.tool,
      severity: action.args['severity'] as String?,
      startedAt: DateTime.now(),
      baselineScore: MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux).confidence,
    ));
    if (interventionRecords.length > 50) interventionRecords.removeRange(50, interventionRecords.length);
  }

  void _recordFeedback(AgentAction action, String response, {String? note}) {
    _ensureInterventionRecord(action);
    final id = action.id;
    if (id == null) return;
    final index = interventionRecords.indexWhere((r) => r.actionId == id);
    if (index == -1) return;
    final record = interventionRecords[index];
    record.response = response;
    record.feedbackNote = note;
    if (response == 'done' || response == 'done_helpful') {
      record.completedAt = DateTime.now();
      record.followUpScore = MoodEngine.predict(_current, profile: comfortProfile, lightLux: currentLightLux).confidence;
    }
    _savePersistentData();
  }

  @override
  void dispose() { stop(); super.dispose(); }
}