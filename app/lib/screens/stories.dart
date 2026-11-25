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
import '../services/media_cache.dart';
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
    // Telegram: ring and gap scale with the circle (3 dp each at 62 dp)
    final stroke = size < 40 ? 1.8 : 2.8;
    final gap = size < 40 ? 1.6 : 2.8;
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
              // "My story" without a story keeps the same photo size as the others
              padding: EdgeInsets.all(ring || add ? stroke + gap : 0),
              child: Avatar(seed: profile.id, label: profile.name, imageUrl: profile.avatarUrl, size: size),
            ),
          ),
          if (add)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                width: size * 0.36,
                height: size * 0.36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: size * 0.045),
                ),
                child: Icon(Icons.add_rounded, color: Colors.white, size: size * 0.25),
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
      // Telegram's ring: green at the top-left running into sky blue
      p.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4FD866), Color(0xFF38C3C8), Color(0xFF3A9EEF)],
        stops: [0.0, 0.55, 1.0],
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
                          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Image.memory(widget.image!, fit: BoxFit.cover, cacheWidth: 48, filterQuality: FilterQuality.low),
                        ),
                        Container(color: Colors.black26),
                        Image.memory(
                          widget.image!,
                          fit: BoxFit.contain,
                          cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
                        ),
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
  bool _burst = false;

  Future<void> _toggleLike() async {
    final st = _story;
    final v = !st.liked;
    HapticFeedback.lightImpact();
    unawaited(AppScope.read(context).likeStory(st, v));
    setState(() => _burst = v);
    if (v) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _burst = false);
    }
  }

  final _replyFocus = FocusNode();
  final Map<String, String> _urls = {};

  ImageProvider _storyImage(AppController app, String path) => CachedImage('stories/$path', () => app.storyUrl(path));
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
      // kept on the phone after the first view, so it opens again offline
      _urls[st.mediaPath!] = st.mediaPath!;
      try {
        await precacheImage(_storyImage(app, st.mediaPath!), context);
      } catch (_) {}
      if (!mounted || st != _story) return;
      // Fetch the next one in the background.
      if (_i + 1 < _items.length && _items[_i + 1].mediaPath != null) {
        final np = _items[_i + 1].mediaPath!;
        unawaited(MediaCache.instance.bytes('stories/$np', () => app.storyUrl(np)));
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
    final st = _story;
    final chat = await app.openDirect(widget.user.user.id);
    if (chat == null) return;
    // The reply carries the story, so it shows as a quote of that story.
    await app.sendText(
      chat,
      t,
      meta: {
        'story': {'id': st.id, 'owner': widget.user.user.id, 'kind': st.kind, 'body': st.body, 'bg': ?st.bg, 'media_path': ?st.mediaPath, 'k': ?st.key},
      },
    );
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
        child: FutureBuilder<List<({Profile profile, bool liked})>>(
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
                        for (final v in list)
                          ListTile(
                            leading: Avatar(seed: v.profile.id, label: v.profile.name, imageUrl: v.profile.avatarUrl, size: 42),
                            title: Text(v.profile.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(v.profile.username != null ? '@${v.profile.username}' : v.profile.email),
                            trailing: v.liked ? const Icon(Icons.favorite_rounded, color: Color(0xFFFF4D67)) : null,
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
    final app = AppScope.read(context);
    final top = MediaQuery.paddingOf(context).top;

    Widget content;
    if (st.kind == 'image') {
      content = url == null || url.isEmpty
          ? const SizedBox.expand()
          : Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  // a tiny copy stretched up already looks blurred; a light blur smooths it
                  imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Image(image: ResizeImage(_storyImage(app, url), width: 48), fit: BoxFit.cover, filterQuality: FilterQuality.low),
                ),
                Container(color: Colors.black26),
                Image(
                  image: ResizeImage(_storyImage(app, url), width: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round()),
                  fit: BoxFit.contain,
                ),
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
          // big heart when you like
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _burst ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: AnimatedScale(
                  scale: _burst ? 1 : 0.4,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 120,
                    color: Color(0xFFFF4D67),
                    shadows: [Shadow(blurRadius: 24, color: Colors.black38)],
                  ),
                ),
              ),
            ),
          ),
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
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${context.digits(st.views ?? 0)} ${s.get('views')}'),
                            if ((st.likes ?? 0) > 0) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFFF4D67)),
                              const SizedBox(width: 3),
                              Text(context.digits(st.likes!)),
                            ],
                          ],
                        ),
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
                          // empty field: heart (like Telegram); typing: send
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _reply,
                            builder: (_, v, _) => v.text.trim().isEmpty
                                ? IconButton(
                                    tooltip: s.get('like_story'),
                                    onPressed: _toggleLike,
                                    style: IconButton.styleFrom(backgroundColor: Colors.white12, minimumSize: const Size(48, 48)),
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      transitionBuilder: (c, a) => ScaleTransition(
                                        scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                                        child: c,
                                      ),
                                      child: Icon(
                                        st.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        key: ValueKey(st.liked),
                                        color: st.liked ? const Color(0xFFFF4D67) : Colors.white,
                                        size: 27,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: s.get('send'),
                                    onPressed: _sendReply,
                                    style: IconButton.styleFrom(backgroundColor: Brand.blue, minimumSize: const Size(48, 48)),
                                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                                  ),
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
          // Fixed geometry (top 6, ring 62, gap 5, name 18) — the header's
          // fold animation uses the very same numbers, so nothing jumps.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              StoryRing(profile: profile, size: 62, unseen: unseen, seen: seen, add: add),
              const SizedBox(height: 5),
              SizedBox(
                height: 18,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w500, color: unseen || add ? cs.onSurface : cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telegram's folded stories in the title bar: rings overlap, the first in
/// front. Where they cross, the rings run into each other, but each photo
/// behind is cut away around the ring in front, with a thin gap, so the
/// circles stay apart.
class FoldedStoryRings extends StatelessWidget {
  const FoldedStoryRings({super.key, required this.users, required this.unseen, this.size = 36, this.step = 17});
  final List<Profile> users;
  final List<bool> unseen;
  final double size, step;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = users.length;
    final w = size + (n - 1) * step;
    const stroke = 2.0, gap = 2.0, cut = 2.0;
    final inner = size - 2 * (stroke + gap);
    double left(int i) => rtl ? w - size - i * step : i * step;
    final children = <Widget>[];
    // photos, back to front, each cut around every ring in front of it
    for (var i = n - 1; i >= 0; i--) {
      final cuts = [for (var j = 0; j < i; j++) Offset(left(j) - left(i) + size / 2, size / 2)];
      children.add(
        Positioned(
          left: left(i),
          top: 0,
          width: size,
          height: size,
          child: ClipPath(
            clipper: _CutOut(cuts, size / 2 + cut),
            child: Padding(
              padding: const EdgeInsets.all(stroke + gap),
              child: Avatar(seed: users[i].id, label: users[i].name, imageUrl: users[i].avatarUrl, size: inner),
            ),
          ),
        ),
      );
    }
    // rings on top (they may run into each other)
    for (var i = n - 1; i >= 0; i--) {
      children.add(
        Positioned(
          left: left(i),
          top: 0,
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(unseen: unseen[i], stroke: stroke, dark: dark),
          ),
        ),
      );
    }
    return SizedBox(
      width: w,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

class _CutOut extends CustomClipper<Path> {
  _CutOut(this.centers, this.radius);
  final List<Offset> centers;
  final double radius;

  @override
  Path getClip(Size size) {
    var p = Path()..addOval(Offset.zero & size);
    for (final c in centers) {
      p = Path.combine(PathOperation.difference, p, Path()..addOval(Rect.fromCircle(center: c, radius: radius)));
    }
    return p;
  }

  @override
  bool shouldReclip(_CutOut old) => old.centers.length != centers.length || old.radius != radius;
}
