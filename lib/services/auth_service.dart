// lib/services/auth_service.dart
//
// AuthService — AuraMind runs as an anonymous guest user by default.
// You can extend this later to add Supabase login if you want accounts.

import 'package:flutter/foundation.dart';

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String token;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.token = '',
  });
}

class AuthService extends ChangeNotifier {
  AuthUser? _currentUser;
  final bool _loading = false;

  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get loading => _loading;
  String get patientId => _currentUser?.id ?? 'anonymous';

  /// Called on app start — signs in anonymously so AuraMind works immediately.
  Future<void> tryRestoreSession() async {
    _currentUser = const AuthUser(
      id: 'anonymous',
      name: 'Guest',
      email: '',
    );
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUser = null;
    notifyListeners();
  }
}
