import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../providers/live_provider.dart';

/// Feed дээд талын "🔴 LIVE NOW" хэвтээ rail
class LiveRail extends ConsumerWidget {
  const LiveRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livesAsync = ref.watch(activeLivesProvider);
    final lives = livesAsync.value ?? [];
    if (lives.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFFFF3B30))),
            const SizedBox(width: 6),
            Text('LIVE NOW', style: AppTextStyles.labelMd.copyWith(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
          ]),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: lives.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final l = lives[i];
              final initial = l.username.replaceAll('@', '').isNotEmpty
                  ? l.username.replaceAll('@', '')[0].toUpperCase() : '?';
              return GestureDetector(
                onTap: () => context.push('/live/view/${l.id}'),
                child: SizedBox(
                  width: 72,
                  child: Column(children: [
                    Stack(alignment: Alignment.bottomCenter, children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF3B30), Color(0xFFFF9500)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppColors.bgBase),
                          child: AppAvatar(
                            imageUrl: l.avatarUrl, initial: initial, size: 56),
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.bgBase, width: 1.5)),
                          child: const Text('LIVE', style: TextStyle(
                            color: Colors.white, fontSize: 8,
                            fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(l.username.replaceAll('@', ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.textSecondary)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
