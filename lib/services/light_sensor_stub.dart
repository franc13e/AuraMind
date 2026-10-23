typedef LightLevelCallback = void Function(double lux);

/// Non-web fallback.
///
/// AuraMind can read ambient light in Flutter Web through browser APIs.
/// On Android/iOS/desktop, add a native light sensor plugin before enabling
/// real device light readings.
class AmbientLightReader {
  Future<bool> start(LightLevelCallback onLevel) async => false;
  void stop() {}
}
