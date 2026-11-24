import 'package:shared_preferences/shared_preferences.dart';

/// Server settings. Either baked in at build time:
///   flutter build apk --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=...
/// or typed once on the app's "Server" screen (saved on the device).
/// The anon key is public by design; Row Level Security on the server protects the data.
class AppConfig {
  static String supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  static String supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> load() async {
    if (configured) return;
    final p = await SharedPreferences.getInstance();
    supabaseUrl = p.getString('server_url') ?? '';
    supabaseAnonKey = p.getString('server_key') ?? '';
  }

  static Future<void> save(String url, String key) async {
    supabaseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    supabaseAnonKey = key.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('server_url', supabaseUrl);
    await p.setString('server_key', supabaseAnonKey);
  }

  /// Storage bucket for photos and files.
  static const attachmentsBucket = 'attachments';

  /// Must match the bucket limit on the server.
  static const maxFileBytes = 50 * 1024 * 1024;
}
