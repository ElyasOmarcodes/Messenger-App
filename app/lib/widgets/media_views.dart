import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/media_cache.dart';
import '../services/messenger.dart';
import 'message_bubble.dart' show MsgAction;

/// Fits a photo of w×h into the bubble: keeps its shape, never too thin or tall.
Size photoBox(double? w, double? h, {double maxW = 270, double maxH = 340, double minW = 150}) {
  if (w == null || h == null || w <= 0 || h <= 0) return Size(maxW, maxW * 0.75);
  final ratio = (w / h).clamp(0.5, 2.2);
  var bw = maxW, bh = bw / ratio;
  if (bh > maxH) {
    bh = maxH;
    bw = math.max(minW, bh * ratio);
  }
  return Size(bw, bh);
}

/// Hero tag shared by a photo in a bubble and the same photo in the viewer.
Object photoHeroTag(({String? path, Uint8List? bytes}) item) => item.path != null ? 'photo:${item.path}' : 'photo-local:${identityHashCode(item.bytes)}';

/// Loads a private attachment (or shows local bytes while uploading).
/// The picture is decoded at the size it is shown, not at full camera size,
/// and the link is fetched once, so scrolling stays smooth.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({super.key, this.path, this.bytes, this.fit = BoxFit.cover, this.full = false, this.size});
  final String? path;
  final Uint8List? bytes;
  final BoxFit fit;

  /// Full-screen viewer: decode at screen size.
  final bool full;

  /// File size, shown on the download button.
  final int? size;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  bool _force = false; // tapped "download" while auto-download is off
  bool _stopped = false; // tapped X while it was downloading

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final placeholder = Container(color: Colors.black26);
    return LayoutBuilder(
      builder: (context, c) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = c.hasBoundedWidth ? c.maxWidth : MediaQuery.sizeOf(context).width;
        final h = c.hasBoundedHeight ? c.maxHeight : MediaQuery.sizeOf(context).height;
        // decode just big enough for the box (or the screen, in the viewer)
        final px = (math.max(w, h) * dpr).clamp(64, 2400).round();
        if (widget.bytes != null) {
          return Image.memory(widget.bytes!, fit: widget.fit, gaplessPlayback: true, cacheWidth: px);
        }
        final path = widget.path;
        if (path == null) return placeholder;
        final small = w < 120 || h < 120;
        final want = (app.autoPhotos || _force || widget.full) && !_stopped;
        // not on the phone and not wanted yet: a download button (with the size)
        if (!want && !MediaCache.instance.has(path)) {
          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              Center(
                child: DownloadRing(
                  cacheKey: path,
                  size: small ? 36 : 48,
                  onStart: () => setState(() {
                    _force = true;
                    _stopped = false;
                  }),
                ),
              ),
              if (widget.size != null && !small) PositionedDirectional(top: 8, start: 8, child: _SizePill(bytes: widget.size!)),
            ],
          );
        }
        return Image(
          // from the phone if we already have it, else downloaded once and kept
          image: ResizeImage.resizeIfNeeded(px, null, CachedImage(path, () => app.fileUrl(path))),
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, sync) => sync || frame != null
              ? child
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    placeholder,
                    // the ring fills while it downloads; X stops it
                    Center(
                      child: DownloadRing(
                        cacheKey: path,
                        size: small ? 36 : 48,
                        onStart: () {},
                        showIdle: false,
                        onCancel: () => setState(() => _stopped = true),
                      ),
                    ),
                  ],
                ),
          errorBuilder: (_, _, _) => GestureDetector(
            onTap: () => setState(() {
              _stopped = false;
              _force = true;
            }),
            child: Container(
              color: Colors.black26,
              child: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

class _SizePill extends StatelessWidget {
  const _SizePill({required this.bytes});
  final int bytes;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
    child: Text('\u2066${localDigits(formatBytes(bytes), context.lang)}\u2069', style: const TextStyle(color: Colors.white, fontSize: 12)),
  );
}

/// Telegram-style round download control: an arrow to start, a ring that
/// fills while the file arrives (tap it to stop), and [done] once the file
/// is on the phone.
class DownloadRing extends StatelessWidget {
  const DownloadRing({
    super.key,
    required this.cacheKey,
    required this.onStart,
    this.onCancel,
    this.size = 48,
    this.background = Colors.black45,
    this.done,
    this.idleIcon = Icons.download_rounded,
    this.showIdle = true,
  });
  final String cacheKey;
  final VoidCallback onStart;
  final VoidCallback? onCancel;
  final double size;
  final Color background;
  final Widget? done;
  final IconData idleIcon;

  /// false: nothing until a download is really running (photos read from disk).
  final bool showIdle;

  @override
  Widget build(BuildContext context) {
    final cache = MediaCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final prog = cache.progressOf(cacheKey);
        if (prog == null && done != null && cache.has(cacheKey)) return done!;
        if (prog == null && !showIdle) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: prog == null
              ? onStart
              : () {
                  cache.cancel(cacheKey);
                  onCancel?.call();
                },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: background, shape: BoxShape.circle),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (prog != null)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: ValueListenableBuilder<double>(
                      valueListenable: prog,
                      builder: (_, v, _) => TweenAnimationBuilder<double>(
                        tween: Tween(end: v),
                        duration: const Duration(milliseconds: 200),
                        builder: (_, a, _) =>
                            CircularProgressIndicator(value: a < 0.02 ? null : a, strokeWidth: 2.6, strokeCap: StrokeCap.round, color: Colors.white),
                      ),
                    ),
                  ),
                Icon(prog == null ? idleIcon : Icons.close_rounded, color: Colors.white, size: size * 0.5),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What the photo viewer can do with the message a photo belongs to.
class ViewerActions {
  const ViewerActions({this.chat, this.onAction, this.onShowInChat, this.onShowAll});
  final Chat? chat;
  final void Function(Message, MsgAction)? onAction;
  final void Function(Message)? onShowInChat;
  final VoidCallback? onShowAll;
}

enum _ViewerMenu { gallery, all, inChat, reply, share, delete }

/// Telegram-style photo viewer: sender and time on top, forward / draw / ⋮,
/// swipe between photos, pinch to zoom, drag down to close.
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({super.key, required this.items, this.initial = 0, this.messages, this.actions});
  final List<({String? path, Uint8List? bytes})> items;
  final int initial;

  /// The message each photo comes from (same length as [items]), if known.
  final List<Message?>? messages;
  final ViewerActions? actions;

  static void open(BuildContext context, List<({String? path, Uint8List? bytes})> items, int i, {List<Message?>? messages, ViewerActions? actions}) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => GalleryViewer(items: items, initial: i, messages: messages, actions: actions),
      ),
    );
  }

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late int _i = widget.initial;
  late final _ctl = PageController(initialPage: widget.initial);
  final _zoom = TransformationController();
  bool _bars = true;
  bool _zoomed = false;
  double _drag = 0;
  String? _note;
  Timer? _noteTimer;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _zoom.dispose();
    _noteTimer?.cancel();
    super.dispose();
  }

  Message? get _msg {
    final ms = widget.messages;
    return ms == null || _i >= ms.length ? null : ms[_i];
  }

  void _toast(String key) {
    _noteTimer?.cancel();
    setState(() => _note = context.tr(key));
    _noteTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<Uint8List?> _bytes() async {
    final it = widget.items[_i];
    if (it.bytes != null) return it.bytes;
    final p = it.path;
    if (p == null) return null;
    final app = AppScope.read(context);
    return MediaCache.instance.bytes(p, () => app.fileUrl(p));
  }

  String get _name {
    final p = widget.items[_i].path;
    final n = p?.split('/').last ?? 'photo.jpg';
    return n.contains('.') ? n : '$n.jpg';
  }

  Future<void> _saveToGallery() async {
    if (kIsWeb) {
      // the decrypted photo as a download (the link would give ciphertext)
      final b = await _bytes();
      if (b != null) await launchUrl(Uri.dataFromBytes(b, mimeType: mimeFor(_name)));
      return;
    }
    final b = await _bytes();
    if (b == null) return _toast('err_generic');
    try {
      await Gal.putImageBytes(b, album: 'Paigham', name: 'Paigham-${DateTime.now().millisecondsSinceEpoch}');
      _toast('saved_gallery');
    } catch (_) {
      _toast('err_generic');
    }
  }

  Future<void> _share() async {
    final b = await _bytes();
    if (b == null) return _toast('err_generic');
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(b, name: _name, mimeType: mimeFor(_name))],
          fileNameOverrides: [_name],
        ),
      );
    } catch (_) {
      _toast('err_generic');
    }
  }

  Future<void> _draw() async {
    final chat = widget.actions?.chat;
    final b = await _bytes();
    if (b == null || chat == null || !mounted) return;
    final app = AppScope.read(context);
    final out = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => PhotoDrawScreen(bytes: b)));
    if (out == null || !mounted) return;
    Navigator.of(context).pop();
    await app.sendPhotos(chat, [(name: 'photo-${DateTime.now().millisecondsSinceEpoch}.png', bytes: out)]);
  }

  void _menu(_ViewerMenu v) {
    final m = _msg;
    final a = widget.actions;
    switch (v) {
      case _ViewerMenu.gallery:
        _saveToGallery();
      case _ViewerMenu.share:
        _share();
      case _ViewerMenu.all:
        Navigator.of(context).pop();
        a?.onShowAll?.call();
      case _ViewerMenu.inChat:
        Navigator.of(context).pop();
        if (m != null) a?.onShowInChat?.call(m);
      case _ViewerMenu.reply:
        Navigator.of(context).pop();
        if (m != null) a?.onAction?.call(m, MsgAction.reply);
      case _ViewerMenu.delete:
        Navigator.of(context).pop();
        if (m != null) a?.onAction?.call(m, MsgAction.delete);
    }
  }

  Widget _topBar(BuildContext context) {
    final app = AppScope.of(context);
    final m = _msg;
    final a = widget.actions;
    final chat = a?.chat;
    final ready = m != null && !m.pending;
    String? who;
    String? when;
    if (m != null) {
      who = m.senderId == app.myId ? (app.me?.name ?? context.tr('you')) : (chat == null ? null : app.memberById(chat, m.senderId)?.name);
      final s = Strings(context.lang);
      final day = sameDay(m.createdAt, DateTime.now()) ? s.get('today') : chatListTime(m.createdAt, context.lang, s);
      when = s.get('day_at', {'d': day, 't': hhmm(m.createdAt, context.lang)});
    }
    final n = widget.items.length;
    final counter = context.tr('n_of_m', {'a': context.digits('${_i + 1}'), 'b': context.digits('$n')});
    const white = TextStyle(color: Colors.white);
    final mine = m != null && m.senderId == app.myId;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const BackButton(color: Colors.white),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  who ?? counter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: white.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
                if (when != null || n > 1)
                  Text(
                    [?when, if (who != null && n > 1) counter].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: white.copyWith(fontSize: 12.5, color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (ready && chat != null)
            IconButton(
              tooltip: context.tr('draw'),
              onPressed: _draw,
              icon: const Icon(Icons.brush_rounded, color: Colors.white),
            ),
          if (ready && a?.onAction != null)
            IconButton(
              tooltip: context.tr('forward'),
              onPressed: () => a!.onAction!(m, MsgAction.forward),
              icon: const Icon(Icons.shortcut_rounded, color: Colors.white),
            ),
          PopupMenuButton<_ViewerMenu>(
            tooltip: context.tr('more'),
            icon: const Icon(CupertinoIcons.ellipsis, color: Colors.white),
            onSelected: _menu,
            itemBuilder: (c) {
              PopupMenuItem<_ViewerMenu> item(_ViewerMenu v, IconData icon, String key, {Color? color}) => PopupMenuItem(
                value: v,
                child: Row(
                  children: [
                    Icon(icon, size: 21, color: color),
                    const SizedBox(width: 14),
                    Text(c.tr(key), style: TextStyle(color: color)),
                  ],
                ),
              );
              return [
                item(_ViewerMenu.gallery, Icons.download_rounded, 'save_gallery'),
                if (a?.onShowAll != null) item(_ViewerMenu.all, Icons.photo_library_rounded, 'show_all_media'),
                if (ready && a?.onShowInChat != null) item(_ViewerMenu.inChat, Icons.chat_rounded, 'show_in_chat'),
                if (ready && a?.onAction != null) item(_ViewerMenu.reply, Icons.reply_rounded, 'reply'),
                item(_ViewerMenu.share, Icons.share_rounded, 'share'),
                if (ready && mine && a?.onAction != null) item(_ViewerMenu.delete, Icons.delete_rounded, 'delete', color: Brand.pomegranate),
              ];
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)!.animation!;
    final pad = MediaQuery.paddingOf(context);
    final dragFade = (1 - _drag.abs() / 400).clamp(0.0, 1.0);
    final caption = _msg?.body.trim() ?? '';
    // Material gives the texts their style (no yellow debug underline)
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: route,
        builder: (context, _) {
          final t = Curves.easeOut.transform(route.value);
          final barsT = _bars ? t * dragFade : 0.0;
          return Stack(
            children: [
              // black backdrop
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: t * dragFade)),
              ),
              // photos
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _bars = !_bars),
                  onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
                  onVerticalDragEnd: _zoomed
                      ? null
                      : (d) {
                          if (_drag.abs() > 110 || (d.primaryVelocity ?? 0).abs() > 900) {
                            Navigator.of(context).pop();
                          } else {
                            setState(() => _drag = 0);
                          }
                        },
                  child: Transform.translate(
                    offset: Offset(0, _drag),
                    child: PageView.builder(
                      controller: _ctl,
                      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                      itemCount: widget.items.length,
                      onPageChanged: (i) => setState(() {
                        _i = i;
                        _zoom.value = Matrix4.identity();
                      }),
                      itemBuilder: (_, i) => InteractiveViewer(
                        transformationController: i == _i ? _zoom : null,
                        maxScale: 5,
                        panEnabled: _zoomed,
                        child: Center(
                          child: Hero(
                            tag: photoHeroTag(widget.items[i]),
                            child: AttachmentImage(path: widget.items[i].path, bytes: widget.items[i].bytes, fit: BoxFit.contain, full: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // top bar slides down from the edge
              Positioned(
                left: 0,
                right: 0,
                top: -80 * (1 - barsT),
                child: IgnorePointer(
                  ignoring: barsT < 0.5,
                  child: Opacity(
                    opacity: barsT,
                    child: Container(
                      padding: EdgeInsets.only(top: pad.top),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA000000), Color(0x00000000)]),
                      ),
                      child: _topBar(context),
                    ),
                  ),
                ),
              ),
              // bottom: caption and page dots
              if (widget.items.length > 1 || caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -80 * (1 - barsT),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: barsT,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 14 + pad.bottom),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)]),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (caption.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  caption,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                                ),
                              ),
                            if (widget.items.length > 1)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var k = 0; k < widget.items.length; k++)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: k == _i ? 18 : 7,
                                      height: 7,
                                      decoration: BoxDecoration(color: k == _i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(4)),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // short notice ("Saved to Gallery")
              Positioned(
                left: 0,
                right: 0,
                bottom: 90 + pad.bottom,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _note == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xE6303030), borderRadius: BorderRadius.circular(12)),
                        child: Text(_note ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Draw on a photo with a finger, then send the result (the brush in the viewer).
class PhotoDrawScreen extends StatefulWidget {
  const PhotoDrawScreen({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<PhotoDrawScreen> createState() => _PhotoDrawScreenState();
}

class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width;
  final List<Offset> points = [];
}

class _PhotoDrawScreenState extends State<PhotoDrawScreen> {
  static const _colors = [Colors.white, Colors.black, Color(0xFFE53935), Color(0xFFFFB300), Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFF8E24AA)];
  final _strokes = <_Stroke>[];
  final _boundary = GlobalKey();
  final _repaint = ValueNotifier<int>(0);
  Color _color = const Color(0xFFE53935);
  double _width = 6;
  ({int w, int h})? _size;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppController.imageSize(widget.bytes).then((s) {
      if (mounted) setState(() => _size = (w: math.max(1, s.w), h: math.max(1, s.h)));
    });
  }

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final ro = _boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || _size == null) return;
    setState(() => _busy = true);
    final ratio = (_size!.w / ro.size.width).clamp(1.0, 4.0);
    final img = await ro.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.of(context).pop(data?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: const CloseButton(),
        title: Text(context.tr('draw')),
        actions: [
          IconButton(
            tooltip: context.tr('undo'),
            onPressed: _strokes.isEmpty ? null : () => setState(() => _strokes.removeLast()),
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(tooltip: context.tr('send'), onPressed: _busy ? null : _done, icon: const Icon(CupertinoIcons.arrow_up)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: size == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: size.w / size.h,
                      child: RepaintBoundary(
                        key: _boundary,
                        child: GestureDetector(
                          onPanStart: (d) => setState(() => _strokes.add(_Stroke(_color, _width)..points.add(d.localPosition))),
                          onPanUpdate: (d) {
                            _strokes.last.points.add(d.localPosition);
                            _repaint.value++;
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(widget.bytes, fit: BoxFit.fill),
                              CustomPaint(painter: _StrokesPainter(_strokes, _repaint)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in _colors)
                        GestureDetector(
                          onTap: () => setState(() => _color = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: c == _color ? 32 : 26,
                            height: c == _color ? 32 : 26,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: c == _color ? 3 : 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Slider(value: _width, min: 2, max: 24, activeColor: _color, onChanged: (v) => setState(() => _width = v)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes, Listenable repaint) : super(repaint: repaint);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, p..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (final o in s.points.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}

/// Telegram-style album grid (2–10 photos).
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.message, this.width = 270, this.actions});
  final Message message;
  final double width;
  final ViewerActions? actions;

  @override
  Widget build(BuildContext context) {
    final items = message.albumItems;
    final local = message.localAlbum;
    final n = local?.length ?? items.length;
    final all = [
      for (var i = 0; i < n; i++) (path: i < items.length ? items[i]['path'] as String? : null, bytes: local != null && i < local.length ? local[i] : null),
    ];
    Widget tile(int i, double w, double h) => GestureDetector(
      onTap: () => GalleryViewer.open(context, all, i, messages: List.filled(n, message), actions: actions),
      child: SizedBox(
        width: w,
        height: h,
        child: Hero(
          tag: photoHeroTag(all[i]),
          child: AttachmentImage(path: all[i].path, bytes: all[i].bytes),
        ),
      ),
    );
    // Telegram-style mosaic: every photo keeps (close to) its own shape and
    // the group fills the bubble exactly, with thin gaps.
    final ratios = [
      for (var i = 0; i < n; i++)
        (() {
          final it = i < items.length ? items[i] : null;
          final w = (it?['w'] as num?)?.toDouble(), h = (it?['h'] as num?)?.toDouble();
          return w == null || h == null || w <= 0 || h <= 0 ? 1.0 : (w / h).clamp(0.5, 2.5);
        })(),
    ];
    final rects = albumLayout(ratios, width);
    final height = rects.fold<double>(0, (m, r) => math.max(m, r.bottom));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [for (var i = 0; i < n; i++) Positioned.fromRect(rect: rects[i], child: tile(i, rects[i].width, rects[i].height))],
            ),
          ),
          if (message.pending)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

/// Location message: a drawn map card with a pin; tap opens a map app.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, required this.lat, required this.lng});
  final double lat, lng;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final coords = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng'), mode: LaunchMode.externalApplication),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _MapPainter(dark: dark, seed: (lat * 1000 + lng * 1000).round()),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 22),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 44,
                        color: Brand.pomegranate,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                color: dark ? Colors.black26 : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.map_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(context.tr('location'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(coords, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

class _MapPainter extends CustomPainter {
  _MapPainter({required this.dark, required this.seed});
  final bool dark;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF22303D) : const Color(0xFFEAF0E6));
    final park = Paint()..color = dark ? const Color(0xFF253A2E) : const Color(0xFFCFE6C4);
    final water = Paint()..color = dark ? const Color(0xFF1D3550) : const Color(0xFFB9D7F2);
    canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), 38, park);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rnd.nextDouble() * size.width * 0.6, size.height * 0.65, 120, 60), const Radius.circular(30)),
      water,
    );
    final road = Paint()
      ..color = dark ? const Color(0xFF3A4A5A) : Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = dark ? const Color(0xFF2F3E4D) : const Color(0xFFFFFFFF)
      ..strokeWidth = 3;
    for (var i = 0; i < 6; i++) {
      final y = rnd.nextDouble() * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + rnd.nextDouble() * 40 - 20), i < 2 ? road : minor);
      final x = rnd.nextDouble() * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x + rnd.nextDouble() * 40 - 20, size.height), i < 2 ? road : minor);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) => o.dark != dark || o.seed != seed;
}

