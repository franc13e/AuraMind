typedef SoundLevelCallback = void Function(double db);

/// Non-web fallback.
///
/// AuraMind can read microphone noise in Flutter Web through browser APIs.
/// On Android/iOS/desktop, add a native microphone/noise plugin before enabling
/// real device microphone readings.
class MicrophoneNoiseReader {
  Future<bool> start(SoundLevelCallback onLevel) async => false;
  void stop() {}
}
