import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'calls_screen.dart';
import 'new_chat_sheet.dart';
import 'profile_screen.dart';

/// People you chat with, plus call history.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.onOpen});
  final void Function(Chat) onOpen;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _calls = false;

  Future<void> _add() async {
    final app = AppScope.read(context);
    final p = await showDialog<Profile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('add_contact')),
        content: SizedBox(
          width: 420,
          child: PersonFinder(buttonKey: 'find', onFound: (p) => Navigator.pop(ctx, p)),
        ),
      ),
    );
    if (p == null) return;
    final chat = await app.startDirectChat(p);
    if (chat != null && mounted) widget.onOpen(chat);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final people = <String, (Profile, Chat?)>{};
    for (final c in app.chats) {
      for (final m in c.members) {
        if (m.id == app.myId) continue;
        final direct = !c.isGroup ? c : people[m.id]?.$2;
        people[m.id] = (m, direct);
      }
    }
    final list = people.values.toList()..sort((a, b) => a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase()));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, icon: const Icon(CupertinoIcons.person_2_fill), label: Text(context.tr('contacts'))),
              ButtonSegment(value: true, icon: const Icon(CupertinoIcons.phone_fill), label: Text(context.tr('calls'))),
            ],
            selected: {_calls},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _calls = v.first),
          ),
        ),
        Expanded(
          child: _calls
              ? const CallsScreen()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 110),
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: cs.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.person_add_rounded, color: cs.primary),
                      ),
                      title: Text(
                        context.tr('add_contact'),
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                      onTap: _add,
                    ),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          context.tr('contacts_empty'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final (p, chat) in list)
                      ListTile(
                        leading: Avatar(seed: p.id, label: p.name, imageUrl: p.avatarUrl, size: 48),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(p.username != null ? '@${p.username}' : p.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen.user(profile: p, chatId: chat?.id),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