/// Shared contact card with "Message" / "Call" buttons.
class ContactCard extends StatelessWidget {
  const ContactCard({super.key, required this.meta, required this.onMessage});
  final Map<String, dynamic> meta;
  final void Function(String userId)? onMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (meta['name'] as String?) ?? '';
    final phone = meta['phone'] as String?;
    final email = meta['email'] as String?;
    final uid = meta['user_id'] as String?;
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Brand.avatarColor(uid ?? name),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    if (phone != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(phone, style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    if (email != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(email, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Row(
            children: [
              if (uid != null && onMessage != null)
                Expanded(
                  child: TextButton(onPressed: () => onMessage!(uid), child: Text(context.tr('message'))),
                ),
              if (phone != null)
                Expanded(
                  child: TextButton(onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')), child: Text(context.tr('call_number'))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where each photo of an album goes (Telegram's grouped-media idea): two
/// photos side by side or stacked, three as one big + two, and longer
/// albums as rows whose heights follow the photos' shapes, chosen so the
/// whole group is close to a pleasant height. [ratios] are width / height.
List<Rect> albumLayout(List<double> ratios, double width, {double gap = 2}) {
  final n = ratios.length;
  final maxH = width * 1.15;
  if (n == 0) return const [];
  if (n == 1) return [Rect.fromLTWH(0, 0, width, math.min(maxH, width / ratios[0]))];
  String kind(double r) => r > 1.2 ? 'w' : (r < 0.8 ? 'n' : 'q');
  final r0 = ratios[0];
  if (n == 2) {
    final r1 = ratios[1];
    // two wide photos: one above the other
    if (kind(r0) == 'w' && kind(r1) == 'w' && (r0 - r1).abs() < 0.3) {
      final h = math.min(width / math.max(r0, r1), (maxH - gap) / 2);
      return [Rect.fromLTWH(0, 0, width, h), Rect.fromLTWH(0, h + gap, width, h)];
    }
    // side by side, widths by shape, one height
    final w1 = math.max(0.35 * width, (width - gap) * (r1 / (r0 + r1)));
    final w0 = width - gap - w1;
    final h = math.min(maxH, math.min(w0 / r0, w1 / r1).clamp(width * 0.45, maxH));
    return [Rect.fromLTWH(0, 0, w0, h), Rect.fromLTWH(w0 + gap, 0, w1, h)];
  }
  if (n == 3 && kind(r0) == 'n') {
    // a tall first photo on the left, two stacked on the right
    final h = math.min(maxH, width * 0.95);
    final rightW = (width * 0.42).clamp(width * 0.3, width * 0.5);
    final leftW = width - gap - rightW;
    final top = (h - gap) * (ratios[2] / (ratios[1] + ratios[2]));
    return [Rect.fromLTWH(0, 0, leftW, h), Rect.fromLTWH(leftW + gap, 0, rightW, top), Rect.fromLTWH(leftW + gap, top + gap, rightW, h - gap - top)];
  }
  // rows: try every way to cut the photos into 1–4 rows of 1–4 photos
  // (first row may hold the one big photo) and keep the best-looking one
  List<Rect>? best;
  var bestScore = double.infinity;
  void tryRows(List<int> sizes) {
    final rects = <Rect>[];
    var y = 0.0, i = 0, score = 0.0;
    double? prevH;
    for (final k in sizes) {
      final rs = ratios.sublist(i, i + k);
      final sum = rs.fold<double>(0, (a, b) => a + b);
      final h = (width - gap * (k - 1)) / sum;
      // rows much taller or flatter than others look bad
      score += (h < width * 0.22 ? (width * 0.22 - h) * 3 : 0) + (h > maxH * 0.75 ? (h - maxH * 0.75) * 2 : 0);
      if (prevH != null) score += (h - prevH).abs() * 0.4; // rows of similar height
      prevH = h;
      var x = 0.0;
      for (var j = 0; j < k; j++) {
        final w = j == k - 1 ? width - x : h * rs[j];
        if (w < width * 0.24) score += (width * 0.24 - w) * 4; // no sliver photos
        rects.add(Rect.fromLTWH(x, y, w, h));
        x += w + gap;
      }
      y += h + gap;
      i += k;
    }
    final total = y - gap;
    score += (total - maxH).abs() + (sizes.first > sizes.last ? 15 : 0);
    if (score < bestScore) {
      bestScore = score;
      best = rects;
    }
  }

  void split(int left, List<int> acc) {
    if (left == 0) {
      tryRows(acc);
      return;
    }
    if (acc.length == math.max(4, (n + 3) ~/ 4)) return;
    for (var k = 1; k <= math.min(4, left); k++) {
      if (k == 1 && n > 3 && acc.isNotEmpty) continue; // a lone photo only on top
      split(left - k, [...acc, k]);
    }
  }

  split(n, []);
  return best!;
}
