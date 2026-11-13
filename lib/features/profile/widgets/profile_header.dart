import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../models/user_profile.dart';

/// Profile identity and actions, using the person's actual profile data.
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final Widget avatar;
  final bool coverBusy;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onEditCover;
  final VoidCallback onSettings;
  final VoidCallback onActions;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;

  const ProfileHeader({
    super.key,
    required this.profile,
    required this.avatar,
    required this.onEdit,
    required this.onShare,
    required this.onEditCover,
    required this.onSettings,
    required this.onActions,
    required this.onFollowers,
    required this.onFollowing,
    this.coverBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final username =
        (profile.username?.trim() ?? '').replaceFirst(RegExp(r'^@+'), '');
    final name = profile.name?.trim() ?? '';
    final bio = profile.bio?.trim() ?? '';
    final title = name.isNotEmpty
        ? name
        : username.isNotEmpty
            ? '@$username'
            : 'Профайл';
    final coverHeight = 140 + MediaQuery.paddingOf(context).top;
    final avatarFrame = Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ]),
        child: avatar);
    return AppEntrance(
        child: ColoredBox(
            color: AppColors.bgBase,
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  // Reserve less height so the avatar overlaps the cover's lower edge.
                  height: coverHeight - 24,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: coverHeight,
                        child: _ProfileCover(
                            url: profile.coverUrl, busy: coverBusy)),
                    // Нүүр зураг дээрх нэгдсэн толгой (DS-06): status bar-ыг
                    // өөрөө тооцож, медиа дээр шилэн товчтой.
                    Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AppHeader.media(
                            title: 'Миний профайл',
                            centerTitle: true,
                            scrim: true,
                            leading: GlassIconButton(
                                icon: AppIcons.more,
                                onMedia: true,
                                tooltip: 'Профайлын үйлдлүүд',
                                onTap: onActions),
                            actions: [
                              GlassIconButton(
                                  icon: Icons.settings_outlined,
                                  onMedia: true,
                                  tooltip: 'Тохиргоо',
                                  onTap: onSettings),
                            ])),
                  ]),
                ),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(builder: (context, constraints) {
                            final stats = Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _ProfileStat(
                                          count: profile.postsCount,
                                          label: 'Пост')),
                                  Expanded(
                                      child: _ProfileStat(
                                          count: profile.followersCount,
                                          label: 'Дагагч',
                                          onPressed: onFollowers)),
                                  Expanded(
                                      child: _ProfileStat(
                                          count: profile.followingCount,
                                          label: 'Дагаж буй',
                                          onPressed: onFollowing)),
                                ]);
                            if (constraints.maxWidth < 360 &&
                                MediaQuery.textScalerOf(context).scale(19) >
                                    24) {
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    avatarFrame,
                                    const SizedBox(height: 10),
                                    stats
                                  ]);
                            }
                            return Row(children: [
                              avatarFrame,
                              const SizedBox(width: 12),
                              Expanded(child: stats)
                            ]);
                          }),
                          const SizedBox(height: 16),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Профайлын нэр — h1 token (жинхэнэ Inter
                                // Bold, DS-04)
                                Flexible(
                                    child: Text(title,
                                        style: AppTextStyles.h1
                                            .copyWith(height: 1.18))),
                                if (profile.isVerified) ...[
                                  const SizedBox(width: 6),
                                  Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Tooltip(
                                          message: 'Баталгаажсан профайл',
                                          child: Icon(Icons.verified,
                                              color: AppColors.accentText,
                                              size: 18))),
                                ],
                              ]),
                          if (name.isNotEmpty && username.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text('@$username',
                                style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3)),
                          ],
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(bio,
                                style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.5)),
                          ],
                          if (profile.interests.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final interest in profile.interests)
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                        color: AppColors.silver
                                            .withValues(alpha: .08),
                                        borderRadius:
                                            BorderRadius.circular(999)),
                                    child: Text(interest,
                                        style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                            height: 1.3))),
                            ]),
                          ],
                          const SizedBox(height: 20),
                          LayoutBuilder(builder: (context, constraints) {
                            // Primary + secondary pill (DS-03).
                            final edit = GradientButton(
                                label: 'Профайл засах',
                                size: GradientButtonSize.md,
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                onPressed: onEdit);
                            final share = OutlineButton(
                                label: 'Хуваалцах',
                                size: GradientButtonSize.md,
                                icon: Icon(AppIcons.share, size: 17),
                                onPressed: onShare);
                            if (constraints.maxWidth < 360 &&
                                MediaQuery.textScalerOf(context).scale(13) >
                                    17) {
                              return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    edit,
                                    // Room for the primary pill's lip and glow.
                                    const SizedBox(height: 12),
                                    share
                                  ]);
                            }
                            return Row(children: [
                              Expanded(child: edit),
                              const SizedBox(width: 10),
                              Expanded(child: share)
                            ]);
                          }),
                        ])),
              ]),
              // Keep the entire cover-edit target hittable across the overlapping edge.
              // The 44 px hit box has a 2 px inset, so right 18 puts the 40 px
              // disc on the 20 px gutter, like AppHeader's actions above it.
              Positioned(
                  right: 18,
                  top: coverHeight - 52,
                  child: GlassIconButton(
                      icon: Icons.photo_camera_outlined,
                      onMedia: true,
                      tooltip: 'Нүүр зураг солих',
                      onTap: coverBusy ? null : onEditCover)),
            ])));
  }
}

class ProfileContentTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const ProfileContentTabs(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const labels = ['Нийтлэл', 'Хадгалсан', 'Бичлэг'];
        final labelStyle = AppTextStyles.labelLg.copyWith(fontSize: 13);
        final labelWidth = constraints.maxWidth / labels.length - 8;
        final stacked = labels.any((label) {
          final painter = TextPainter(
              text: TextSpan(text: label, style: labelStyle),
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: Directionality.of(context),
              maxLines: 1)
            ..layout();
          final doesNotFit = painter.width > labelWidth;
          painter.dispose();
          return doesNotFit;
        });

        Widget tab(int index) {
          final active = selected == index;
          // DS-09: идэвхгүй — outline, идэвхтэй — filled.
          final icon = SculptedIcon(
              switch (index) {
                0 => Icons.grid_on_rounded,
                1 => active ? AppIcons.saveActive : AppIcons.save,
                _ => active ? AppIcons.shortVideoActive : AppIcons.shortVideo,
              },
              size: 21,
              color: active ? AppColors.silver : AppColors.textTertiary);
          final label = Text(labels[index],
              textAlign: stacked ? TextAlign.start : TextAlign.center,
              style: labelStyle.copyWith(
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary));
          return Semantics(
              button: true,
              selected: active,
              child: PressFeedback(
                  child: InkWell(
                      borderRadius: BorderRadius.circular(stacked ? 12 : 0),
                      onTap: () => onChanged(index),
                      child: AnimatedContainer(
                          duration:
                              AppMotion.duration(context, AppMotion.release),
                          padding: EdgeInsets.symmetric(
                              horizontal: stacked ? 14 : 4, vertical: 14),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: stacked && active
                                  ? AppColors.silver.withValues(alpha: .08)
                                  : Colors.transparent),
                          child: stacked
                              ? Row(children: [
                                  icon,
                                  const SizedBox(width: 12),
                                  Expanded(child: label),
                                  const SizedBox(width: 12),
                                  if (active)
                                    Icon(Icons.check_rounded,
                                        size: 20, color: AppColors.silver)
                                  else
                                    const SizedBox(width: 20),
                                ])
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                      icon,
                                      const SizedBox(height: 4),
                                      label,
                                    ])))));
        }

        if (stacked) {
          return Column(children: [
            for (var index = 0; index < labels.length; index++) tab(index),
          ]);
        }
        return Container(
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.hairline))),
          child: Stack(children: [
            IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(child: tab(index)),
                ])),
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedAlign(
                    alignment: Alignment(selected - 1.0, 0),
                    duration: AppMotion.duration(
                        context, const Duration(milliseconds: 380)),
                    curve: Curves.easeOutCubic,
                    child: FractionallySizedBox(
                        widthFactor: 1 / 3,
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: AppColors.silver),
                        )),
                  ),
                )),
          ]),
        );
      });
}

class _ProfileStat extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback? onPressed;
  const _ProfileStat(
      {required this.count, required this.label, this.onPressed});

  String get formatted {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Статистик — AppTextStyles token (DS-04)
          Text(formatted,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2.copyWith(height: 1.2)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(height: 1.4)),
        ]));
    return onPressed == null
        ? content
        : InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: content);
  }
}

class _ProfileCover extends StatelessWidget {
  final String? url;
  final bool busy;
  const _ProfileCover({this.url, required this.busy});

  Widget _fallback() => Image.asset('assets/images/tonight_city.png',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.15),
      errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.bgElevated));

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 140,
      child: Stack(fit: StackFit.expand, children: [
        if (url?.isNotEmpty == true)
          CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: 1200,
              placeholder: (_, __) => ColoredBox(color: AppColors.bgElevated),
              errorWidget: (_, __, ___) => _fallback())
        else
          _fallback(),
        DecoratedBox(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [
              0,
              0.6,
              1
            ],
                    colors: [
              const Color(0x240B0D17),
              AppColors.bgBase.withValues(alpha: 0.12),
              AppColors.bgBase
            ]))),
        if (busy)
          const Center(
              child: OwlLoading(
                  size: 32,
                  compact: true,
                  onDark: true,
                  message: 'Нүүр зургийг хадгалж байна')),
      ]));
}
