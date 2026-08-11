import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/auth_exceptions.dart';
import '../data/models/community.dart';
import '../data/models/login_result.dart';
import '../data/models/profile.dart';
import '../data/repositories/auth_repository.dart';

enum AuthStatus {
  /// Restoring a persisted Supabase session at startup.
  restoring,

  /// No session; the login screen is shown.
  signedOut,

  /// A login request is in flight.
  signingIn,

  /// A real Supabase session is active.
  signedIn,
}

/// App-level authentication state machine backed by [AuthRepository].
class AuthController extends ChangeNotifier {
  AuthController({required AuthRepository repository})
      : _repository = repository {
    _restore();
  }

  final AuthRepository _repository;

  AuthStatus _status = AuthStatus.restoring;
  Profile? _profile;
  Community? _community;
  LoginException? _error;

  AuthStatus get status => _status;
  Profile? get profile => _profile;
  Community? get community => _community;
  LoginException? get error => _error;
  bool get isBusy => _status == AuthStatus.restoring || _status == AuthStatus.signingIn;

  /// The authenticated Supabase user (available after a session restore even
  /// before a fresh login response refreshes the cached profile).
  User? get currentUser => _repository.currentUser;

  Future<void> _restore() async {
    final session = _repository.currentSession;
    _status = session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    _status = AuthStatus.signingIn;
    _error = null;
    notifyListeners();
    try {
      final LoginResult result =
          await _repository.login(username: username, password: password);
      _profile = result.profile;
      _community = result.community;
      _status = AuthStatus.signedIn;
    } on LoginException catch (error) {
      _error = error;
      _status = AuthStatus.signedOut;
    } catch (_) {
      _error = const LoginException(LoginFailureKind.unexpected);
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      _profile = null;
      _community = null;
      _error = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }
}
