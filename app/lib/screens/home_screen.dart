import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:flutter/services.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../services/notifier.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';
import 'contacts_screen.dart';
import 'new_chat_sheet.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'stories.dart';

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
      ..showSnackBar(
        SnackBar(
          content: Text('$who: ${app.previewOf(m)}', maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(label: '›', textColor: Brand.blueBright, onPressed: () => openChat(chat)),
          duration: const Duration(seconds: 3),
        ),
      );
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
    // round, filled icons (like Telegram's tab bar); the colour shows the chosen tab
    NavItem(CupertinoIcons.chat_bubble_2_fill, CupertinoIcons.chat_bubble_2_fill, context.tr('chats')),
    NavItem(CupertinoIcons.person_2_fill, CupertinoIcons.person_2_fill, context.tr('contacts')),
    NavItem(CupertinoIcons.gear_solid, CupertinoIcons.gear_solid, context.tr('settings')),
    NavItem(
      CupertinoIcons.person_crop_circle_fill,
      CupertinoIcons.person_crop_circle_fill,
      context.tr('profile_tab'),
      custom: AppScope.read(context).me == null
          ? null
          : (sel, color) {
              final me = AppScope.read(context).me!;
              return Container(
                padding: const EdgeInsets.all(1.6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? color : Colors.transparent, width: 1.8),
                ),
                child: Avatar(seed: me.id, label: me.name, imageUrl: me.avatarUrl, size: 24),
              );
            },
    ),
  ];

  Widget _tabBody() => switch (_tab) {
    0 => ChatsScreen(onOpen: openChat, selectedId: _wide ? _selectedChat : null, onNewChat: _newChat, wide: _wide),
    1 => ContactsScreen(onOpen: openChat),
    2 => const SettingsScreen(),
    _ => const ProfileScreen.me(),
  };

  PreferredSizeWidget? _appBar(BuildContext context) {
    final items = _items(context);
    return switch (_tab) {
      0 || 2 || 3 => null,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // small story camera above the main button (Telegram)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: FloatingActionButton(
                      heroTag: 'story-fab',
                      elevation: 2,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      tooltip: context.tr('add_story'),
                      onPressed: () => addStory(context),
                      child: const Icon(Icons.photo_camera_outlined, size: 22),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FloatingActionButton(heroTag: 'new-fab', onPressed: _newChat, tooltip: context.tr('new_chat'), child: const Icon(Icons.add_comment_rounded)),
                ],
              ),
            )
          : null,
      bottomNavigationBar: PillNavBar(items: items, index: _tab, badges: {0: app.totalUnread}, onTap: (i) => setState(() => _tab = i)),
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
              child: Column(
                children: [
                  const PaighamLogo(size: 42),
                  const SizedBox(height: 18),
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
              for (var i = 0; i < items.length; i++)
                NavigationRailDestination(
                  icon: _badge(Icon(items[i].icon), i == 0 ? unread : 0),
                  selectedIcon: _badge(Icon(items[i].active), i == 0 ? unread : 0),
                  label: Text(items[i].label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          SizedBox(
            width: 390,
            child: Scaffold(appBar: _appBar(context), body: _tabBody()),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          Expanded(
            child: selected == null ? const _EmptyPane() : ChatScreen(key: ValueKey(selected.id), chatId: selected.id, embedded: true),
          ),
        ],
      ),
    );
  }

  Widget _badge(Widget icon, int n) =>
      n <= 0 ? icon : Badge(label: Text(context.digits(n)), backgroundColor: Theme.of(context).colorScheme.primary, textColor: Colors.white, child: icon);
}

class NavItem {
  const NavItem(this.icon, this.active, this.label, {this.custom});
  final IconData icon, active;
  final String label;

  /// Draws something other than an icon (e.g. the profile photo).
  final Widget Function(bool selected, Color color)? custom;
}

/// Telegram-style floating glass tab bar: a frosted capsule with a pill that
/// slides to the chosen tab, and icons that bounce when picked.
class PillNavBar extends StatelessWidget {
  const PillNavBar({super.key, required this.items, required this.index, required this.onTap, this.badges = const {}});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;

