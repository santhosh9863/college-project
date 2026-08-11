import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-held Linways session store (FlutterSecureStorage / platform
/// keychain). Linways cookies are secret material: they are never written to
/// plaintext storage, never logged, and cleared on logout.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _linwaysCookiesKey = 'linways_session_cookies';

  Future<String?> readLinwaysCookies() => _storage.read(key: _linwaysCookiesKey);

  Future<void> writeLinwaysCookies(String cookies) =>
      _storage.write(key: _linwaysCookiesKey, value: cookies);

  Future<void> clearLinwaysCookies() => _storage.delete(key: _linwaysCookiesKey);
}
