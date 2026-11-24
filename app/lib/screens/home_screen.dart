import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../services/notifier.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';
import 'contacts_screen.dart';
import 'new_chat_sheet.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// Wide screens (desktop, tablet, web) get a Telegram-Desktop style
/// two-pane layout; phones get the floating bottom bar.
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
        if (chat != null) openChat(chat);
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
      ..showSnackBar(SnackBar(
        content: Text('$who: ${app.previewOf(m)}', maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: '›', textColor: Brand.blueBright, onPressed: () => openChat(chat)),
        duration: const Duration(seconds: 3),
      ));
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= wideBreakpoint;

  void openChat(Chat chat) {
    if (_wide) {
      setState(() {
        _tab = 0;
        _selectedChat = chat.id;
      });
      AppScope.read(context).openChat(chat.id);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)));
    }
  }

  Future<void> _newChat() async {
    final chat = await showNewChatSheet(context);
    if (chat != null && mounted) openChat(chat);
  }

  List<NavItem> _items(BuildContext context) => [
        NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, context.tr('chats')),
        NavItem(Icons.person_outline_rounded, Icons.person_rounded, context.tr('contacts')),
        NavItem(Icons.settings_outlined, Icons.settings_rounded, context.tr('settings')),
        NavItem(Icons.account_circle_outlined, Icons.account_circle, context.tr('profile_tab')),
      ];

  Widget _tabBody() => switch (_tab) {
        0 => ChatsScreen(onOpen: openChat, selectedId: _wide ? _selectedChat : null),
        1 => ContactsScreen(onOpen: openChat),
        2 => const SettingsScreen(),
        _ => const ProfileScreen.me(),
      };

  PreferredSizeWidget? _appBar(BuildContext context) {
    final items = _items(context);
    return switch (_tab) {
      0 => ChatsAppBar(onNewChat: _newChat, wide: _wide),
      3 => null,
      _ => AppBar(title: Text(items[_tab].label)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final items = _items(context);
    if (_wide) return _buildWide(app, items);
    return Scaffold(
      extendBody: true,
      appBar: _appBar(context),
      body: _tabBody(),
      floatingActionButton: _tab == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton(onPressed: _newChat, tooltip: context.tr('new_chat'), child: const Icon(Icons.edit_rounded)),
            )
          : null,
      bottomNavigationBar: PillNavBar(
        items: items,
        index: _tab,
        badges: {0: app.totalUnread},
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Widget _buildWide(AppController app, List<NavItem> items) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedChat == null ? null : app.chatById(_selectedChat!);
    final unread = app.totalUnread;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: cs.surface,
            indicatorColor: cs.primaryContainer,
            leading: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 18),
              child: Column(children: [
                const PaighamLogo(size: 42),
                const SizedBox(height: 18),
                FloatingActionButton.small(
                    heroTag: 'new', elevation: 0, tooltip: context.tr('new_chat'), onPressed: _newChat, child: const Icon(Icons.edit_rounded)),
              ]),
            ),
            destinations: [
              for (var i = 0; i < items.length; i++)
                NavigationRailDestination(
                  icon: _badge(Icon(items[i].icon), i == 0 ? unread : 0),
                  selectedIcon: _badge(Icon(items[i].active), i == 0 ? unread : 0),
                  label: Text(items[i].label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          SizedBox(width: 390, child: Scaffold(appBar: _appBar(context), body: _tabBody())),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          Expanded(
            child: selected == null ? const _EmptyPane() : ChatScreen(key: ValueKey(selected.id), chatId: selected.id, embedded: true),
          ),
        ],
      ),
    );
  }

  Widget _badge(Widget icon, int n) => n <= 0
      ? icon
      : Badge(label: Text(context.digits(n)), backgroundColor: Theme.of(context).colorScheme.primary, textColor: Colors.white, child: icon);
}

class NavItem {
  const NavItem(this.icon, this.active, this.label);
  final IconData icon, active;
  final String label;
}

/// Telegram-style floating, translucent bottom bar.
class PillNavBar extends StatelessWidget {
  const PillNavBar({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: (dark ? const Color(0xFF1E2C3A) : Colors.white).withValues(alpha: dark ? 0.92 : 0.94),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: dark ? const Color(0x22FFFFFF) : const Color(0x14000000)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _PillItem(
                        item: items[i],
                        selected: i == index,
                        badge: badges[i] ?? 0,
                        onTap: () => onTap(i),
                        color: i == index ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({required this.item, required this.selected, required this.badge, required this.onTap, required this.color});
  final NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget icon = Icon(selected ? item.active : item.icon, color: color, size: 26);
    if (badge > 0) {
      icon = Badge(
        label: Text(context.digits(badge)),
        backgroundColor: cs.primary,
        textColor: Colors.white,
        offset: const Offset(10, -6),
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header of the chats tab: name or "Connecting...", search.
class ChatsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatsAppBar({super.key, required this.onNewChat, this.wide = false});
  final VoidCallback onNewChat;
  final bool wide;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 18,
      title: Row(
        children: [
          if (!wide) ...[const PaighamLogo(size: 34), const SizedBox(width: 12)],
          Flexible(
            child: Text(
              app.realtimeOnline ? context.tr('app_name') : context.tr('connecting'),
              style: TextStyle(fontSize: app.realtimeOnline ? 22 : 19, fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
          ),
        ],
      ),
      actions: [
        if (wide) IconButton(onPressed: onNewChat, icon: const Icon(Icons.edit_outlined), tooltip: context.tr('new_chat')),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    return GirihWallpaper(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(18)),
          child: Text(context.tr('select_chat'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
