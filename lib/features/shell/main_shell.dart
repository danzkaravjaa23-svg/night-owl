import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
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
  static const double _dockHeight = 62; // glass бар өндөр
  static const double _fabSize = 54;    // төв CREATE FAB
  static const double _fabLift = 16;    // FAB док дээгүүр цухуйх хэмжээ

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Доод ирмэгээс хөвүүлж, хажуу талаас 20 зай (дэлгэцийн padding-тай ижил)
      padding: EdgeInsets.fromLTRB(20, 0, 20, 14 + bottomInset),
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
                      child: Row(children: [
                        _NavItem(
                          icon: Icons.home_outlined, activeIcon: Icons.home,
                          label: 'Feed', isActive: currentIndex == 0,
                          onTap: () => context.go(AppRoutes.feed)),
                        _NavItem(
                          icon: Icons.explore_outlined, activeIcon: Icons.explore,
                          label: 'Explore', isActive: currentIndex == 1,
                          onTap: () => context.go(AppRoutes.explore)),
                        // FAB-ийн суудал — төв хоосон зай
                        const SizedBox(width: _fabSize + 18),
                        _NavItem(
                          icon: Icons.smart_display_outlined, activeIcon: Icons.smart_display,
                          label: 'Discovery', isActive: currentIndex == 3,
                          onTap: () => context.go(AppRoutes.reels)),
                        _NavItem(
                          icon: Icons.person_outline, activeIcon: Icons.person,
                          label: 'Profile', isActive: currentIndex == 4,
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

            // Post
            _CreateOption(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Post',
              subtitle: 'Photo эсвэл video хуваалцах',
              gradient: AppColors.accentGradient,
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createPost);
              },
            ),
            const SizedBox(height: 12),

            // Discovery (зөвхөн venue эзэд)
            _CreateOption(
              icon: Icons.explore_outlined,
              label: 'Discovery',
              subtitle: 'Богино видео — зөвхөн venue эзэд',
              gradient: const LinearGradient(
                  colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)]),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.createReel);
              },
            ),
            const SizedBox(height: 12),

            // Live
            _CreateOption(
              icon: Icons.sensors_rounded,
              label: 'Live',
              subtitle: 'Шууд дамжуулалт эхлүүлэх',
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)]),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.goLive);
              },
            ),
            const SizedBox(height: 12),

            // Event
            _CreateOption(
              icon: Icons.event_rounded,
              label: 'Event',
              subtitle: 'Үйл явдал зарлах (бизнес)',
              gradient: const LinearGradient(
                  colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
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
class _NavItem extends StatelessWidget {
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
  }) : badge = 0;

  @override
  Widget build(BuildContext context) {
    final iconData = isActive ? activeIcon : icon;
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: isActive,
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 600),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Идэвхтэй icon томорч "сэргэх" — идэвхгүй нь жаахан жижиг
                  AnimatedScale(
                    scale: isActive ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Icon(iconData, size: 25,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          shadows: isActive
                              ? [
                                  Shadow(
                                      color: AppColors.neonCyan
                                          .withValues(alpha: 0.45),
                                      blurRadius: 16),
                                ]
                              : null),
                      if (badge > 0)
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
                              badge > 99 ? '99+' : '$badge',
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
                  // ── 4px cyan glow цэг — идэвхтэй tab-ийн индикатор ──
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? AppColors.neonCyan
                          : Colors.transparent,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                  color: AppColors.neonCyan
                                      .withValues(alpha: 0.85),
                                  blurRadius: 8, spreadRadius: 1),
                            ]
                          : const [],
                    ),
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

/// Төв CREATE FAB — 54px gradient дугуй, хүчтэй неон glow, дарахад агшина.
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
