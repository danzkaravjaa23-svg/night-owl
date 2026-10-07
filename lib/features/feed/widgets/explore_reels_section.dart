import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/widgets/owl_loading.dart';
import '../providers/reels_provider.dart';

/// Lightweight, paused previews within Explore's parent scroll view.
/// Opening a card passes its real post ID to the vertical reel viewer.
class ExploreReelsSection extends ConsumerWidget {
  final ValueChanged<String?>? onOpenReel;
  const ExploreReelsSection({super.key, this.onOpenReel});

  void _open(BuildContext context, [String? id]) {
    if (onOpenReel != null) {
      onOpenReel!(id);
    } else {
      context.push(
          Uri(path: '/reels', queryParameters: id == null ? null : {'id': id})
              .toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reels = ref.watch(reelsProvider);
    return Column(
      key: const ValueKey('explore-reels-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 12, 4),
          child: LayoutBuilder(builder: (context, constraints) {
            final title = Text('Богино бичлэгүүд',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20));
            final action = TextButton(
              onPressed: () => _open(context),
              child: const Text('Бүгдийг үзэх'),
            );
            if (constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(20) > 24) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, action]);
            }
            return Row(children: [Expanded(child: title), action]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text('Газруудын уур амьсгалыг ойроос мэдрээрэй.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        ),
        reels.when(
          skipLoadingOnRefresh: false,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child:
                    OwlLoading(message: 'Бичлэгүүдийг ачаалж байна', size: 44)),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
                child: OwlLoading(
              state: OwlLoadingState.error,
              message: 'Бичлэгүүдийг ачаалж чадсангүй',
              detail: 'Холболтоо шалгаад дахин оролдоорой.',
              size: 44,
              onRetry: () => ref.invalidate(reelsProvider),
            )),
          ),
          data: (items) => items.isEmpty
              ? Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(22),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.hairline)),
                  child: Column(children: [
                    Icon(Icons.video_library_outlined,
                        color: AppColors.neonCyan, size: 32),
                    const SizedBox(height: 10),
                    Text('Шинэ бичлэгүүд удахгүй',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Газруудын нийтэлсэн богино бичлэгүүд энд харагдана.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, height: 1.4)),
                  ]),
                )
              : SizedBox(
                  height: 280,
                  child: ListView.separated(
                    key: const PageStorageKey('explore-reel-previews'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _ReelPreview(
                        reel: items[i],
                        onTap: () => _open(context, items[i]['id'] as String)),
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReelPreview extends StatelessWidget {
  final Map<String, dynamic> reel;
  final VoidCallback onTap;
  const _ReelPreview({required this.reel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profile = reel['profiles'] as Map?;
    final username = profile?['username'] as String? ?? 'night owl';
    final caption = (reel['caption'] as String? ?? '').trim();
    return SizedBox(
      key: ValueKey('explore-reel-${reel['id']}'),
      width: 176,
      child: Semantics(
        button: true,
        label: '$username. ${caption.isEmpty ? 'Богино бичлэг үзэх' : caption}',
        child: PressFeedback(
            child: Material(
          color: AppColors.bgElevatedDark,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(fit: StackFit.expand, children: [
              IgnorePointer(
                  child: NetworkVideo(
                key: ValueKey(reel['media_url']),
                url: reel['media_url'] as String,
                posterOnly: true,
                autoplay: false,
                active: false,
                showPosterIcon: false,
              )),
              const IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x33000000),
                      Color(0xE6000000)
                    ],
                    stops: [
                      0,
                      .5,
                      1
                    ]),
              ))),
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 44)),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('@${username.replaceAll('@', '')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      if (caption.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.3)),
                      ],
                    ]),
              ),
            ]),
          ),
        )),
      ),
    );
  }
}
