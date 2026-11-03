import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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
                    Positioned(
                        top: 0,
                        left: 20,
                        right: 20,
                        child: SafeArea(
                            bottom: false,
                            child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(children: [
                                  _CoverAction(
                                      icon: Icons.more_horiz_rounded,
                                      label: 'Профайлын үйлдлүүд',
                                      onPressed: onActions),
                                  const Expanded(
                                      child: Text('Миний профайл',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600))),
                                  _CoverAction(
                                      icon: Icons.settings_outlined,
                                      label: 'Тохиргоо',
                                      onPressed: onSettings),
                                ])))),
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
                                Flexible(
                                    child: Text(title,
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.6,
                                            height: 1.18))),
                                if (profile.isVerified) ...[
                                  const SizedBox(width: 6),
                                  const Padding(
                                      padding: EdgeInsets.only(top: 3),
                                      child: Tooltip(
                                          message: 'Баталгаажсан профайл',
                                          child: Icon(Icons.verified,
                                              color: AppColors.accentStart,
                                              size: 18))),
                                ],
                              ]),
                          if (name.isNotEmpty && username.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text('@$username',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3)),
                          ],
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(bio,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
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
                            final edit = PressFeedback(
                                child: FilledButton.icon(
                                    onPressed: onEdit,
                                    style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.accentStart,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(48),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        textStyle: AppTextStyles.btnSm.copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    icon: const SculptedIcon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: Colors.white,
                                        onDark: true),
                                    label: const Text('Профайл засах',
                                        textAlign: TextAlign.center)));
                            final share = PressFeedback(
                                child: OutlinedButton.icon(
                                    onPressed: onShare,
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textPrimary,
                                        minimumSize: const Size.fromHeight(48),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 14),
                                        side: BorderSide(
                                            color: AppColors.hairline2),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        textStyle: AppTextStyles.btnSm.copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    icon: SculptedIcon(Icons.ios_share_rounded,
                                        size: 17, color: AppColors.textPrimary),
                                    label: const Text('Хуваалцах',
                                        textAlign: TextAlign.center)));
                            if (constraints.maxWidth < 360 &&
                                MediaQuery.textScalerOf(context).scale(13) >
                                    17) {
                              return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    edit,
                                    const SizedBox(height: 8),
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
              Positioned(
                  right: 20,
                  top: coverHeight - 54,
                  child: _CoverAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Нүүр зураг солих',
                      onPressed: coverBusy ? null : onEditCover)),
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
          final icon = SculptedIcon(
              [
                Icons.grid_on_rounded,
                Icons.bookmark_border_rounded,
                Icons.play_circle_outline_rounded
              ][index],
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
          Text(formatted,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.2)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
        ]));
    return onPressed == null
        ? content
        : InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: content);
  }
}

class _CoverAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _CoverAction({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => PressFeedback(
      enabled: onPressed != null,
      child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          style: IconButton.styleFrom(
              backgroundColor: const Color(0x450B0D17),
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44)),
          icon:
              SculptedIcon(icon, size: 22, color: Colors.white, onDark: true)));
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
