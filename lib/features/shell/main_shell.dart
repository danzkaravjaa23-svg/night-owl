import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/router/app_router.dart';

/// Bottom nav shell — matches BottomNav JSX component
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBody: true, // floating bar контентын дээгүүр хөвнө
      body: child,
      bottomNavigationBar: _BottomNav(),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Доод ирмэгээс хөвүүлж, хажуу талаас зай авна
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // glassmorphism
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xB3121212), // rgba(18,18,18,0.7)
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 24, offset: const Offset(0, 8)),
              ],
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
              _CreateButton(onTap: () => _showCreateSheet(context)),
              _NavItem(
                icon: Icons.explore_outlined, activeIcon: Icons.explore,
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
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true, // контентдээ багтаж overflow гарахгүй
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Create', style: AppTextStyles.h2),
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
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    const mutedGray = Color(0xFF8A8A95); // идэвхгүй — намуухан саарал
    final color = isActive ? _navActiveRed : mutedGray;
    final iconData = isActive ? activeIcon : icon;
    // Идэвхтэй icon — улаан + гэрэлтэх улаан glow
    Widget iconWidget = isActive
        ? Icon(iconData, color: _navActiveRed, size: 26, shadows: [
            Shadow(color: _navActiveRed.withValues(alpha: 0.95), blurRadius: 16),
            Shadow(color: _navActiveRed.withValues(alpha: 0.5), blurRadius: 28),
          ])
        : Icon(iconData, color: mutedGray, size: 24);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Дээрээс тусах улаан гэрлийн туяа (зөвхөн идэвхтэй) ──
            if (isActive)
              Positioned(
                top: 0, left: 0, right: 0,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(double.infinity, 42),
                    painter: const _BeamPainter(_navActiveRed),
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  iconWidget,
                  if (badge > 0)
                    Positioned(
                      top: -4, right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accentStart,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.bgElevated, width: 1.5),
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
                const SizedBox(height: 3),
                Text(label, style: TextStyle(
                  fontSize: 10, color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Идэвхтэй tab-ийн улаан өнгө
const Color _navActiveRed = Color(0xFFFF2E4D);

/// Дээд ирмэгээс доош тусах улаан гэрлийн туяа (spotlight cone) + гэрлийн эх.
class _BeamPainter extends CustomPainter {
  final Color color;
  const _BeamPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    const topHalf = 10.0, botHalf = 27.0;
    // Конус (трапец) — дээр нарийн, доош өргөн
    final path = Path()
      ..moveTo(cx - topHalf, 0)
      ..lineTo(cx + topHalf, 0)
      ..lineTo(cx + botHalf, h)
      ..lineTo(cx - botHalf, h)
      ..close();
    final shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, Paint()..shader = shader);
    // Гэрлийн эх — дээд ирмэг дээрх тод улаан зураас + glow
    final notch = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, 2.5), width: topHalf * 2.4, height: 3.5),
      const Radius.circular(2));
    canvas.drawRRect(notch, Paint()
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(notch, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BeamPainter old) => old.color != color;
}

class _CreateButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                  color: AppColors.accentStart.withValues(alpha: 0.4),
                  blurRadius: 12, offset: const Offset(0, 4),
                )],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
          ],
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14)),
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
  );
}
