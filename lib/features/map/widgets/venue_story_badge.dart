import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../models/venue_story_activity.dart';

/// Paint-only emotion. Map pins share a single bounded animation clock so
/// camera/tiles and widget layout never rebuild on each animation frame.
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

class _StoryEmotionPainter extends CustomPainter {
  final VenueStoryLevel level;
  final Animation<double> phase;
  _StoryEmotionPainter(this.level, this.phase) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final wave = math.sin(phase.value * math.pi * 4);
    final warm =
        level == VenueStoryLevel.lively || level == VenueStoryLevel.onFire;
    final color = VenueStoryBadge.color(level);
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, .38)!,
          color,
          Color.lerp(color, const Color(0xFF462276), .25)!
        ],
      ).createShader(const Rect.fromLTWH(7, 7, 34, 35));
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(24, 43), width: 24 + wave, height: 3),
        Paint()..color = color.withValues(alpha: .16));
    canvas.translate(0, -wave * (warm ? 1.8 : 1.1));
    if (warm) {
      final flame = Path()
        ..moveTo(24, 3)
        ..cubicTo(28 + wave, 12, 39, 13, 39, 27)
        ..cubicTo(40, 45, 8, 45, 9, 28)
        ..cubicTo(9, 22, 13, 15, 15, 12)
        ..quadraticBezierTo(16, 21, 20, 21)
        ..quadraticBezierTo(19 - wave, 10, 24, 3)
        ..close();
      canvas.drawPath(
          flame,
          Paint()
            ..color = const Color(0xFF1D1732).withValues(alpha: .22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      canvas.drawPath(flame, body);
      canvas.drawOval(const Rect.fromLTWH(14, 20, 20, 18),
          Paint()..color = const Color(0xFFFFE4A3).withValues(alpha: .6));
      if (level == VenueStoryLevel.onFire) {
        for (var i = 0; i < 3; i++) {
          final p = (phase.value * 2 + i / 3) % 1;
          canvas.drawCircle(Offset(8 + i * 16, 19 - p * 13), 1.3 * (1 - p),
              Paint()..color = color.withValues(alpha: 1 - p));
        }
      }
    } else {
      final owl = Path()
        ..moveTo(10, 20)
        ..quadraticBezierTo(6, 7, 12, 10)
        ..lineTo(19, 15)
        ..quadraticBezierTo(24, 12, 29, 15)
        ..lineTo(37, 10)
        ..quadraticBezierTo(41, 9, 38, 23)
        ..cubicTo(44, 47, 4, 47, 10, 20)
        ..close();
      canvas.drawPath(
          owl,
          Paint()
            ..color = const Color(0xFF1D1732).withValues(alpha: .22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
      canvas.drawPath(owl, body);
      canvas.drawOval(const Rect.fromLTWH(12, 18, 24, 18),
          Paint()..color = Colors.white.withValues(alpha: .35));
    }
    final ink = Paint()
      ..color = const Color(0xFF30234A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    if (level == VenueStoryLevel.sleeping) {
      for (final x in [18.0, 30.0]) {
        canvas.drawArc(
            Rect.fromCenter(center: Offset(x, 25), width: 6, height: 5),
            .15,
            math.pi - .3,
            false,
            ink);
      }
      _sleepZ(canvas, Offset(35 + wave, 8 - wave), 6, color);
      _sleepZ(canvas, Offset(39 + wave, 0 - wave), 8, color);
    } else {
      final blink = phase.value > .44 && phase.value < .47;
      for (final x in [18.0, 30.0]) {
        if (blink) {
          canvas.drawLine(Offset(x - 2, 26), Offset(x + 2, 26), ink);
        } else {
          canvas.drawOval(
              Rect.fromCenter(center: Offset(x, 26), width: 3.5, height: 5),
              Paint()..color = const Color(0xFF30234A));
          canvas.drawCircle(
              Offset(x + .4, 25), .7, Paint()..color = Colors.white);
        }
      }
      canvas.drawArc(
          const Rect.fromLTWH(21, 27, 6, 7), .1, math.pi - .2, false, ink);
      if (level == VenueStoryLevel.waking) {
        final sparkle = Paint()
          ..color = const Color(0xFFE4FFF2)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(38, 4 - wave), Offset(38, 12 - wave), sparkle);
        canvas.drawLine(Offset(34, 8 - wave), Offset(42, 8 - wave), sparkle);
      }
    }
    canvas.drawCircle(const Offset(13.5, 30), 2.2,
        Paint()..color = const Color(0xFFF5A0B7).withValues(alpha: .62));
    canvas.drawCircle(const Offset(34.5, 30), 2.2,
        Paint()..color = const Color(0xFFF5A0B7).withValues(alpha: .62));
    canvas.restore();
  }

  void _sleepZ(Canvas canvas, Offset at, double size, Color color) {
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx + size, at.dy)
      ..lineTo(at.dx, at.dy + size)
      ..lineTo(at.dx + size, at.dy + size);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
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
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800));
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) || !TickerMode.of(context)) {
      _phase.stop();
      _phase.value = 0;
    } else if (!_started) {
      _started = true;
      _phase.forward();
    }
  }

  @override
  void dispose() {
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
