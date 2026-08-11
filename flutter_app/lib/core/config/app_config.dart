/// Central application configuration.
///
/// Security notes:
/// - `supabaseAnonKey` is the publishable (anon) key, safe to embed in the
///   app. The service role key is never present in the app.
/// - No credentials, tokens, or cookies are defined here or logged anywhere.
abstract final class AppConfig {
  static const String appName = 'college project';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bvxuvkpmpufsbxvpdkht.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ2eHV2a3BtcHVmc2J4dnBka2h0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzg1MTQsImV4cCI6MjEwMTQxNDUxNH0.U05ruBCN0tzvvB3mcciqSXliIk1vZzsGSPtPLShSqHI',
  );

  /// Deployed linways-login Edge Function (confirmed working endpoint).
  static const String linwaysLoginUrl = String.fromEnvironment(
    'LINWAYS_LOGIN_URL',
    defaultValue:
        'https://bvxuvkpmpufsbxvpdkht.functions.supabase.co/linways-login',
  );

  /// Linways API host (confirmed endpoint:
  /// GET /academics/api/v1/student/get-my-attendance-summary).
  static const String linwaysBaseUrl = 'https://sfcv4.linways.com';

  /// In-memory attendance cache TTL (LINWAYS_INTEGRATION_ARCHITECTURE.md §F:
  /// ~10–30 min; last known value shown when Linways is unreachable).
  static const Duration attendanceCacheTtl = Duration(minutes: 30);

  static const Duration linwaysAttendanceTimeout = Duration(seconds: 20);

  static const Duration loginTimeout = Duration(seconds: 90);
}
