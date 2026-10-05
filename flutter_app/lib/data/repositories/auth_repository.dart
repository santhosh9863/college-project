import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/api_client.dart';
import '../../core/security/secure_store.dart';
import '../models/login_result.dart';

/// Orchestrates the login handshake and session lifecycle:
///   1. Call the deployed linways-login Edge Function (password in-memory only).
///   2. Persist the Linways session cookies in secure storage (device-held).
///   3. Establish the real Supabase session via setSession (auto-refresh and
///      signOut revocation work natively; auth.users.id = profiles.id by
///      construction from the server handshake).
class AuthRepository {
  AuthRepository({ApiClient? apiClient, SecureStore? secureStore})
      : _api = apiClient ?? ApiClient(),
        _secureStore = secureStore ?? SecureStore();

  final ApiClient _api;
  final SecureStore _secureStore;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final result = await _api.login(username: username, password: password);
    // Establish the Supabase session first: if it fails there is no signed-in
    // user, and persisting Linways cookies first would leave the device holding
    // session cookies with no matching session.
    await _supabase.auth.setSession(
      result.refreshToken,
      accessToken: result.accessToken,
    );
    await _secureStore.writeLinwaysCookies(result.linwaysSessionCookies);
    return result;
  }

  Session? get currentSession => _supabase.auth.currentSession;

  User? get currentUser => _supabase.auth.currentUser;

  Future<void> logout() async {
    await _supabase.auth.signOut();
    await _secureStore.clearLinwaysCookies();
  }
}
