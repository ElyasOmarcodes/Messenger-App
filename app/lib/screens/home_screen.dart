import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import 'call_screen.dart';
import 'calls_screen.dart';
import '../services/notifier.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';
import 'new_chat_sheet.dart';
import 'settings_screen.dart';

/// Wide screens (desktop, tablet, web) get a Telegram-Desktop style
/// two-pane layout; phones get bottom navigation.
const wideBreakpoint = 900.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _selectedChat; // wide layout only
  StreamSubscription<Message>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = AppScope.read(context).incoming.listen(_onIncoming);
      CallScope.read(context).start();
      Notifier.instance.onTap = (payload) {
        if (!mounted || !payload.startsWith('chat:')) return;
        final chat = AppScope.read(context).chatById(payload.substring(5));
        if (chat != null) _openChat(chat);
      };
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onIncoming(Message m) {
    if (!mounted) return;
    final app = AppScope.read(context);
    if (app.openChatId == m.chatId) return;
    final chat = app.chatById(m.chatId);
    if (chat == null) return;
    final sender = app.memberById(chat, m.senderId)?.name ?? '';
    final who = chat.isGroup ? '${app.chatTitle(chat)} · $sender' : sender;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$who: ${app.previewOf(m)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: '›',
            textColor: Brand.accent,
            onPressed: () => _openChat(chat),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= wideBreakpoint;

  void _openChat(Chat chat) {
    if (_wide) {
      setState(() {
        _tab = 0;
        _selectedChat = chat.id;
      });
      AppScope.read(context).openChat(chat.id);
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)));
    }
  }

  Future<void> _newChat() async {
    final chat = await showNewChatSheet(context);
    if (chat != null && mounted) _openChat(chat);
  }

  List<({IconData icon, IconData active, String label})> _destinations(
    BuildContext context,
  ) => [
    (
      icon: Icons.chat_bubble_outline_rounded,
      active: Icons.chat_bubble_rounded,
      label: context.tr('chats'),
    ),
    (
      icon: Icons.call_outlined,
      active: Icons.call_rounded,
      label: context.tr('calls'),
    ),
    (
      icon: Icons.settings_outlined,
      active: Icons.settings_rounded,
      label: context.tr('settings'),
    ),
  ];

  Widget _tabBody() => switch (_tab) {
    0 => ChatsScreen(
      onOpen: _openChat,
      selectedId: _wide ? _selectedChat : null,
    ),
    1 => const CallsScreen(),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final unread = app.totalUnread;
    final dests = _destinations(context);
    Widget badge(Widget icon, int i) => (i == 0 && unread > 0)
        ? Badge(
            label: Text(context.digits(unread)),
            backgroundColor: Brand.accent,
            textColor: Colors.white,
            child: icon,
          )
        : icon;

    if (_wide) return _buildWide(app, dests, badge);

    return Scaffold(
      appBar: _tab == 0
          ? HomeAppBar(onNewChat: _newChat)
          : AppBar(title: Text(dests[_tab].label)),
      body: _tabBody(),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _newChat,
              tooltip: context.tr('new_chat'),
              child: const Icon(Icons.edit_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (var i = 0; i < dests.length; i++)
            NavigationDestination(
              icon: badge(Icon(dests[i].icon), i),
              selectedIcon: badge(Icon(dests[i].active), i),
              label: dests[i].label,
            ),
        ],
      ),
    );
  }

  Widget _buildWide(
    AppController app,
    List<({IconData icon, IconData active, String label})> dests,
    Widget Function(Widget, int) badge,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedChat == null
        ? null
        : app.chatById(_selectedChat!);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Column(
                children: [
                  const PaighamLogo(size: 44),
                  const SizedBox(height: 16),
                  FloatingActionButton.small(
                    heroTag: 'new',
                    elevation: 0,
                    tooltip: context.tr('new_chat'),
                    onPressed: _newChat,
                    child: const Icon(Icons.edit_rounded),
                  ),
                ],
              ),
            ),
            destinations: [
              for (var i = 0; i < dests.length; i++)
                NavigationRailDestination(
                  icon: badge(Icon(dests[i].icon), i),
                  selectedIcon: badge(Icon(dests[i].active), i),
                  label: Text(dests[i].label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 380,
            child: Scaffold(
              appBar: _tab == 0
                  ? HomeAppBar(onNewChat: _newChat, compact: true)
                  : AppBar(title: Text(dests[_tab].label)),
              body: _tabBody(),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? _EmptyPane(color: cs.surfaceContainerLowest)
                : ChatScreen(
                    key: ValueKey(selected.id),
                    chatId: selected.id,
                    embedded: true,
                  ),
          ),
        ],
      ),
    );
  }
}

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key, required this.onNewChat, this.compact = false});
  final VoidCallback onNewChat;
  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final (label, color) = app.realtimeOnline
        ? (context.tr('connected'), const Color(0xFF5BE0A6))
        : (context.tr('connecting'), Brand.accent);
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 16,
      title: Row(
        children: [
          if (!compact) ...[
            const PaighamLogo(size: 34),
            const SizedBox(width: 10),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('app_name'),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (compact)
          IconButton(
            onPressed: onNewChat,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: context.tr('new_chat'),
          ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GirihWallpaper(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PaighamLogo(size: 88),
              const SizedBox(height: 16),
              Text(
                context.tr('app_name'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('tagline'),
                style: const TextStyle(
                  fontSize: 15,
                  color: Brand.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('select_chat'),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
