import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../core/services/supabase_service.dart';

/// Bottom nav shell — center-FAB template (Instagram/TikTok маягийн док)
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    // Online статус — минут тутам last_seen_at шинэчилнэ (heartbeat)
    _beat();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) => _beat());
  }

  Future<void> _beat() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      await SupabaseService.client.from('profiles')
          .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', me);
    } catch (_) {}
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBody: true, // floating bar контентын дээгүүр хөвнө
      body: widget.child,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  // ── Center-FAB dock хэмжээс ──
  // _dockMargin + _dockHeight + _fabLift = AppSpacing.dockClearance (92).
  // Дэлгэцүүд ёроолын нөөц зайг мөн AppSpacing.dockClearance-аас авдаг тул
  // энд ганц эх сурвалж (токен) л шийднэ.
  static const double _dockHeight = 62; // glass бар өндөр
  static const double _fabSize = 54;    // төв CREATE FAB
  static const double _fabLift = 16;    // FAB док дээгүүр цухуйх хэмжээ
  // Доод ирмэгээс хөвөх зай — токеноос ухаж авна (92 - 62 - 16 = 14)
  static const double _dockMargin =
      AppSpacing.dockClearance - _dockHeight - _fabLift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Доод ирмэгээс хөвүүлж, хажуу талаас 20 зай (дэлгэцийн padding-тай ижил)
      padding: EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, _dockMargin + bottomInset),
      child: SizedBox(
        // FAB дээш цухуйдаг тул Stack-д нэмэлт өндөр өгнө
        height: _dockHeight + _fabLift,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Хөвөгч glass док — 2 tab | FAB суудал | 2 tab ──
            Positioned(
              left: 0, right: 0, bottom: 0,
              // Сүүдэр ClipRRect-ийн ГАДНА — үгүй бол хайчлагдаж алга болно
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  boxShadow: AppColors.shadowDock,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(31),
                  // ⚠️ Web perf: цор ганц blur давхарга — өөр хаана ч blur хэрэглэхгүй
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: _dockHeight,
                      decoration: BoxDecoration(
                        // Glass spec: bgElevated @~0.72 — токеноос авна
                        color: AppColors.bgElevated.withValues(alpha: 0.73),
                        borderRadius: BorderRadius.circular(31),
                        border: Border.all(color: AppColors.hairline, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        _NavItem(
                          icon: Icons.home_outlined, activeIcon: Icons.home,
                          label: 'Нүүр', isActive: currentIndex == 0,
                          onTap: () => context.go(AppRoutes.feed)),
                        _NavItem(
                          icon: Icons.explore_outlined, activeIcon: Icons.explore,
                          label: 'Нээх', isActive: currentIndex == 1,
                          onTap: () => context.go(AppRoutes.explore)),
                        // FAB-ийн суудал — төв хоосон зай
                        const SizedBox(width: _fabSize + 18),
                        _NavItem(
                          icon: Icons.smart_display_outlined, activeIcon: Icons.smart_display,
                          label: 'Богино', isActive: currentIndex == 3,
                          onTap: () => context.go(AppRoutes.reels)),
                        _NavItem(
                          icon: Icons.person_outline, activeIcon: Icons.person,
                          label: 'Профайл', isActive: currentIndex == 4,
                          onTap: () => context.go(AppRoutes.profile)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

            // ── Төв CREATE FAB — док дээгүүр 16px өргөгдсөн gradient дугуй ──
            Positioned(
              top: 0, left: 0, right: 0,
              child: Center(
                child: _CreateFab(onTap: () => _showCreateSheet(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true, // контентдээ багтаж overflow гарахгүй
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Шинээр үүсгэх', style: AppTextStyles.h2),
            const SizedBox(height: 20),

            // Нийтлэл
            _CreateOption(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Нийтлэл',
              subtitle: 'Зураг эсвэл видео хуваалцах',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createPost);
              },
            ),
            const SizedBox(height: 12),

            // Богино видео (зөвхөн venue эзэд)
            _CreateOption(
              icon: Icons.explore_outlined,
              label: 'Богино видео',
              subtitle: 'Зөвхөн газрын эзэд нийтэлнэ',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createReel);
              },
            ),
            const SizedBox(height: 12),

            // Шууд
            _CreateOption(
              icon: Icons.sensors_rounded,
              label: 'Шууд',
              subtitle: 'Шууд дамжуулалт эхлүүлэх',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.goLive);
              },
            ),
            const SizedBox(height: 12),

            // Эвент
            _CreateOption(
              icon: Icons.event_rounded,
              label: 'Эвент',
              subtitle: 'Үйл явдал зарлах (бизнес)',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createEvent);
              },
            ),
          ]),
        ),
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith('/feed'))          return 0;
    if (location.startsWith('/explore'))       return 1;
    if (location.startsWith('/map'))           return 1;
    if (location.startsWith('/reels'))         return 3;
    if (location.startsWith('/profile'))       return 4;
    return 0;
  }
}

