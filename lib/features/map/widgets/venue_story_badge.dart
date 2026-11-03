import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../models/venue_story_activity.dart';

/// Paint-only toy emotions. Map pins share one active animation clock, keeping
/// camera, tiles, and widget layout out of every animation frame.
class VenueStoryBadge extends StatelessWidget {
  final VenueStoryLevel level;
  final Animation<double> phase;
  final double size;
  const VenueStoryBadge({
    super.key,
    required this.level,
    this.phase = const AlwaysStoppedAnimation(0),
    this.size = 36,
  });

  static Color color(VenueStoryLevel level) => switch (level) {
        VenueStoryLevel.sleeping => const Color(0xFFA99AE6),
        VenueStoryLevel.waking => const Color(0xFF69D9C1),
        VenueStoryLevel.lively => const Color(0xFFFFB45E),
        VenueStoryLevel.onFire => const Color(0xFFFF706C),
      };

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: _StoryEmotionPainter(level, phase),
          ),
        ),
      );
}

/// Sculpted silhouettes use a dark extrusion, spherical light, and small gloss
/// strokes. No images, blur, saveLayer, or per-character tickers are needed.
/// All transforms repeat seamlessly at phase 0/1 in the shared six-second loop.
class _StoryEmotionPainter extends CustomPainter {
  final VenueStoryLevel level;
  final Animation<double> phase;
  static const _ink = Color(0xFF2C204B);
  _StoryEmotionPainter(this.level, this.phase) : super(repaint: phase);

  Paint _solid(Color color) => Paint()..color = color;
  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _clay(Rect bounds, Color light, Color color, Color shade) => Paint()
    ..shader = RadialGradient(
      center: const Alignment(-.52, -.68),
      radius: 1.18,
      colors: [light, color, shade],
      stops: const [0, .48, 1],
    ).createShader(bounds);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final t = phase.value * math.pi * 2;
    final breathing = math.sin(t);
    final bounce = math.sin(t * 2);
    final warm =
        level == VenueStoryLevel.lively || level == VenueStoryLevel.onFire;
    final lift = warm ? 1.1 + bounce * 1.1 : .4 + breathing * .4;
    final color = VenueStoryBadge.color(level);

