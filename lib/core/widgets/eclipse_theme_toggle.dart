import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Харанхуй / гэрэл горимын "нар хиртэлт" toggle.
///
/// Гэрэл горим (isDark=false): хар хоолой дотор зүүн талд цагаан "нар".
/// Шилжилт: бөмбөг баруун тийш гулсахдаа хэвтээ сунаж (squash), цагаан →
/// саарал → хар болж хиртэнэ; зүүн талаас оч цацарна.
/// Харанхуй горим (isDark=true): баруун талд хар "сар" неон титэмтэй,
/// хоолой нь 5 өнгөний үе дамжин урсах плазмаар дүүрнэ (ногоон-шар →
/// ягаан → нил-улаан → алтан → цахилгаан цэнхэр + цагираг долгион).
///
/// `onChanged` дуудагдмагц toggle өөрөө шууд хөдөлж эхэлнэ (optimistic);
/// эцэг widget `isDark`-ийг шинэчилснээр төлөв бататгагдана.
class EclipseThemeToggle extends StatefulWidget {
  final bool isDark;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  const EclipseThemeToggle({
    super.key,
    required this.isDark,
    this.onChanged,
    this.width = 60,
    this.height = 30,
  });

  @override
  State<EclipseThemeToggle> createState() => _EclipseThemeToggleState();
}