/// Tab — filled icon + доор нь 4px cyan glow цэг (label-гүй template хэлбэр).
/// label нь Semantics/Tooltip-д үлдэнэ — хүртээмж хэвээр.
// Идэвхтэй tab-ийн улаан гэрэл (spotlight) — хэрэглэгчийн дуртай дизайнаас буцаав
const Color _navActiveRed = Color(0xFFFF2E4D);

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    // ignore: unused_element_parameter — badge stream-ээс ирэх утга хожим холбогдоно
    this.badge = 0,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  // Улаан гэрэл "асах" хөдөлгөөн — ЗӨВХӨН tab солигдох үед нэг удаа тоглоно.
  // Тайван үедээ 1.0 дээр зогсох тул идэвхтэй tab бүрэн туяатай хэвээр
  // (тасралтгүй давталт байхгүй — CPU/батарей хэмнэнэ, анхаарал сарниулахгүй).
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420), value: 1);

  // Системийн "хөдөлгөөн багасгах" тохиргоо — статик туяа шууд харуулна
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
  }

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.isActive == old.isActive) return;
    // Идэвхтэй болмогц нэг удаа асна; хөдөлгөөн хаалттай бол шууд бүрэн туяа
    if (widget.isActive && !_reduceMotion) {
      _pulse.forward(from: 0);
    } else {
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final iconData = active ? widget.activeIcon : widget.icon;
    return Expanded(
      child: Semantics(
        label: widget.label,
        button: true,
        selected: active,
        child: Tooltip(
          message: widget.label,
          waitDuration: const Duration(milliseconds: 600),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Дээрээс тусах улаан туяа — tab солигдоход нэг удаа зөөлөн асна ──
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: active ? 1 : 0,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => CustomPaint(
                            size: const Size(double.infinity, 44),
                            painter: _BeamPainter(_navActiveRed,
                                intensity: 0.7 + 0.3 * _pulse.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Идэвхтэй icon томорч "сэргэх" + улаан glow (асахдаа тодорно)
                      AnimatedScale(
                        scale: active ? 1.0 : 0.9,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: Stack(clipBehavior: Clip.none, children: [
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, __) => Icon(iconData, size: 25,
                                color: active
                                    ? _navActiveRed
                                    : AppColors.textTertiary,
                                shadows: active
                                    ? [
                                        Shadow(
                                            color: _navActiveRed.withValues(
                                                alpha: 0.65 + 0.3 * _pulse.value),
                                            blurRadius: 16),
                                        Shadow(
                                            color: _navActiveRed.withValues(
                                                alpha: 0.3 + 0.2 * _pulse.value),
                                            blurRadius: 28),
                                      ]
                                    : null),
                          ),
                          if (widget.badge > 0)
                            Positioned(
                              top: -4, right: -8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.accentStart,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.bgElevated, width: 1.5),
                                ),
                                child: Text(
                                  widget.badge > 99 ? '99+' : '${widget.badge}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 5),
                      // ── 4px улаан glow цэг — идэвхтэй tab-ийн индикатор ──
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        width: 4, height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? _navActiveRed : Colors.transparent,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                      color: _navActiveRed.withValues(alpha: 0.85),
                                      blurRadius: 8, spreadRadius: 1),
                                ]
                              : const [],
                        ),
                      ),
                    ],
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

/// Дээрээс тусах конус хэлбэрийн улаан гэрэл (дээр нарийн, доош өргөн)
class _BeamPainter extends CustomPainter {
  final Color color;
  final double intensity; // 0..1 — туяа асах үеийн тодрол
  const _BeamPainter(this.color, {this.intensity = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    const topHalf = 10.0, botHalf = 27.0;
    final path = Path()
      ..moveTo(cx - topHalf, 0)
      ..lineTo(cx + topHalf, 0)
      ..lineTo(cx + botHalf, h)
      ..lineTo(cx - botHalf, h)
      ..close();
    final shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.55 * intensity), color.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, Paint()..shader = shader);
    // Гэрлийн эх — дээд ирмэг дээрх тод улаан зураас + glow
    final notch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, 2.5), width: topHalf * 2.4, height: 3.5),
      const Radius.circular(2));
    canvas.drawRRect(notch, Paint()
      ..color = color.withValues(alpha: intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(notch, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BeamPainter old) =>
      old.color != color || old.intensity != intensity;
}

class _CreateFab extends StatefulWidget {
  final VoidCallback onTap;
  const _CreateFab({required this.onTap});

  @override
  State<_CreateFab> createState() => _CreateFabState();
}

class _CreateFabState extends State<_CreateFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 1.2),
              boxShadow: AppColors.glowShadow(AppColors.accentStart,
                  alpha: 0.55, blur: 26, offset: const Offset(0, 8)),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon, required this.label, required this.subtitle,
    required this.gradient, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTextStyles.labelLg),
            const SizedBox(height: 3),
            Text(subtitle, style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textSecondary)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        ]),
      ),
    ),
  );
}