  /// Each tab has a fixed width, so the bar keeps its size on every screen.
  static const double itemWidth = 80;
  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = Theme.of(context).scaffoldBackgroundColor;
    if (GlassScope.of(context)) return _liquid(context, dark);
    final barW = items.length * itemWidth + 8;
    Widget capsule = Container(
      width: barW,
      height: height,
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          // sliding lens under the selected tab
          AnimatedPositionedDirectional(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            start: index * itemWidth,
            top: 0,
            bottom: 0,
            width: itemWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(color: dark ? const Color(0xFF253A50) : const Color(0xFFE6F0FB), borderRadius: BorderRadius.circular((height - 8) / 2)),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: itemWidth,
                  child: _PillItem(item: items[i], selected: i == index, badge: badges[i] ?? 0, onTap: () => onTap(i)),
                ),
            ],
          ),
        ],
      ),
    );
    // iOS 27 liquid glass capsule (solid when glass is off)
    capsule = LiquidGlass(radius: height / 2, child: capsule);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The list fades out gradually toward the bottom edge behind the bar.
        Positioned(
          left: 0,
          right: 0,
          top: -48,
          bottom: 0,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [page.withValues(alpha: 0), page.withValues(alpha: 0.6), page.withValues(alpha: 0.92), page],
                  stops: const [0, 0.35, 0.7, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: capsule,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on PillNavBar {
  /// Apple's Liquid Glass tab bar: a glass capsule with a clear liquid lens
  /// that slides (with a little jelly) to the chosen tab.
  Widget _liquid(BuildContext context, bool dark) {
    final cs = Theme.of(context).colorScheme;
    Widget icon(int i, bool sel) {
      final it = items[i];
      final color = sel ? cs.primary : cs.onSurface;
      final w = it.custom?.call(sel, color) ?? Icon(sel ? it.active : it.icon, color: color, size: 26);
      final n = badges[i] ?? 0;
      return n <= 0 ? w : Badge(label: Text(context.digits(n)), backgroundColor: cs.primary, textColor: Colors.white, child: w);
    }

    return lg.GlassTabBar.bottom(
      tabs: [for (var i = 0; i < items.length; i++) lg.GlassTab(icon: icon(i, false), activeIcon: icon(i, true), label: items[i].label)],
      selectedIndex: index,
      onTabSelected: onTap,
      barHeight: 62,
      horizontalPadding: 18,
      verticalPadding: 10,
      labelFontSize: 11,
      selectedIconColor: cs.primary,
      unselectedIconColor: cs.onSurface,
      selectedLabelColor: cs.primary,
      unselectedLabelColor: cs.onSurface,
      settings: dark ? lg.LiquidGlassSettings.ios27Dark : lg.LiquidGlassSettings.ios27Light,
      indicatorSettings: lg.LiquidGlassSettings.ios27Indicator,
    );
  }
}

class _PillItem extends StatefulWidget {
  const _PillItem({required this.item, required this.selected, required this.badge, required this.onTap});
  final NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_PillItem> createState() => _PillItemState();
}

class _PillItemState extends State<_PillItem> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), value: 1);

  @override
  void didUpdateWidget(_PillItem old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.selected ? cs.primary : (dark ? const Color(0xFFE4E9EE) : const Color(0xFF2A2F35));
    Widget icon = widget.item.custom?.call(widget.selected, color) ?? Icon(widget.selected ? widget.item.active : widget.item.icon, color: color, size: 25);
    icon = AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) {
        // quick squash, then spring back with a small overshoot
        final v = _bounce.value;
        final s = v < 0.25 ? 1 - 0.18 * (v / 0.25) : 0.82 + 0.18 * Curves.elasticOut.transform((v - 0.25) / 0.75);
        return Transform.scale(scale: s, child: child);
      },
      child: icon,
    );
    if (widget.badge > 0) {
      icon = Badge(
        label: Text(context.digits(widget.badge > 99 ? '99+' : widget.badge)),
        backgroundColor: cs.primary,
        textColor: Colors.white,
        offset: const Offset(12, -5),
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 1),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 12,
                height: 1.2,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
              child: Text(widget.item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
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
          child: Text(
            context.tr('select_chat'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
