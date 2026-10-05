import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform keychain instead of the
/// default plaintext storage. Sessions (access/refresh tokens) therefore never
/// touch unencrypted storage on the device.
///
/// The keychain holds the stringified [Session] JSON under a single key, which
/// is the contract [LocalStorage.accessToken] is defined against: gotrue's
/// `setInitialSession`/`recoverSession` call `json.decode` on this value, so a
/// bare JWT here fails to parse and the session is silently dropped on restart.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'college_project_sb_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _sessionKey);
  }
}
