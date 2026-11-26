import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../services/calls.dart';
import '../widgets/avatar.dart';

/// Makes the call controller reachable from any widget.
class CallScope extends InheritedNotifier<CallController> {
  const CallScope({super.key, required CallController controller, required super.child}) : super(notifier: controller);

  static CallController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CallScope>()!.notifier!;
  static CallController read(BuildContext context) => (context.getElementForInheritedWidgetOfExactType<CallScope>()!.widget as CallScope).notifier!;
}

/// Full-screen call UI shown above everything while a call is in progress.
class CallOverlay extends StatefulWidget {
  const CallOverlay({super.key});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _status(BuildContext context, CallController c) {
    switch (c.phase) {
      case CallPhase.outgoing:
        return context.tr('calling');
      case CallPhase.incoming:
        return context.tr(c.video ? 'incoming_video' : 'incoming_voice');
      case CallPhase.connecting:
        return context.tr('connecting_call');
      case CallPhase.active:
        final d = DateTime.now().difference(c.startedAt ?? DateTime.now());
        final mm = d.inMinutes.toString().padLeft(2, '0');
        final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
        return context.digits('$mm:$ss');
      case CallPhase.ended:
        return context.tr(switch (c.endReason) {
          'declined' => 'call_declined',
          'missed' => 'call_missed',
          'failed' => 'call_failed',
          _ => 'call_ended',
        });
      case CallPhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CallScope.of(context);
    if (c.phase == CallPhase.ended) {
      Future.delayed(const Duration(seconds: 2), c.reset);
    }
    final showVideo = c.video && (c.phase == CallPhase.active || c.phase == CallPhase.connecting);
    final name = c.peer?.name ?? '';

    return Material(
      color: Brand.lapisDeep,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            RTCVideoView(c.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Brand.lapisBright, Brand.lapis, Brand.lapisDeep]),
              ),
            ),
          if (c.video && c.phase != CallPhase.incoming && c.phase != CallPhase.ended && !c.cameraOff)
            PositionedDirectional(
              top: 48,
              end: 16,
              width: 110,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: RTCVideoView(c.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 60),
                if (!showVideo) ...[
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 6),
                    ),
                    child: Avatar(seed: c.peer?.id ?? '', label: name, imageUrl: c.peer?.avatarUrl, size: 120),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(_status(context, c), style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 16)),
                const Spacer(),
                Padding(padding: const EdgeInsets.only(bottom: 36), child: _controls(context, c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, CallController c) {
    if (c.phase == CallPhase.ended) return const SizedBox(height: 72);
    if (c.phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(icon: Icons.call_end_rounded, color: Brand.pomegranate, label: context.tr('decline'), onTap: c.decline),
          _RoundButton(
            icon: c.video ? CupertinoIcons.video_camera_solid : CupertinoIcons.phone_fill,
            color: const Color(0xFF1E8C6E),
            label: context.tr('accept'),
            onTap: c.accept,
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: c.muted ? Icons.mic_off_rounded : CupertinoIcons.mic_fill,
          color: c.muted ? Colors.white : Colors.white24,
          iconColor: c.muted ? Brand.lapisDeep : Colors.white,
          label: context.tr('mute'),
          onTap: c.toggleMute,
        ),
        if (c.video)
          _RoundButton(
            icon: c.cameraOff ? Icons.videocam_off_rounded : CupertinoIcons.video_camera_solid,
            color: c.cameraOff ? Colors.white : Colors.white24,
            iconColor: c.cameraOff ? Brand.lapisDeep : Colors.white,
            label: context.tr('camera'),
            onTap: c.toggleCamera,
          ),
        if (c.video) _RoundButton(icon: Icons.cameraswitch_rounded, color: Colors.white24, label: context.tr('flip'), onTap: c.switchCamera),
        _RoundButton(icon: Icons.call_end_rounded, color: Brand.pomegranate, label: context.tr('end_call'), onTap: () => c.hangUp()),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, required this.label, required this.onTap, this.iconColor = Colors.white});
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 66, height: 66, child: Icon(icon, color: iconColor, size: 30)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    ),
  );
}
