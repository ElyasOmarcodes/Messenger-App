import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

/// Backgrounds for text stories, stored by name in `stories.bg`.
const storyBackgrounds = <String, List<Color>>{
  'blue': [Color(0xFF5EB5F7), Color(0xFF2470C2)],
  'violet': [Color(0xFFA695E7), Color(0xFF5B45C4)],
  'green': [Color(0xFF7BC862), Color(0xFF23915A)],
  'sunset': [Color(0xFFF7B955), Color(0xFFE5484D)],
  'pink': [Color(0xFFF59AC0), Color(0xFFB4479A)],
  'teal': [Color(0xFF6EC9CB), Color(0xFF1F6F86)],
  'night': [Color(0xFF2B5278), Color(0xFF0E1621)],
};

List<Color> storyGradient(String? bg) => storyBackgrounds[bg] ?? storyBackgrounds['blue']!;

/// Telegram-like ring: blue-to-green when there is something new, grey when seen.
class StoryRing extends StatelessWidget {
  const StoryRing({super.key, required this.profile, required this.size, this.unseen = false, this.seen = false, this.add = false});
  final Profile profile;
  final double size;
  final bool unseen; // gradient ring
  final bool seen; // grey ring
  final bool add; // small "+" badge

  @override
  Widget build(BuildContext context) {
    final ring = unseen || seen;
    final stroke = size < 36 ? 1.6 : 2.4;
    final gap = size < 36 ? 1.6 : 2.6;
    final bg = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ring)
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(unseen: unseen, stroke: stroke, dark: Theme.of(context).brightness == Brightness.dark),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(ring ? stroke + gap : 0),
              child: Avatar(seed: profile.id, label: profile.name, imageUrl: profile.avatarUrl, size: size),
            ),
          ),
          if (add)
            PositionedDirectional(
              end: -1,
              bottom: -1,
              child: Container(
                width: size * 0.34,
                height: size * 0.34,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 2),
                ),
                child: Icon(Icons.add_rounded, color: Colors.white, size: size * 0.24),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.unseen, required this.stroke, required this.dark});
  final bool unseen, dark;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (unseen) {
      p.shader = const SweepGradient(
        colors: [Color(0xFF34C76F), Color(0xFF3DA1FD), Color(0xFF2470C2), Color(0xFF3DA1FD), Color(0xFF34C76F)],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(r);
    } else {
      p.color = dark ? const Color(0xFF4A5868) : const Color(0xFFC4C9CE);
    }
    canvas.drawCircle(r.center, size.width / 2 - stroke / 2, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.unseen != unseen || old.dark != dark;
}

/// Order used by the strip and the viewer: me first (if I have stories), then the feed.
List<StoryUser> storyOrder(AppController app) => [
  for (final u in app.stories)
    if (u.stories.isNotEmpty) u,
];

Future<void> openStories(BuildContext context, StoryUser start) async {
  final app = AppScope.read(context);
  final users = storyOrder(app);
  var i = users.indexWhere((u) => u.user.id == start.user.id);
  if (i < 0) i = 0;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => StoryViewer(users: users, initial: i),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
  unawaited(app.loadStories());
}

/// Asks where the new story comes from, then opens the composer.
Future<void> addStory(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Text(ctx.tr('add_story'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const Spacer(),
                Icon(Icons.schedule_rounded, size: 16, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(ctx.tr('expires_24h'), style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final (icon, color, key) in const [
            (Icons.photo_camera_rounded, Color(0xFF8E6CEF), 'camera'),
            (Icons.photo_library_rounded, Color(0xFF3390EC), 'gallery'),
            (Icons.text_fields_rounded, Color(0xFF31B545), 'text_story'),
          ])
            ListTile(
              leading: CircleAvatar(
                backgroundColor: color,
                child: Icon(icon, color: Colors.white),
              ),
              title: Text(ctx.tr(key), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  Uint8List? bytes;
  String? name;
  if (choice != 'text_story') {
    try {
      final f = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 2160);
      if (f == null) return;
      bytes = await f.readAsBytes();
      name = f.name;
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('err_generic'))));
      return;
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryComposer(image: bytes, imageName: name),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Composer
// ─────────────────────────────────────────────────────────────────────────

class StoryComposer extends StatefulWidget {
  const StoryComposer({super.key, this.image, this.imageName});
  final Uint8List? image;
  final String? imageName;

  @override
  State<StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<StoryComposer> {
  final _text = TextEditingController();
  String _bg = 'blue';
  bool _posting = false;

  bool get _photo => widget.image != null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (!_photo && _text.text.trim().isEmpty) return;
    setState(() => _posting = true);
    final ok = await AppScope.read(context).postStory(image: widget.image, imageName: widget.imageName, text: _text.text, bg: _photo ? null : _bg);
    if (!mounted) return;
    setState(() => _posting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(ok ? 'story_posted' : 'err_generic'))));
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = storyGradient(_bg);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: _photo
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Image.memory(widget.image!, fit: BoxFit.cover),
                        ),
                        Container(color: Colors.black26),
                        Image.memory(widget.image!, fit: BoxFit.contain),
                      ],
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 120),
                      child: TextField(
                        controller: _text,
                        autofocus: true,
                        maxLines: null,
                        maxLength: 700,
                        textAlign: TextAlign.center,
                        cursorColor: Colors.white,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: _text.text.length > 120 ? 22 : 30, fontWeight: FontWeight.w800, color: Colors.white, height: 1.35),
                        decoration: InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: context.tr('story_text_hint'),
                          hintStyle: const TextStyle(color: Colors.white60, fontSize: 28, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
            ),
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      _glassIcon(Icons.close_rounded, context.tr('cancel'), () => Navigator.of(context).pop()),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              context.tr('expires_24h'),
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _photo
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white24),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: TextField(
                                  controller: _text,
                                  maxLines: 4,
                                  minLines: 1,
                                  maxLength: 300,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  cursorColor: Colors.white,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    hintText: context.tr('add_caption'),
                                    hintStyle: const TextStyle(color: Colors.white60),
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: 48,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final e in storyBackgrounds.entries)
                                      Semantics(
                                        button: true,
                                        selected: e.key == _bg,
                                        label: e.key,
                                        child: GestureDetector(
                                          onTap: () => setState(() => _bg = e.key),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 180),
                                            width: 34,
                                            height: 34,
                                            margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(colors: e.value),
                                              border: Border.all(color: Colors.white, width: e.key == _bg ? 3 : 1.2),
                                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: FloatingActionButton(
                          heroTag: null,
                          tooltip: context.tr('post_story'),
                          onPressed: _posting ? null : _post,
                          child: _posting
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Icon(Icons.send_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _glassIcon(IconData icon, String tip, VoidCallback onTap) => IconButton(
  tooltip: tip,
  onPressed: onTap,
  style: IconButton.styleFrom(backgroundColor: Colors.black26),
  icon: Icon(icon, color: Colors.white),
);

// ─────────────────────────────────────────────────────────────────────────
// Viewer
// ─────────────────────────────────────────────────────────────────────────

class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.users, required this.initial});
  final List<StoryUser> users;
  final int initial;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  double _drag = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _nextUser() {
    if (_page + 1 < widget.users.length) {
      _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOut);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prevUser() {
    if (_page > 0) _pages.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final fade = (1 - _drag / 500).clamp(0.0, 1.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => _drag = math.max(0, _drag + d.delta.dy)),
        onVerticalDragEnd: (d) {
          if (_drag > 110 || d.primaryVelocity! > 900) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _drag = 0);
          }
        },
        child: ColoredBox(
          color: Colors.black.withValues(alpha: fade),
          child: AnimatedContainer(
            duration: Duration(milliseconds: _drag == 0 ? 220 : 0),
            curve: Curves.easeOut,
            transform: Matrix4.identity()
              ..translateByDouble(0, _drag, 0, 1)
              ..scaleByDouble(1 - _drag / 1800, 1 - _drag / 1800, 1, 1),
            transformAlignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_drag > 0 ? 24 : 0),
              child: _phoneFrame(
                context,
                PageView.builder(
                  controller: _pages,
                  itemCount: widget.users.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => AnimatedBuilder(
                    animation: _pages,
                    builder: (context, child) {
                      // Cube-like turn between people.
                      var delta = 0.0;
                      if (_pages.hasClients && _pages.position.haveDimensions) delta = (_pages.page ?? _page.toDouble()) - i;
                      final rtl = Directionality.of(context) == TextDirection.rtl;
                      final angle = (rtl ? -1 : 1) * delta.clamp(-1.0, 1.0) * (math.pi / 5);
                      return Transform(
                        alignment: delta > 0 ? (rtl ? Alignment.centerLeft : Alignment.centerRight) : (rtl ? Alignment.centerRight : Alignment.centerLeft),
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(angle),
                        child: child,
                      );
                    },
                    child: _UserStories(
                      key: ValueKey(widget.users[i].user.id),
                      user: widget.users[i],
                      active: i == _page && _drag == 0,
                      onNextUser: _nextUser,
                      onPrevUser: _prevUser,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On wide screens stories sit in a phone-shaped frame in the middle.
Widget _phoneFrame(BuildContext context, Widget child) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < 600) return child;
  final w = math.min(460.0, size.height * 9 / 16);
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: w,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(w, size.height - 32)),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _UserStories extends StatefulWidget {
  const _UserStories({super.key, required this.user, required this.active, required this.onNextUser, required this.onPrevUser});
  final StoryUser user;
  final bool active;
  final VoidCallback onNextUser, onPrevUser;

  @override
  State<_UserStories> createState() => _UserStoriesState();
}

class _UserStoriesState extends State<_UserStories> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  late int _i;
  bool _holding = false;
  bool _ready = false;
  bool _sheet = false;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final Map<String, String> _urls = {};
  late final List<StoryItem> _items = [...widget.user.stories];

  bool get _mine => widget.user.user.id == AppScope.read(context).myId;
  StoryItem get _story => _items[_i];

  @override
  void initState() {
    super.initState();
    // Start from the first story not yet seen.
    final firstNew = widget.user.stories.indexWhere((s) => !s.seen);
    _i = firstNew < 0 ? 0 : firstNew;
    _replyFocus.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(_UserStories old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _progress.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  bool get _paused => !widget.active || _holding || !_ready || _sheet || _replyFocus.hasFocus;

  void _sync() {
    if (!mounted) return;
    if (_paused) {
      _progress.stop();
    } else if (!_progress.isAnimating) {
      _progress.forward();
      final app = AppScope.read(context);
      if (!_mine) app.markStorySeen(_story);
    }
    setState(() {});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _ready = false);
    _progress.stop();
    _progress.value = 0;
    final st = _story;
    if (st.mediaPath != null) {
      final app = AppScope.read(context);
      final url = _urls[st.mediaPath!] ??= (await app.storyUrl(st.mediaPath!)) ?? '';
      if (!mounted || st != _story) return;
      if (url.isNotEmpty) {
        try {
          await precacheImage(NetworkImage(url), context);
        } catch (_) {}
      }
      if (!mounted || st != _story) return;
      // Preload the next one in the background.
      if (_i + 1 < _items.length && _items[_i + 1].mediaPath != null) {
        final np = _items[_i + 1].mediaPath!;
        unawaited(
          app.storyUrl(np).then((u) {
            if (u != null) _urls[np] = u;
          }),
        );
      }
    }
    _ready = true;
    _sync();
  }

  void _next() {
    if (_i + 1 < _items.length) {
      setState(() => _i++);
      _load();
    } else {
      widget.onNextUser();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _load();
    } else if (_progress.value > 0.15) {
      _load();
    } else {
      widget.onPrevUser();
    }
  }

  Future<void> _sendReply() async {
    final t = _reply.text.trim();
    if (t.isEmpty) return;
    _reply.clear();
    _replyFocus.unfocus();
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final sent = context.tr('reply_sent');
    final chat = await app.openDirect(widget.user.user.id);
    if (chat == null) return;
    await app.sendText(chat, t);
    messenger.showSnackBar(SnackBar(content: Text(sent), duration: const Duration(seconds: 2)));
  }

  Future<void> _showViewers() async {
    setState(() => _sheet = true);
    _sync();
    final app = AppScope.read(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
        child: FutureBuilder<List<Profile>>(
          future: app.storyViewers(_story),
          builder: (ctx, snap) {
            final list = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_rounded, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(ctx.tr('story_viewers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (list != null)
                        Text(
                          ctx.digits(list.length),
                          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (list == null)
                  const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
                else if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    child: Column(
                      children: [
                        Icon(Icons.visibility_off_outlined, size: 44, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(ctx.tr('no_views'), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in list)
                          ListTile(
                            leading: Avatar(seed: p.id, label: p.name, imageUrl: p.avatarUrl, size: 42),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(p.username != null ? '@${p.username}' : p.email),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _sheet = false);
    _sync();
  }

  Future<void> _delete() async {
    setState(() => _sheet = true);
    _sync();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(d.tr('delete_story_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _sheet = false);
    if (ok != true) return _sync();
    final st = _story;
    unawaited(AppScope.read(context).deleteStory(st));
    _items.removeAt(_i);
    if (_items.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (_i >= _items.length) _i = _items.length - 1;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final s = Strings(lang);
    final st = _story;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final p = widget.user.user;
    final url = st.mediaPath == null ? null : _urls[st.mediaPath!];
    final top = MediaQuery.paddingOf(context).top;

    Widget content;
    if (st.kind == 'image') {
      content = url == null || url.isEmpty
          ? const SizedBox.expand()
          : Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Image.network(url, fit: BoxFit.cover),
                ),
                Container(color: Colors.black26),
                Image.network(url, fit: BoxFit.contain),
              ],
            );
    } else {
      final g = storyGradient(st.bg);
      content = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 130),
        child: Text(
          st.body,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: st.body.length > 120 ? 22 : 30, fontWeight: FontWeight.w800, height: 1.4),
        ),
      );
    }

    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: content),
          if (!_ready) const Center(child: CircularProgressIndicator(color: Colors.white)),
          // Tap zones: start side goes back, the rest goes forward. Hold to pause.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (_replyFocus.hasFocus) return _replyFocus.unfocus();
                final w = MediaQuery.sizeOf(context).width;
                final back = rtl ? d.localPosition.dx > w * 0.7 : d.localPosition.dx < w * 0.3;
                back ? _prev() : _next();
              },
              onLongPressStart: (_) {
                _holding = true;
                _sync();
              },
              onLongPressEnd: (_) {
                _holding = false;
                _sync();
              },
            ),
          ),
          // Top shade, progress and header.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: false,
              child: AnimatedOpacity(
                opacity: _holding ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: EdgeInsets.fromLTRB(8, top + 8, 4, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x88000000), Color(0x00000000)]),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var k = 0; k < _items.length; k++)
                            Expanded(
                              child: Container(
                                height: 2.6,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                                alignment: AlignmentDirectional.centerStart,
                                child: k < _i
                                    ? Container(
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                                      )
                                    : k == _i
                                    ? AnimatedBuilder(
                                        animation: _progress,
                                        builder: (_, _) => FractionallySizedBox(
                                          widthFactor: _progress.value,
                                          child: Container(
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(width: 6),
                          Avatar(seed: p.id, label: p.name, imageUrl: p.avatarUrl, size: 38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _mine ? s.get('my_story') : p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5),
                                ),
                                Text(_ago(st.createdAt, lang, s), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          if (_mine)
                            IconButton(
                              tooltip: s.get('add_story'),
                              onPressed: () async {
                                setState(() => _sheet = true);
                                _sync();
                                await addStory(context);
                                if (!mounted) return;
                                setState(() => _sheet = false);
                                _sync();
                              },
                              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                            ),
                          if (_mine)
                            IconButton(
                              tooltip: s.get('delete_story'),
                              onPressed: _delete,
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            ),
                          IconButton(
                            tooltip: s.get('close'),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom: caption + reply or views.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _holding ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x99000000), Color(0x00000000)]),
                ),
                padding: EdgeInsets.fromLTRB(12, 30, 12, 12 + MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (st.kind == 'image' && st.body.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          st.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                        ),
                      ),
                    if (_mine)
                      TextButton.icon(
                        onPressed: _showViewers,
                        style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white12, shape: const StadiumBorder()),
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text('${context.digits(st.views ?? 0)} ${s.get('views')}'),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white54),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: TextField(
                                controller: _reply,
                                focusNode: _replyFocus,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white,
                                onSubmitted: (_) => _sendReply(),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  hintText: s.get('reply_story'),
                                  hintStyle: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: s.get('send'),
                            onPressed: _sendReply,
                            style: IconButton.styleFrom(backgroundColor: Brand.blue, minimumSize: const Size(48, 48)),
                            icon: const Icon(Icons.send_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _ago(DateTime t, AppLang lang, Strings s) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return s.get('just_now');
  if (d.inMinutes < 60) return s.get('min_ago', {'n': localDigits('${d.inMinutes}', lang)});
  if (d.inHours < 24) return s.get('hours_ago', {'n': localDigits('${d.inHours}', lang)});
  return hhmm(t, lang);
}

/// The horizontal row of stories shown at the top of the chat list.
class StoriesStrip extends StatelessWidget {
  const StoriesStrip({super.key, this.height = 96});
  final double height;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final me = app.me;
    final mine = app.myStories;
    final others = [
      for (final u in app.stories)
        if (u.user.id != app.myId && u.stories.isNotEmpty) u,
    ];
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          if (me != null)
            _StoryTile(
              profile: me,
              label: context.tr('my_story'),
              unseen: false,
              seen: mine != null && mine.stories.isNotEmpty,
              add: mine == null || mine.stories.isEmpty,
              onTap: () => mine != null && mine.stories.isNotEmpty ? openStories(context, mine) : addStory(context),
              onLongPress: () => addStory(context),
            ),
          for (final u in others) _StoryTile(profile: u.user, label: u.user.name, unseen: !u.allSeen, seen: u.allSeen, onTap: () => openStories(context, u)),
        ],
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.profile,
    required this.label,
    required this.unseen,
    required this.seen,
    this.add = false,
    required this.onTap,
    this.onLongPress,
  });
  final Profile profile;
  final String label;
  final bool unseen, seen, add;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 74,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StoryRing(profile: profile, size: 62, unseen: unseen, seen: seen, add: add),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: unseen ? FontWeight.w700 : FontWeight.w500, color: unseen ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
