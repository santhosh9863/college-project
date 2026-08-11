import 'community.dart';
import 'profile.dart';

/// Parsed login response from the linways-login Edge Function.
///
/// The response shape is the documented one:
/// ```
/// { success, data: { supabase_session: { access_token, refresh_token },
///   profile, community|null, linways_session_cookies } }
/// ```
/// Defensive parsing only: unknown/extra fields are ignored, required fields
/// missing cause a [FormatException].
class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.profile,
    this.community,
    required this.linwaysSessionCookies,
  });

  final String accessToken;
  final String refreshToken;
  final Profile profile;

  /// Null when the server could not derive a community (community_pending);
  /// community assignment is server-derived and never client-selected.
  final Community? community;

  /// Linways AUTH_SESSION/refresh cookie string for direct Linways API use.
  /// Held in secure storage only; never logged.
  final String linwaysSessionCookies;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final session = data['supabase_session'] is Map<String, dynamic>
        ? data['supabase_session'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final profileJson = data['profile'] is Map<String, dynamic>
        ? data['profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final communityJson = data['community'];

    final profile = Profile.fromJson(profileJson);
    if (!profile.isValid) {
      throw const FormatException('malformed login response: profile missing');
    }

    final accessToken = session['access_token'];
    final refreshToken = session['refresh_token'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const FormatException('malformed login response: session missing');
    }

    return LoginResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      profile: profile,
      community: communityJson is Map<String, dynamic>
          ? Community.fromJson(communityJson)
          : null,
      linwaysSessionCookies:
          data['linways_session_cookies'] is String
              ? data['linways_session_cookies'] as String
              : '',
    );
  }
}