    // Stepped translucent ellipses form a soft grounding shadow without blur.
    for (var i = 3; i > 0; i--) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(24, 43),
          width: 19 + i * 2 - lift,
          height: 1.6 + i * .7,
        ),
        _solid(
            const Color(0xFF24133E).withValues(alpha: .035 + (3 - i) * .025)),
      );
    }
    canvas.save();
    canvas.translate(24, 29 - lift);
    canvas.rotate(level == VenueStoryLevel.sleeping
        ? .035 * breathing
        : level == VenueStoryLevel.onFire
            ? .055 * math.sin(t * 2)
            : .028 * math.sin(t * 2));
    if (level == VenueStoryLevel.sleeping) {
      canvas.scale(1 + breathing * .018, 1 - breathing * .016);
    }
    canvas.translate(-24, -29);
    if (level == VenueStoryLevel.onFire) {
      _flame(canvas, t);
    } else {
      _owl(canvas, t, color);
    }
    canvas.restore();

    if (level == VenueStoryLevel.sleeping) {
      for (var i = 0; i < 2; i++) {
        final p = (phase.value + i * .5) % 1;
        final opacity = math.pow(math.sin(math.pi * p), 2).toDouble();
        _sleepZ(
            canvas, Offset(35 + p * 4, 15 - p * 10), 3.1 + p * 1.2, opacity);
      }
    } else if (level == VenueStoryLevel.waking) {
      _sparkle(
          canvas,
          Offset(39, 10 + math.sin(t) * .7),
          2.5 + .45 * math.cos(t),
          const Color(0xFFD9FFF2),
          const Color(0xFF378C7A));
    } else if (level == VenueStoryLevel.lively) {
      _sparkle(canvas, Offset(7, 13 + math.sin(t * 2)), 2.2,
          const Color(0xFFFFF3B4), const Color(0xFFE59231));
      _sparkle(canvas, Offset(40, 8 - math.sin(t * 2)), 2.7,
          const Color(0xFFFFF3B4), const Color(0xFFE59231));
    } else {
      for (var i = 0; i < 3; i++) {
        final p = (phase.value * 2 + i / 3) % 1;
        final opacity = math.pow(math.sin(math.pi * p), 2).toDouble();
        final x = i == 1
            ? 39.0
            : i == 0
                ? 8.0
                : 33.0;
        final y = 22 - p * 16;
        canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: 2.1, height: 3.2 - p),
            _solid(const Color(0xFFFFBA6C).withValues(alpha: opacity)));
        canvas.drawCircle(Offset(x - .25, y - .45), .5,
            _solid(const Color(0xFFFFF2C5).withValues(alpha: opacity)));
      }
    }
    canvas.restore();
  }

  void _owl(Canvas canvas, double t, Color color) {
    final sleeping = level == VenueStoryLevel.sleeping;
    final lively = level == VenueStoryLevel.lively;
    final shade = sleeping
        ? const Color(0xFF6550A0)
        : lively
            ? const Color(0xFFB46C33)
            : const Color(0xFF2D8F84);
    final light = sleeping
        ? const Color(0xFFE0D5FF)
        : lively
            ? const Color(0xFFFFE7A8)
            : const Color(0xFFC1F8E7);
    final owl = Path()
      ..moveTo(10.5, 21)
      ..cubicTo(10, 17, 8, 10, 10.5, 10.5)
      ..quadraticBezierTo(15, 11, 19, 15)
      ..quadraticBezierTo(24, 13, 29, 15)
      ..quadraticBezierTo(34, 10.5, 37.5, 10.5)
      ..quadraticBezierTo(39, 11, 37.5, 21)
      ..cubicTo(44, 46, 4, 46, 10.5, 21)
      ..close();
    // The offset lower rim is visible around the cheeks and feet like a toy.
    canvas.save();
    canvas.translate(.5, 1.4);
    canvas.drawPath(owl, _solid(shade));
    canvas.drawPath(
        owl, _stroke(const Color(0xFF332346).withValues(alpha: .28), 1.4));
    canvas.restore();
    canvas.drawPath(
        owl, _clay(const Rect.fromLTWH(8, 10, 32, 31), light, color, shade));
    canvas.drawPath(owl, _stroke(light.withValues(alpha: .55), .65));

    // Ear inserts and the rounded wings keep the owl identity at map-pin size.
    for (final isLeft in [true, false]) {
      final ear = Path();
      if (isLeft) {
        ear
          ..moveTo(11.7, 13)
          ..lineTo(13, 20)
          ..lineTo(18, 17)
          ..close();
      } else {
        ear
          ..moveTo(36.2, 13)
          ..lineTo(35.2, 20)
          ..lineTo(30, 17)
          ..close();
      }
      canvas.drawPath(ear, _solid(shade.withValues(alpha: .55)));
      final wingX = isLeft ? 11.5 : 36.5;
      final flap = sleeping ? 0.0 : math.sin(t * 2) * (lively ? .3 : .18);
      canvas.save();
      canvas.translate(wingX, 29);
      canvas.rotate((isLeft ? -.24 : .24) + (isLeft ? flap : -flap));
      canvas.drawOval(const Rect.fromLTWH(-3, -5, 6, 13),
          _clay(const Rect.fromLTWH(-3, -5, 6, 13), light, color, shade));
      canvas.drawArc(const Rect.fromLTWH(-1.5, -4, 3, 9), -.9, 1.4, false,
          _stroke(light.withValues(alpha: .65), .75));
      canvas.restore();
    }
    // Twin face cushions cast a tiny rim shadow, then catch the top-left light.
    final face = Path()
      ..moveTo(24, 22)
      ..cubicTo(16, 11, 9, 22, 13, 31)
      ..quadraticBezierTo(18, 39, 24, 35)
      ..quadraticBezierTo(30, 39, 35, 31)
      ..cubicTo(39, 22, 32, 11, 24, 22)
      ..close();
    canvas.save();
    canvas.translate(.3, .9);
    canvas.drawPath(face, _solid(shade.withValues(alpha: .48)));
    canvas.restore();
    canvas.drawPath(
        face,
        _clay(const Rect.fromLTWH(12, 17, 24, 20), const Color(0xFFFFFCF4),
            light, Color.lerp(color, shade, .1)!));
    canvas.drawPath(face, _stroke(Colors.white.withValues(alpha: .42), .65));
    canvas.drawOval(const Rect.fromLTWH(18, 35, 12, 3.5),
        _solid(light.withValues(alpha: .2)));

    if (sleeping) {
      for (final x in [18.0, 30.0]) {
        final eyelid = Path()
          ..moveTo(x - 3, 25)
          ..quadraticBezierTo(x, 28.6, x + 3, 25);
        canvas.drawPath(eyelid, _stroke(shade.withValues(alpha: .25), 2.8));
        canvas.drawPath(eyelid, _stroke(_ink, 1.7));
      }
    } else if (lively) {
      for (final x in [18.0, 30.0]) {
        final smileEye = Path()
          ..moveTo(x - 2.5, 26.1)
          ..quadraticBezierTo(x, 22.1, x + 2.5, 26.1);
        canvas.drawPath(smileEye, _stroke(_ink, 1.8));
      }
    } else {
      final blink = _blink(t);
      _eye(canvas, const Offset(18.1, 25.5), blink, shade);
      _eye(canvas, const Offset(29.9, 25.5), blink, shade);
    }
    _cheeks(canvas, 14.4, 33.6, 29.1, lively ? .85 : .63);
    // A dimensional little beak, including a light edge and shaded underside.
    final beak = Path()
      ..moveTo(21.7, 28.1)
      ..quadraticBezierTo(24, 26.5, 26.3, 28.1)
      ..quadraticBezierTo(25.7, 30.3, 24, 31.1)
      ..quadraticBezierTo(22.3, 30.3, 21.7, 28.1)
      ..close();
    canvas.drawPath(
        beak,
        _clay(const Rect.fromLTWH(21.5, 27, 5, 4.5), const Color(0xFFFFEDAE),
            const Color(0xFFFFBD65), const Color(0xFFD38343)));
    canvas.drawLine(const Offset(22.8, 28), const Offset(24, 27.8),
        _stroke(const Color(0xFFFFF6C8), .8));
    if (lively) {
      final mouth = Path()
        ..moveTo(21.8, 32)
        ..quadraticBezierTo(24, 36.8, 26.2, 32)
        ..close();
      canvas.drawPath(mouth, _solid(_ink));
      canvas.drawOval(const Rect.fromLTWH(23, 33.5, 2.7, 1.2),
          _solid(const Color(0xFFF38C9C)));
    }
    // Small unblurred gloss strokes sell the rounded forehead and cheek edge.
    final gloss = Path()
      ..moveTo(14, 15.1)
      ..quadraticBezierTo(15, 15.3, 16.3, 16.4);
    canvas.drawPath(gloss, _stroke(Colors.white.withValues(alpha: .7), 1.4));
    canvas.drawArc(const Rect.fromLTWH(12, 27, 23, 12), .3, .65, false,
        _stroke(light.withValues(alpha: .45), 1));
  }

  // A smooth, narrow eyelid closure once per loop, including matching endpoints.
  double _blink(double t) {
    final closing = math.pow((1 + math.cos(t - math.pi)) / 2, 24).toDouble();
    return 1 - closing * .94;
  }

  void _eye(Canvas canvas, Offset center, double openness, Color shade) {
    final eye =
        Rect.fromCenter(center: center, width: 6.1, height: 8.2 * openness);
    canvas.drawOval(
        eye.shift(const Offset(.2, .5)), _solid(shade.withValues(alpha: .24)));
    canvas.drawOval(
        eye,
        _clay(eye, const Color(0xFF64527C), const Color(0xFF302344),
            const Color(0xFF170F2B)));
    if (openness > .4) {
      canvas.drawOval(
          Rect.fromCenter(
              center: center + Offset(-.85, -1.5 * openness),
              width: 1.8,
              height: 2.2 * openness),
          _solid(const Color(0xFFFFFBFF)));
      canvas.drawCircle(center + Offset(1, 1.6 * openness), .55 * openness,
          _solid(const Color(0xFFB6D9EE)));
    }
  }

  void _cheeks(
      Canvas canvas, double left, double right, double y, double alpha) {
    for (final x in [left, right]) {
      final cheek =
          Rect.fromCenter(center: Offset(x, y), width: 4.4, height: 2.5);
      canvas.drawOval(
          cheek,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFF68FAE).withValues(alpha: alpha),
                const Color(0xFFF68FAE).withValues(alpha: .08)
              ],
            ).createShader(cheek));
    }
  }

  void _flame(Canvas canvas, double t) {
    final sway = math.sin(t * 2) * 1.4;
    final flame = Path()
      ..moveTo(25 + sway, 5.1)
      ..cubicTo(24 + sway, 13, 37, 17, 38.2, 27)
      ..cubicTo(40.5, 45, 8, 46, 9.2, 28.7)
      ..quadraticBezierTo(9.4, 22.5, 14.1, 17)
      ..quadraticBezierTo(13.5, 24.6, 18.5, 24.4)
      ..cubicTo(17.9, 17.5, 20, 10, 25 + sway, 5.1)
      ..close();
    canvas.save();
    canvas.translate(.6, 1.2);
    canvas.drawPath(flame, _solid(const Color(0xFFA83B53)));
    canvas.drawPath(
        flame, _stroke(const Color(0xFF572449).withValues(alpha: .38), 1.3));
    canvas.restore();
    canvas.drawPath(
        flame,
        _clay(const Rect.fromLTWH(9, 5, 30, 36), const Color(0xFFFFD991),
            const Color(0xFFFF9169), const Color(0xFFE64D65)));
    canvas.drawPath(
        flame, _stroke(const Color(0xFFFFD8AB).withValues(alpha: .65), .7));
    final core = Path()
      ..moveTo(24, 22)
      ..cubicTo(28, 26, 34, 28, 33.7, 33)
      ..cubicTo(32.5, 41, 15, 41, 14.3, 33)
      ..quadraticBezierTo(14, 30, 18, 26.7)
      ..quadraticBezierTo(20, 29.9, 21.5, 28)
      ..quadraticBezierTo(22, 24.5, 24, 22)
      ..close();
    canvas.drawPath(
        core,
        _clay(const Rect.fromLTWH(14, 22, 20, 18), const Color(0xFFFFF4D2),
            const Color(0xFFFFDC91), const Color(0xFFFFAB70)));
    final blink = _blink(t);
    _eye(canvas, const Offset(18.1, 29), blink, const Color(0xFFBF7151));
    _eye(canvas, const Offset(29.9, 29), blink, const Color(0xFFBF7151));
    _cheeks(canvas, 13.9, 34, 33, .8);
    final smile = Path()
      ..moveTo(21.8, 33.3)
      ..quadraticBezierTo(24, 37.5, 26.2, 33.3);
    canvas.drawPath(smile, _stroke(_ink, 1.6));
    final gloss = Path()
      ..moveTo(23, 13)
      ..quadraticBezierTo(21.8, 16.5, 23.1, 19);
    canvas.drawPath(
        gloss, _stroke(const Color(0xFFFFF1D4).withValues(alpha: .87), 1.8));
    final rim = Path()
      ..moveTo(34.5, 32)
      ..quadraticBezierTo(34.9, 36, 31, 37.5);
    canvas.drawPath(
        rim, _stroke(const Color(0xFFFFE4B8).withValues(alpha: .7), 1));
  }

  void _sleepZ(Canvas canvas, Offset at, double size, double opacity) {
    if (opacity < .01) return;
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx + size, at.dy)
      ..lineTo(at.dx, at.dy + size)
      ..lineTo(at.dx + size, at.dy + size);
    canvas.save();
    canvas.translate(.5, .7);
    canvas.drawPath(
        path, _stroke(const Color(0xFF66529B).withValues(alpha: opacity), 1.9));
    canvas.restore();
    canvas.drawPath(
        path, _stroke(const Color(0xFFEAE1FF).withValues(alpha: opacity), 1.2));
  }

  void _sparkle(
      Canvas canvas, Offset at, double radius, Color light, Color shade) {
    final star = Path()
      ..moveTo(at.dx, at.dy - radius)
      ..quadraticBezierTo(at.dx + .5, at.dy - .5, at.dx + radius, at.dy)
      ..quadraticBezierTo(at.dx + .5, at.dy + .5, at.dx, at.dy + radius)
      ..quadraticBezierTo(at.dx - .5, at.dy + .5, at.dx - radius, at.dy)
      ..quadraticBezierTo(at.dx - .5, at.dy - .5, at.dx, at.dy - radius)
      ..close();
    canvas.drawPath(star.shift(const Offset(.4, .7)), _solid(shade));
    canvas.drawPath(
        star,
        _clay(Rect.fromCircle(center: at, radius: radius), Colors.white, light,
            shade));
  }

  @override
  bool shouldRepaint(_StoryEmotionPainter old) =>
      old.level != level || old.phase != phase;
}

