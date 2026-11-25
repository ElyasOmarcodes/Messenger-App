import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/group_invite.dart';
import '../screens/profile_screen.dart';
import '../services/messenger.dart';

/// Taps on links in messages: web links open in the browser, @username and
/// paigham:// links open inside the app.
Future<void> openLink(BuildContext context, String link) async {
  final app = AppScope.read(context);
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  String? username;
  if (link.startsWith('@')) username = link.substring(1);
  final uri = Uri.tryParse(link.startsWith('www.') ? 'https://$link' : link);
  if (uri != null && uri.scheme == 'paigham') {
    // paigham://u/<username>, paigham://join/<code> (group invite)
    final parts = [uri.host, ...uri.pathSegments].where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2 && parts[0] == 'u') username = parts[1];
    if (parts.length >= 2 && parts[0] == 'join') {
      if (context.mounted) await openGroupInvite(context, parts[1]);
      return;
    }
  }
  if (username != null) {
    final p = await app.findUser('@$username').catchError((_) => null);
    if (p == null) {
      messenger.showSnackBar(SnackBar(content: Text(app.s.get('user_not_found'))));
      return;
    }
    await nav.push(MaterialPageRoute(builder: (_) => ProfileScreen.user(profile: p)));
    return;
  }
  if (link.startsWith('#')) return; // hashtags: nothing yet
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