class _EclipseThemeToggleState extends State<EclipseThemeToggle>
    with TickerProviderStateMixin {
  // 0 = нар (гэрэл) … 1 = хиртэлт (харанхуй). Шугаман — муруйг painter хэрэглэнэ.
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: widget.isDark ? 1 : 0,
  )..addStatusListener((_) => _syncFlow());

  // Плазмын палитрын эргэлт — 5 үе × 1.5с (видеотой ижил хэмнэл)
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7500),
  );

  late bool _target = widget.isDark;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncFlow();
  }

  @override
  void didUpdateWidget(EclipseThemeToggle old) {
    super.didUpdateWidget(old);
    if (widget.isDark != _target) _animateTo(widget.isDark);
  }

  void _animateTo(bool dark) {
    _target = dark;
    if (_reduceMotion) {
      _t.value = dark ? 1 : 0;
    } else {
      // Харанхуй руу орохдоо палитрыг эхнээс нь (ногоон-шар) эхлүүлнэ
      if (dark && _t.value < 0.05) _flow.value = 0;
      _t.animateTo(dark ? 1 : 0);
    }
    _syncFlow();
  }

  // Плазм зөвхөн харанхуй төлөвт эсвэл шилжилтийн үед урсана.
  void _syncFlow() {
    if (!mounted) return;
    final run = !_reduceMotion && (_target || _t.value > 0);
    if (run && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!run && _flow.isAnimating) {
      _flow.stop();
    }
  }

  void _tap() {
    final cb = widget.onChanged;
    if (cb == null) return;
    HapticFeedback.lightImpact();
    final next = !_target;
    _animateTo(next);
    cb(next);
  }

  @override
  void dispose() {
    _t.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return Semantics(
      button: true,
      toggled: _target,
      label: 'Харанхуй горим',
      child: Tooltip(
        message: _target ? 'Гэрэл горим руу шилжих' : 'Харанхуй горим руу шилжих',
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _tap : null,
            // Хүрэх талбай хамгийн багадаа 44×44
            child: SizedBox(
              width: math.max(widget.width, 44),
              height: math.max(widget.height, 44),
              child: Center(
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(widget.width, widget.height),
                    painter: EclipseTogglePainter(t: _t, flow: _flow),
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

/// Тодорхой нэг агшны зураг — тест/баримтжуулалтад (анимацгүй).
class EclipseToggleFrame extends StatelessWidget {
  final double t;
  final double flow;
  final double width;
  final double height;

  const EclipseToggleFrame({
    super.key,
    required this.t,
    this.flow = 0,
    this.width = 60,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: EclipseTogglePainter(
          t: AlwaysStoppedAnimation(t),
          flow: AlwaysStoppedAnimation(flow),
        ),
      );
}

// ─────────────────────────────── Palette ───────────────────────────────

class _Pal {
  final Color a, b, c; // плазмын гурван өнгө (зүүнээс баруун)
  final Color rim; // сарны титэм
  final Color halo; // гадна гэрэлтэлт
  final double ripple; // сарны эргэн тойрны цагираг долгионы хүч (0..1)
  const _Pal(this.a, this.b, this.c, this.rim, this.halo, this.ripple);

  static _Pal lerp(_Pal x, _Pal y, double k) => _Pal(
        Color.lerp(x.a, y.a, k)!,
        Color.lerp(x.b, y.b, k)!,
        Color.lerp(x.c, y.c, k)!,
        Color.lerp(x.rim, y.rim, k)!,
        Color.lerp(x.halo, y.halo, k)!,
        lerpDouble(x.ripple, y.ripple, k)!,
      );
}

// Лавлагаа видеоны 5 үе
const _pals = <_Pal>[
  // 1. Ногоон → шар, шар титэм
  _Pal(Color(0xFF1FFF5A), Color(0xFFC6FF1A), Color(0xFFFFE21A),
      Color(0xFFFFE21A), Color(0xFFB8FF2E), 0.0),
  // 2. Час улаан / ягаан
  _Pal(Color(0xFF6A0DAD), Color(0xFFFF1E56), Color(0xFFFF2D8E),
      Color(0xFFFF2D6E), Color(0xFFFF2D8E), 0.15),
  // 3. Хөх нил → улаан
  _Pal(Color(0xFF2B1B7A), Color(0xFF7C3AED), Color(0xFFFF3355),
      Color(0xFFFF3355), Color(0xFFC026D3), 0.25),
  // 4. Алтан шингэн, нил ирмэг
  _Pal(Color(0xFFB04BFF), Color(0xFFFFD60A), Color(0xFFFF8A00),
      Color(0xFFFF3B30), Color(0xFFFFB020), 0.1),
  // 5. Цахилгаан цэнхэр → ягаан, цагираг долгион
  _Pal(Color(0xFF1E6BFF), Color(0xFF22E7FF), Color(0xFFFF2BD6),
      Color(0xFFFF9F1C), Color(0xFF3D5AFE), 1.0),
];

double _interval(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

double _smooth(double x) => x * x * (3 - 2 * x);

_Pal _paletteAt(double flow) {
  final x = (flow % 1.0) * _pals.length;
  final i = x.floor();
  final f = x - i;
  // Үе бүрийн 55%-д тогтож, үлдсэнд нь дараагийн рүү зөөлөн шилжинэ
  final k = _smooth(((f - 0.55) / 0.45).clamp(0.0, 1.0));
  return _Pal.lerp(_pals[i % _pals.length], _pals[(i + 1) % _pals.length], k);
}

Color _lerp3(Color a, Color b, Color c, double t) =>
    t < 0.5 ? Color.lerp(a, b, t * 2)! : Color.lerp(b, c, (t - 0.5) * 2)!;

// Очны тогтмол үр (өнцөг°, хурд, хэмжээ) — зүүн тийш цацарна
const _sparks = <(double, double, double)>[
  (150, 1.00, 0.9), (168, 0.70, 0.6), (182, 1.15, 0.8), (196, 0.85, 0.7),
  (210, 1.05, 0.9), (224, 0.65, 0.6), (238, 0.95, 0.7), (132, 0.80, 0.6),
  (118, 0.60, 0.5), (252, 0.70, 0.5), (174, 1.35, 0.5), (204, 1.30, 0.6),
  (160, 0.45, 0.8), (230, 0.40, 0.7),
];

// ─────────────────────────────── Painter ───────────────────────────────

class EclipseTogglePainter extends CustomPainter {
  final Animation<double> t;
  final Animation<double> flow;

  EclipseTogglePainter({required this.t, required this.flow})
      : super(repaint: Listenable.merge([t, flow]));

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final u = h / 30.0; // масштабын нэгж — жижиг/том хэмжээнд ижил харагдана
    final tv = t.value;
    final fv = flow.value;

    final track = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(h / 2));
    final pad = h * 0.09;
    final r = h / 2 - pad;
    final cy = h / 2;

    final pos = Curves.easeInOutCubic.transform(tv);
    final cx = lerpDouble(pad + r, w - pad - r, pos)!;
    final bump = math.sin(math.pi * tv); // шилжилтийн дунд оргилно
    final e = Curves.easeOut.transform(_interval(tv, 0.45, 1.0)); // плазм/титэм
    final pal = _paletteAt(fv);
    final phase = fv * math.pi * 2 * _pals.length; // үе бүрт нэг бүтэн долгион

    // ── 1. Гадна гэрэлтэлт (трекийн ард) ──
    if (e > 0.01) {
      canvas.drawRRect(
        track.inflate(1.5 * u),
        Paint()
          ..color = pal.halo.withValues(alpha: 0.5 * e)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * u),
      );
    }

    // ── 2. Трекийн суурь ──
    canvas.drawRRect(track, Paint()..color = const Color(0xFF101014));

    // ── 3. Плазм (трек дотор хавчина) ──
    canvas.save();
    canvas.clipRRect(track);

    // Шилжилтийн үед баруунаас нэвчих ягаан туяа
    if (bump > 0.01) {
      canvas.drawCircle(
        Offset(w - r * 0.8, cy),
        h * 0.85,
        Paint()
          ..color = const Color(0xFFFF1E8A)
              .withValues(alpha: 0.9 * bump * (1 - 0.6 * e))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * u),
      );
    }

    if (e > 0.01) {
      // Суурь градиент — зогсоолууд нь аажуухан хөвнө
      final shift = math.sin(phase * 0.5) * 0.08;
      canvas.drawRRect(
        track,
        Paint()
          ..shader = LinearGradient(
            colors: [
              pal.a.withValues(alpha: e),
              pal.b.withValues(alpha: e),
              pal.c.withValues(alpha: e),
            ],
            stops: [0.0, (0.42 + shift).clamp(0.2, 0.75), 0.95],
          ).createShader(Offset.zero & size),
      );

      // Шингэн долгионт зурвасууд
      for (var i = 0; i < 3; i++) {
        final baseX = w * (0.14 + i * 0.19) +
            math.sin(phase * (0.35 + i * 0.18) + i * 1.7) * w * 0.07;
        final path = Path();
        for (var k = 0; k <= 14; k++) {
          final yy = h * k / 14;
          final xx = baseX +
              math.sin(yy / h * math.pi * 2.4 + phase * 0.8 + i * 2.1) * 2.4 * u;
          k == 0 ? path.moveTo(xx, yy) : path.lineTo(xx, yy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (5.0 - i * 1.2) * u
            ..color = (i.isEven ? pal.b : pal.c).withValues(alpha: 0.7 * e)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.2 * u),
        );
        // Хурц гэрэлт судал
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9 * u
            ..color = Color.lerp(pal.b, Colors.white, 0.45)!
                .withValues(alpha: 0.55 * e * (i == 1 ? 1 : 0.5))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 * u),
        );
      }

      // Сарны эргэн тойрны цагираг долгион (5-р үед хамгийн тод)
      final ripple = (0.2 + 0.8 * pal.ripple) * e;
      if (ripple > 0.02) {
        final grow = (fv * _pals.length) % 1.0;
        for (var k = 0; k < 3; k++) {
          final rr = r * (1.22 + k * 0.3 + grow * 0.22);
          canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: rr),
            math.pi * 0.6,
            math.pi * 0.8,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.1 * u
              ..color = Color.lerp(pal.c, Colors.white, 0.25)!
                  .withValues(alpha: ripple * (1 - k * 0.28) * (1 - grow * 0.5))
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.6 * u),
          );
        }
      }
    }
    canvas.restore();

    // ── 4. Трекийн хүрээ ──
    canvas.drawRRect(
      track.deflate(0.6 * u),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * u
        ..color = const Color(0xFF8E8E94).withValues(alpha: 0.85 - 0.25 * e),
    );

    // ── 5. Оч + зүүн ирмэгийн алтан нум (зөвхөн шилжих үед) ──
    if (bump > 0.02) {
      final ox = pad + r * 0.35, oy = cy;
      final spark = Paint()
        ..color = const Color(0xFFFFE7A8).withValues(alpha: 0.9 * bump * (1 - e))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.35 * u);
      for (final s in _sparks) {
        final a = s.$1 * math.pi / 180;
        final d = s.$2 * u * (3 + 15 * tv);
        canvas.drawCircle(
            Offset(ox + math.cos(a) * d, oy + math.sin(a) * d), s.$3 * u, spark);
      }
      canvas.drawArc(
        Rect.fromCircle(center: Offset(pad + r, cy), radius: r * 1.18),
        math.pi * 0.72,
        math.pi * 0.56,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 * u
          ..color = const Color(0xFFFFC53D).withValues(alpha: 0.75 * bump)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 * u),
      );
    }

    // ── 6. Бөмбөг — squash & stretch ──
    final sx = 1 + 0.10 * bump, sy = 1 - 0.05 * bump;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(sx, sy);
    final knob = Rect.fromCircle(center: Offset.zero, radius: r);

    // Нарны зөөлөн гэрэлтэлт
    final sun = 1 - _interval(tv, 0.15, 0.8);
    if (sun > 0.01) {
      canvas.drawCircle(
        Offset.zero,
        r * 1.04,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.32 * sun)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * u),
      );
    }

    // Титмийн гэрэлтэлт (биеийн ард — гадна тал нь л харагдана)
    if (e > 0.01) {
      canvas.drawCircle(
        Offset.zero,
        r * 1.02,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.42
          ..color = pal.rim.withValues(alpha: 0.8 * e)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.2 * u),
      );
    }

    // Бөмбөгний бие: цагаан нар → саарал → радиаль сүүдэртэй хар сар
    final ct = Curves.easeInOut.transform(_interval(tv, 0.2, 0.9));
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 1.05,
          colors: [
            _lerp3(const Color(0xFFFFFFFF), const Color(0xFFA2A2A6),
                const Color(0xFF2C2C33), ct),
            _lerp3(const Color(0xFFF1F1F3), const Color(0xFF8E8E92),
                const Color(0xFF16161B), ct),
            _lerp3(const Color(0xFFD4D4D9), const Color(0xFF78787C),
                const Color(0xFF08080B), ct),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(knob),
    );

    // Хурц титэм — өнгө нь сарыг тойрон эргэнэ
    if (e > 0.01) {
      canvas.drawCircle(
        Offset.zero,
        r - 0.2 * u,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.1 * u, r * 0.1)
          ..shader = SweepGradient(
            colors: [
              pal.rim.withValues(alpha: e),
              pal.c.withValues(alpha: e),
              Color.lerp(pal.rim, Colors.white, 0.45)!.withValues(alpha: e),
              pal.rim.withValues(alpha: e),
            ],
            stops: const [0.0, 0.4, 0.7, 1.0],
            transform: GradientRotation(phase * 0.25),
          ).createShader(knob),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EclipseTogglePainter old) =>
      old.t != t || old.flow != flow;
}