class VenueStoryLegend extends StatefulWidget {
  const VenueStoryLegend({super.key});
  @override
  State<VenueStoryLegend> createState() => _VenueStoryLegendState();
}

class _VenueStoryLegendState extends State<VenueStoryLegend>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _phase =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _dependenciesReady = false;
  bool _motionAllowed = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _motionAllowed = !AppMotion.reduced(context) && TickerMode.of(context);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (_dependenciesReady && _motionAllowed && _foreground) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
      _phase.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Өнөөдрийн story хэмнэл',
                    style:
                        TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: 'Хаах',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Энэ газрыг тэмдэглэсэн, танд харагдах идэвхтэй story-ийн тоо. '
              'Өнөөдрийг Улаанбаатарын цагаар тоолно.',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 20),
          for (final level in VenueStoryLevel.values)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: VenueStoryBadge.color(level).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: VenueStoryBadge.color(level)
                              .withValues(alpha: .24))),
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        VenueStoryBadge(level: level, phase: _phase, size: 48),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(level.label,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('${level.rangeLabel} story'),
                            ])),
                      ])),
                )),
          const SizedBox(height: 4),
          const Text(
              'Story-ийн идэвх нь газрын бодит хүнтэй эсэх, ажиллаж байгаа эсэхийг батлахгүй.',
              style: TextStyle(fontSize: 12, height: 1.5)),
        ]),
      );
}
