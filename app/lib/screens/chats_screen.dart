import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_options.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';
import 'stories.dart';

enum _Filter { all, personal, groups, unread }

/// The chat list with a Telegram-style dynamic header:
/// the stories row folds into small rings beside the title as you scroll,
/// and the search box + filter chips slide away when scrolling down and
/// come back as soon as you scroll up. The list runs under the frosted header.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.onOpen, this.selectedId, this.onNewChat, this.wide = false});
  final void Function(Chat) onOpen;
  final String? selectedId;
  final VoidCallback? onNewChat;
  final bool wide;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  String _query = '';
  _Filter _filter = _Filter.all;
  final _scroll = ScrollController();

  /// How much of the search + chips block is hidden (0 = fully shown).
  final _hide = ValueNotifier<double>(0);
  double _last = 0;
  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
    ..addListener(() => _hide.value = _snapFrom + (_snapTo - _snapFrom) * Curves.easeOut.transform(_snap.value));
  double _snapFrom = 0, _snapTo = 0;

  static const _toolbarH = 56.0;
  static const _storiesH = 98.0;
  static const _searchH = 50.0; // search row (slides away on scroll)
  static const _chipsH = _searchH + 46.0; // + folder bar (stays)
  bool _initialFold = false;
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  /// Tap on the small search icon: bring the search row back and focus it.
  void _revealSearch() {
    _snapFrom = _hide.value;
    _snapTo = 0;
    _snap.forward(from: 0);
    Future<void>.delayed(const Duration(milliseconds: 230), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _hide.dispose();
    _snap.dispose();
    _snapTimer?.cancel();
    super.dispose();
  }

  double _dir = 0;
  Timer? _snapTimer;

  /// The chips may hide only as far as the list has scrolled past them,
  /// so no empty gap ever opens between the header and the first chat.
  double _maxHide(double o) => (o - _storiesH).clamp(0.0, _searchH);

  void _onScroll() {
    final o = _scroll.offset;
    final d = o - _last;
    _last = o;
    if (d != 0) _dir = d.sign;
    _snapTimer?.cancel();
    if (_snap.isAnimating) _snap.stop();
    _hide.value = (_hide.value + d).clamp(0.0, _maxHide(o));
  }

  bool _onScrollEnd(ScrollEndNotification n) {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 40), () {
      if (!mounted || !_scroll.hasClients) return;
      // Stories open/close with a snap: past a small pull they finish by themselves.
      final o = _scroll.offset;
      if (o > 0.5 && o < _storiesH - 0.5) {
        final target = _dir > 0 ? (o > _storiesH * 0.15 ? _storiesH : 0.0) : (o < _storiesH * 0.85 ? 0.0 : _storiesH);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        return;
      }
      final h = _hide.value;
      // Never leave the search half-way between field and icon: when scrolling
      // down, carry the list a little further so it can finish turning into the icon.
      if (h > 0 && h < _searchH && _dir > 0) {
        final target = _storiesH + _searchH;
        if (o < target && _scroll.position.maxScrollExtent >= target) {
          _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
          return;
        }
      }
      if (h <= 0 || h >= _searchH || (_dir > 0 && h >= _maxHide(_scroll.offset))) return;
      _snapFrom = h;
      // Scrolling down tucks the chips away (as far as the list allows); scrolling up brings them back.
      _snapTo = _dir > 0 ? _maxHide(_scroll.offset) : 0;
      _snap.forward(from: 0);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final archived = app.chats.where((c) => c.archived).toList();
    final list = app.chats.where((c) {
      if (c.archived && _query.trim().isEmpty) return false;
      switch (_filter) {
        case _Filter.personal:
          if (c.isGroup) return false;
        case _Filter.groups:
          if (!c.isGroup) return false;
        case _Filter.unread:
          if (c.unread == 0) return false;
        case _Filter.all:
          break;
      }
      if (q.isEmpty) return true;
      if (app.chatTitle(c).toLowerCase().contains(q)) return true;
      return c.members.any((m) => m.email.contains(q) || (m.username ?? '').contains(q));
    }).toList();

    final groupsUnread = app.chats.where((c) => c.isGroup).fold<int>(0, (n, c) => n + c.unread);
    final personalUnread = app.totalUnread - groupsUnread;
    final topInset = MediaQuery.paddingOf(context).top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = Theme.of(context).scaffoldBackgroundColor;
    final full = topInset + _toolbarH + _storiesH + _chipsH;
    // Like Telegram: stories start folded beside the title unless someone posted something new.
    if (!_initialFold && app.chatsLoaded) {
      _initialFold = true;
      final fresh = app.stories.any((u) => u.user.id != app.myId && !u.allSeen && u.stories.isNotEmpty);
      if (!fresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients && _scroll.position.maxScrollExtent >= _storiesH) _scroll.jumpTo(_storiesH);
        });
      }
    }
    final field = dark ? const Color(0xFF202B38) : const Color(0xFFEEF1F5);

    // Folder chips share one slim capsule equally, like Telegram; the active
    // one sits on a pill with a thin outline that slides between them.
    final filters = [_Filter.all, _Filter.personal, _Filter.groups, _Filter.unread];
    final folders = Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: field,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: dark ? const Color(0x14FFFFFF) : const Color(0x0A000000)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / filters.length;
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                start: filters.indexOf(_filter) * w,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF26405C) : Brand.blueMist,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withValues(alpha: dark ? 0.28 : 0.22), width: 1),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _chip(context, _Filter.all, 'all', app.totalUnread)),
                  Expanded(child: _chip(context, _Filter.personal, 'personal', personalUnread)),
                  Expanded(child: _chip(context, _Filter.groups, 'groups', groupsUnread)),
                  Expanded(child: _chip(context, _Filter.unread, 'unread', 0)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: _onScrollEnd,
            child: RefreshIndicator(
              edgeOffset: full,
              onRefresh: () async {
                await Future.wait([app.reloadChats(), app.loadStories()]);
              },
              child: CustomScrollView(
                // no Android stretch here: it made the list wobble against the header
                scrollBehavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: full)),
                  if (archived.isNotEmpty && q.isEmpty && _filter == _Filter.all)
                    SliverToBoxAdapter(
                      child: ArchivedRow(
                        chats: archived,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArchivedChatsScreen(onOpen: widget.onOpen))),
                      ),
                    ),
                  if (!app.chatsLoaded)
                    const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                  else if (list.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: Icon(Icons.forum_rounded, size: 48, color: cs.primary),
                            ),
                            const SizedBox(height: 16),
                            Text(context.tr(q.isEmpty ? 'no_chats' : 'no_results'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            if (q.isEmpty && _filter == _Filter.all)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  context.tr('no_chats_sub'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            const SizedBox(height: 90),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      // enough room under short lists so the header can still fold away
                      padding: EdgeInsets.only(
                        bottom: math.max(
                          120.0,
                          MediaQuery.sizeOf(context).height - topInset - _toolbarH - (list.length + (archived.isNotEmpty ? 1 : 0)) * 74.0,
                        ),
                      ),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => SwipeArchive(
                          chat: list[i],
                          child: ChatTile(chat: list[i], selected: list[i].id == widget.selectedId, onTap: () => widget.onOpen(list[i])),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Frosted header drawn over the list.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ListenableBuilder(
            listenable: Listenable.merge([_scroll, _hide]),
            builder: (context, _) {
              final o = _scroll.hasClients ? _scroll.offset.clamp(0.0, double.infinity) : 0.0;
              final t = (o / _storiesH).clamp(0.0, 1.0);
              final storiesNow = _storiesH * (1 - t);
              final hide = _hide.value;
              final height = topInset + _toolbarH + storiesNow + _chipsH - hide;
              return ClipRect(
                // solid page colour, no live blur: the biggest cost while scrolling
                child: BackdropFilter(
                  enabled: false,
                  filter: Glass.filter,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: glass,
                      border: Border(
                        bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: hide >= _searchH ? 1 : 0.6), width: 0.6),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Stories row: slides up, shrinks and fades while folding.
                        Positioned(
                          top: topInset + _toolbarH,
                          left: 0,
                          right: 0,
                          height: storiesNow,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: _storiesH,
                              maxHeight: _storiesH,
                              child: Transform.translate(
                                offset: Offset.zero,
                                child: IgnorePointer(
                                  ignoring: t > 0,
                                  // the moving avatars take over as soon as it starts folding
                                  child: Opacity(
                                    opacity: t > 0 ? 0 : 1,
                                    child: const RepaintBoundary(child: StoriesStrip()),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // …while the folder bar stays.
                        Positioned(top: topInset + _toolbarH + storiesNow + _searchH - hide, left: 0, right: 0, height: 38, child: folders),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: topInset + _toolbarH,
                          child: Container(
                            color: glass.withValues(alpha: t),
                            padding: EdgeInsets.only(top: topInset),
                            child: _Toolbar(
                              t: t,
                              wide: widget.wide,
                              onNewChat: widget.onNewChat,
                              onScrollTop: () => _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                            ),
                          ),
                        ),
                        // Stories: small rings beside the title ⇄ big circles in the row.
                        if (t > 0 && t < 1) _storyMorph(context, app, t, topInset, MediaQuery.sizeOf(context).width),
                        // Search: full field ⇄ small round icon in the title bar.
                        _searchMorph(context, field, topInset, storiesNow, hide, MediaQuery.sizeOf(context).width),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Story avatars glide between the row (open) and the rings beside the
  /// title (folded), growing or shrinking on the way, at fold amount [t].
  Widget _storyMorph(BuildContext context, AppController app, double t, double topInset, double width) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final cs = Theme.of(context).colorScheme;
    final me = app.me;
    final mine = app.myStories;
    final mineHas = mine != null && mine.stories.isNotEmpty;
    final others = [
      for (final u in app.stories)
        if (u.user.id != app.myId && u.stories.isNotEmpty) u,
    ];
    final row = <(Profile, bool, bool, bool, int?)>[]; // profile, unseen, seen, add-badge, folded slot
    var j = 0;
    if (me != null) row.add((me, false, mineHas, !mineHas, mineHas ? j++ : null));
    for (final u in others) {
      row.add((u.user, !u.allSeen, u.allSeen, false, j < 3 ? j++ : null));
    }
    final e = Curves.easeInOutCubic.transform(t);
    double left(double start, double size) => rtl ? width - start - size : start;
    final back = <Widget>[], front = <Widget>[];
    for (var k = 0; k < row.length && k < 7; k++) {
      final (p, unseen, seen, add, f) = row[k];
      final bigStart = 14.0 + k * 74, bigTop = topInset + _toolbarH + 6;
      const bigSize = 62.0;
      double start, top, size, opacity = 1;
      if (f != null) {
        final smallStart = 17.5 + f * 20, smallTop = topInset + 12.5;
        start = bigStart + (smallStart - bigStart) * e;
        top = bigTop + (smallTop - bigTop) * e;
        size = bigSize + (31 - bigSize) * e;
      } else {
        start = bigStart;
        top = bigTop - 36 * e;
        size = bigSize * (1 - 0.3 * e);
        opacity = (1 - e * 1.6).clamp(0.0, 1.0);
      }
      final ring = Positioned(
        left: left(start + (bigSize - size) * 0, size),
        top: top,
        width: size,
        height: size,
        child: Opacity(
          opacity: opacity,
          child: StoryRing(profile: p, size: size, unseen: unseen, seen: seen, add: add && e < 0.5),
        ),
      );
      (f != null ? front : back).add(ring);
      final nameOpacity = (1 - e * 3).clamp(0.0, 1.0);
      if (nameOpacity > 0) {
        back.add(
          Positioned(
            left: left(8.0 + k * 74, 74),
            top: bigTop + bigSize + 5 - 20 * e,
            width: 74,
            height: 18,
            child: Opacity(
              opacity: nameOpacity,
              child: Text(
                me != null && p.id == me.id ? context.tr('my_story') : p.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.3, color: unseen ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ),
          ),
        );
      }
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(clipBehavior: Clip.none, children: [...back, ...front.reversed]),
      ),
    );
  }

  /// The search field shrinks into a round icon in the title bar while you
  /// scroll (Telegram); tapping the icon brings the field back.
  Widget _searchMorph(BuildContext context, Color field, double topInset, double storiesNow, double hide, double width) {
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final e = Curves.easeInOutCubic.transform((hide / _searchH).clamp(0.0, 1.0));
    const fullStart = 12.0;
    final fullTop = topInset + _toolbarH + storiesNow + 2, fullW = width - 24;
    final iconStart = width - 4 - 48 - 2 - 40, iconTop = topInset + 8;
    final start = fullStart + (iconStart - fullStart) * e;
    final top = fullTop + (iconTop - fullTop) * e;
    final w = fullW + (40 - fullW) * e;
    final small = e > 0.55;
    return Positioned(
      left: rtl ? width - start - w : start,
      top: top,
      width: w,
      height: 40,
      child: GestureDetector(
        onTap: small ? _revealSearch : null,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: field, borderRadius: BorderRadius.circular(20)),
          child: small
              ? Semantics(
                  button: true,
                  label: context.tr('search'),
                  child: Center(child: Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 22)),
                )
              : Opacity(
                  opacity: (1 - e * 1.8).clamp(0.0, 1.0),
                  child: OverflowBox(
                    minWidth: fullW,
                    maxWidth: fullW,
                    alignment: AlignmentDirectional.centerStart,
                    child: TextField(
                      controller: _searchCtl,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: context.tr('search'),
                        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 21),
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, _Filter f, String key, int count) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sel = _filter == f;
    return Semantics(
      button: true,
      selected: sel,
      label: context.tr(key),
      excludeSemantics: true,
      onTap: () => setState(() => _filter = f),
      child: GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          color: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  context.tr(key),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: sel ? cs.primary : cs.onSurfaceVariant, fontWeight: sel ? FontWeight.w700 : FontWeight.w600),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(minWidth: 19),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: sel ? cs.primary : (dark ? const Color(0xFF5B6B7C) : const Color(0xFFA9B2BC)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.digits(count),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.t, required this.wide, required this.onNewChat, required this.onScrollTop});
  final double t;
  final bool wide;
  final VoidCallback? onNewChat;
  final VoidCallback onScrollTop;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final shown = [
      if (app.myStories != null && app.myStories!.stories.isNotEmpty) app.myStories!,
      for (final u in storyOrder(app))
        if (u.user.id != app.myId) u,
    ].take(3).toList();
    final fold = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    final archived = app.chats.where((c) => c.archived).length;
    Widget rings = const SizedBox.shrink();
    if (shown.isNotEmpty && fold > 0) {
      rings = Opacity(
        opacity: fold,
        child: Transform.scale(
          scale: 0.6 + 0.4 * fold,
          child: Semantics(
            button: true,
            label: context.tr('stories'),
            excludeSemantics: true,
            onTap: () => openStories(context, shown.first),
            child: GestureDetector(
              onTap: () => openStories(context, shown.first),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: SizedBox(
                  width: 34.0 + (shown.length - 1) * 20,
                  height: 34,
                  child: Stack(
                    children: [
                      for (var i = shown.length - 1; i >= 0; i--)
                        PositionedDirectional(
                          start: i * 20.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                            ),
                            child: StoryRing(
                              profile: shown[i].user,
                              size: 31,
                              unseen: !shown[i].allSeen && shown[i].user.id != app.myId,
                              seen: shown[i].allSeen || shown[i].user.id == app.myId,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          // folded stories sit before the title (Telegram)
          // While folding, the moving avatars are drawn by the header; the title
          // slides aside to make room for them, then the real rings appear.
          if (t >= 0.999) rings else if (shown.isNotEmpty) SizedBox(width: (34.0 + (shown.length - 1) * 20 + 10) * Curves.easeInOutCubic.transform(t)),
          Flexible(
            fit: FlexFit.loose,
            flex: 0,
            child: GestureDetector(
              onTap: onScrollTop,
              child: Text(
                app.realtimeOnline ? context.tr('app_name') : context.tr('connecting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: app.realtimeOnline ? 22 : 18, fontWeight: FontWeight.w800, color: cs.onSurface),
              ),
            ),
          ),
          const Spacer(),
          if (wide && onNewChat != null) IconButton(onPressed: onNewChat, icon: const Icon(Icons.edit_outlined), tooltip: context.tr('new_chat')),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case 'new':
                  onNewChat?.call();
                case 'story':
                  addStory(context);
                case 'saved':
                  openSavedMessages(context);
                case 'archive':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArchivedChatsScreen(
                        onOpen: (c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id))),
                      ),
                    ),
                  );
              }
            },
            itemBuilder: (ctx) {
              PopupMenuItem<String> item(String v, IconData icon, String key) => PopupMenuItem(
                value: v,
                child: Row(
                  children: [
                    Icon(icon, size: 21, color: cs.onSurfaceVariant),
                    const SizedBox(width: 14),
                    Text(ctx.tr(key)),
                  ],
                ),
              );
              return [
                if (onNewChat != null) item('new', Icons.edit_outlined, 'new_chat'),
                item('story', Icons.add_a_photo_outlined, 'add_story'),
                item('saved', Icons.bookmark_border_rounded, 'saved_messages'),
                if (archived > 0) item('archive', Icons.archive_outlined, 'archived_chats'),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({super.key, required this.chat, required this.onTap, this.selected = false});
  final Chat chat;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final last = chat.lastMessage;
    final title = app.chatTitle(chat);
    final s = Strings(context.lang);
    final mine = last != null && last.senderId == app.myId;

    String preview;
    String who = '';
    if (last == null) {
      preview = context.tr(chat.isSaved ? 'saved_hint_short' : 'no_messages');
    } else {
      who = chat.isSaved ? '' : (mine ? '${context.tr('you')}: ' : (chat.isGroup ? '${app.memberById(chat, last.senderId)?.name ?? ''}: ' : ''));
      preview = app.previewOf(last).replaceAll('\n', ' ');
    }
    final read = last != null && mine && !chat.isSaved && app.statusOf(chat, last) == MsgStatus.read;
    final badgeColor = chat.muted ? cs.onSurfaceVariant.withValues(alpha: 0.55) : cs.primary;

    return Material(
      color: selected ? cs.primaryContainer : (chat.pinnedAt != null ? cs.surfaceContainerLow.withValues(alpha: 0.6) : Colors.transparent),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showChatOptions(context, chat),
        onSecondaryTap: () => showChatOptions(context, chat),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 14, 8),
          child: Row(
            children: [
              ChatAvatar(chat: chat, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.isGroup)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Icon(Icons.groups_rounded, size: 17, color: cs.onSurface),
                          ),
                        // the name takes all free room, so the time always sits at the edge
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (chat.muted)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 4),
                                  child: Icon(Icons.volume_off_rounded, size: 16, color: cs.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (mine && !chat.isSaved) ...[
                          Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 17, color: cs.primary),
                          const SizedBox(width: 3),
                        ],
                        if (last != null)
                          Text(
                            chatListTime(last.createdAt, context.lang, s),
                            style: TextStyle(fontSize: 12.5, color: chat.unread > 0 && !chat.muted ? cs.primary : cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (who.isNotEmpty)
                                  TextSpan(
                                    text: who,
                                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                                  ),
                                if (last != null && app.previewIcon(last) != null)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.only(end: 4),
                                      child: Icon(app.previewIcon(last), size: 16, color: cs.primary),
                                    ),
                                  ),
                                TextSpan(text: preview),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                        if (chat.unread > 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 24),
                            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              context.digits(chat.unread),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          )
                        else if (chat.markedUnread)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 8),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                          )
                        else if (chat.pinnedAt != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            child: Transform.rotate(
                              angle: 0.6,
                              child: Icon(Icons.push_pin_rounded, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipe a chat toward the start edge to archive it (or bring it back from the archive).
class SwipeArchive extends StatelessWidget {
  const SwipeArchive({super.key, required this.chat, required this.child});
  final Chat chat;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('swipe-${chat.id}-${chat.archived}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: chat.archived ? cs.primary : const Color(0xFF9AA6B2),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chat.archived ? Icons.unarchive_rounded : Icons.archive_rounded, color: Colors.white),
            const SizedBox(height: 2),
            Text(
              context.tr(chat.archived ? 'unarchive' : 'archive'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        if (chat.archived) {
          await AppScope.read(context).setArchived(chat, false);
        } else {
          await archiveChat(context, chat);
        }
        return true;
      },
      child: child,
    );
  }
}

/// Top row of the list that opens the archive.
class ArchivedRow extends StatelessWidget {
  const ArchivedRow({super.key, required this.chats, required this.onTap});
  final List<Chat> chats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final unread = chats.where((c) => c.unread > 0 || c.markedUnread).length;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 14, 8),
        child: Row(
          children: [
            const ArchiveAvatar(size: 58),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('archived_chats'), style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    chats.map(app.chatTitle).join('، '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                constraints: const BoxConstraints(minWidth: 24),
                decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  context.digits(unread),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ArchivedChatsScreen extends StatelessWidget {
  const ArchivedChatsScreen({super.key, required this.onOpen});
  final void Function(Chat) onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.chats.where((c) => c.archived).toList();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('archived_chats'))),
      body: list.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.archive_outlined, size: 56, color: cs.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Text(context.tr('archive_empty'), style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                  child: Text(context.tr('archive_hint'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ),
                for (final c in list)
                  SwipeArchive(
                    chat: c,
                    child: ChatTile(chat: c, onTap: () => onOpen(c)),
                  ),
              ],
            ),
    );
  }
}
