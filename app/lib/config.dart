/// Server settings, injected at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=...
/// The anon key is public by design; Row Level Security on the server protects the data.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Storage bucket for photos and files.
  static const attachmentsBucket = 'attachments';

  /// Must match the bucket limit on the server.
  static const maxFileBytes = 50 * 1024 * 1024;
}
