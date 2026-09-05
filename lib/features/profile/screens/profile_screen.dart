import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../models/story.dart';
import '../../feed/providers/stories_provider.dart';
import '../../feed/screens/story_viewer_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/utils/image_compress.dart';
import '../../../core/utils/web_media_picker.dart';
import '../widgets/invite_sheet.dart';
import '../utils/app_links.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tab = 0; // 0 = Posts, 1 = Reels
  int _refreshTick = 0; // pull-to-refresh-д grid дахин ачаалах
  bool _coverBusy = false;

  // Cover зураг солих — сонгоод шахаж upload хийгээд profiles.cover_url шинэчилнэ
  Future<void> _changeCover(String uid) async {
    if (_coverBusy) return;
    final bytes = await pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      final out = await compressToJpeg(bytes, maxDim: 1600);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await ImageUploader.uploadBytes(
        bytes: out, bucket: 'avatars', path: '$uid/cover_$ts.jpg');
      if (url == null) throw Exception('upload failed');
      await SupabaseService.client.from('profiles')
          .update({'cover_url': url}).eq('id', uid);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cover зураг хадгалж чадсангүй'),
          backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _coverBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentStart)),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 14),
            Text('Алдаа гарлаа', style: AppTextStyles.h2),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(currentProfileProvider),
              child: const Text('Дахин оролдох'),
            ),
          ]),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('👤', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text('Профайл олдсонгүй', style: AppTextStyles.h2),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.go(AppRoutes.setup),
                  child: const Text('Профайл үүсгэх'),
                ),
              ]),
            );
          }

          // Өөрийн идэвхтэй story (байвал avatar дээр ринг харагдана)
          final myRing = ref.watch(storiesProvider).maybeWhen<StoryRing?>(
            data: (rings) {
              for (final r in rings) {
                if (r.userId == profile.id) return r;
              }
              return null;
            },
            orElse: () => null,
          );

          return Stack(children: [
            // Агаарын неон гэрэлтэлт — magenta зүүн дээд, cyan баруун доод
            Positioned(top: -120, left: -80,
                child: _GlowBlob(size: 300, color: AppColors.magenta.withValues(alpha: 0.10))),
            Positioned(bottom: -100, right: -60,
                child: _GlowBlob(size: 280, color: AppColors.neonCyan.withValues(alpha: 0.07))),
            RefreshIndicator(
            color: AppColors.accentStart,
            backgroundColor: AppColors.bgElevated,
            onRefresh: () async {
              ref.invalidate(currentProfileProvider);
              ref.invalidate(storiesProvider);
              setState(() => _refreshTick++);
              await ref.read(currentProfileProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
            // ── Hero: бүтэн өргөн cover + голд давхарласан avatar (template) ──
            SliverToBoxAdapter(
              child: Column(children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Cover 160 — ирмэггүй, доошоо bgBase руу уусна
                    _CoverImage(
                      url: profile.coverUrl,
                      busy: _coverBusy,
                      onEdit: () => _changeCover(profile.id),
                    ),
                    // Дээд үйлдлүүд — cover дээгүүр glass товчнууд
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // 💬 Чат (DM)
                              _GlassRoundBtn(
                                icon: Icons.chat_bubble_outline,
                                onTap: () => context.push(AppRoutes.dmList),
                              ),
                              const SizedBox(width: 8),
                              // 🔖 Хадгалсан
                              _GlassRoundBtn(
                                icon: Icons.bookmark_border,
                                onTap: () => context.push(AppRoutes.saved),
                              ),
                              const SizedBox(width: 8),
                              // 🔗 Хуваалцах (clipboard)
                              _GlassRoundBtn(
                                icon: Icons.ios_share,
                                onTap: () => _shareProfile(context, profile),
                              ),
                              const SizedBox(width: 8),
                              // ⚙️ Тохиргоо
                              _GlassRoundBtn(
                                icon: Icons.menu,
                                onTap: () => context.push(AppRoutes.settings),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Avatar 96 — cover-ийг -48 давхарлан голд
                    Positioned(
                      bottom: -48,
                      child: _ProfileStoryAvatar(
                        avatarUrl: profile.avatarUrl,
                        initial: profile.initial,
                        ring: myRing,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 60),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    // ── Нэр (голд, h2) ──
                    if (profile.name?.isNotEmpty == true)
                      Text(profile.name!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.h2),
                    const SizedBox(height: 4),

                    // ── @handle — neonCyan eyebrow ──
                    Text('@${profile.username ?? 'profile'}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.neonCyan, letterSpacing: 1.2)),

                    // ── Bio (голд, 2 мөр) ──
                    if (profile.bio?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(profile.bio!,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.textSecondary, height: 1.45)),
                      ),
                    ],

                    // ── Сонирхлууд (cyan chips, голд) ──
                    if (profile.interests.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: profile.interests
                            .map((tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 11, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonCyan
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: AppColors.neonCyan
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Text(tag,
                                      style: AppTextStyles.bodyXs.copyWith(
                                          color: AppColors.neonCyan,
                                          fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ── Stats — нэг glass card, hairline хуваагчтай 3 багана ──
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.hairline),
                        boxShadow: AppColors.shadowCard,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(children: [
                        Expanded(
                            child: _Stat(
                                count: _fmt(profile.postsCount),
                                label: 'ПОСТ')),
                        Container(
                            width: 1, height: 36, color: AppColors.hairline),
                        Expanded(
                            child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Буцахад тоо шинэчлэгдэхээр provider-г invalidate хийнэ
                          onTap: () async {
                            await context.push(
                                '/follows/${profile.id}?tab=followers');
                            ref.invalidate(currentProfileProvider);
                          },
                          child: _Stat(
                              count: _fmt(profile.followersCount),
                              label: 'ДАГАГЧ',
                              gradient: true),
                        ))),
                        Container(
                            width: 1, height: 36, color: AppColors.hairline),
                        Expanded(
                            child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await context.push(
                                '/follows/${profile.id}?tab=following');
                            ref.invalidate(currentProfileProvider);
                          },
                          child: _Stat(
                              count: _fmt(profile.followingCount),
                              label: 'ДАГАЖ БУЙ'),
                        ))),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Action мөр: gradient pill + дөрвөлжин glass товчнууд ──
                    Row(children: [
                      Expanded(
                        child: GradientButton(
                          label: 'Профайл засах',
                          height: 48,
                          borderRadius: 999,
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 16),
                          onPressed: () => context.push(AppRoutes.setup),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SquareGlassBtn(
                        icon: Icons.ios_share,
                        onTap: () => _shareProfile(context, profile),
                      ),
                      const SizedBox(width: 10),
                      _SquareGlassBtn(
                        icon: Icons.person_add_outlined,
                        onTap: () => showInviteSheet(context),
                      ),
                    ]),
                    const SizedBox(height: 14),

                    // ── Glass list — Бизнес самбар (+ Админ) нэг картад ──
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.hairline),
                        boxShadow: AppColors.shadowCard,
                      ),
                      child: Column(children: [
                        // 🏪 Бизнес самбар (Газраа удирдах / Event / Live)
                        _GlassListRow(
                          icon: Icons.storefront_outlined,
                          iconColor: AppColors.neonCyan,
                          title: 'Бизнес самбар',
                          subtitle: 'Газраа удирдах · Event · Live',
                          onTap: () => context.push(AppRoutes.business),
                        ),
                        // 🛡️ Админ панел (зөвхөн админд)
                        if (profile.isAdmin) ...[
                          Container(
                              height: 1,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              color: AppColors.hairline),
                          _GlassListRow(
                            icon: Icons.shield_outlined,
                            iconColor: AppColors.error,
                            title: 'Админ панел',
                            onTap: () => context.push(AppRoutes.adminPanel),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 28),

                    // ── Icon-only таб (grid / reels) — cyan underline glow ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _IconTab(
                            icon: Icons.grid_on,
                            selected: _tab == 0,
                            onTap: () => setState(() => _tab = 0)),
                        const SizedBox(width: 40),
                        _IconTab(
                            icon: Icons.play_arrow_rounded,
                            selected: _tab == 1,
                            onTap: () => setState(() => _tab = 1)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ]),
                ),
              ]),
            ),

            // ── Grid (tab-аас хамаарна) — нягт 2px завсартай template grid ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: _PostsGrid(
                  key: ValueKey(_refreshTick),
                  userId: profile.id,
                  reelsOnly: _tab == 1),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
          ),
          ]);
        },
      ),
    );
  }

  // Профайл холбоосыг clipboard-д хуулах (одоо байгаа handler)
  Future<void> _shareProfile(BuildContext context, dynamic profile) async {
    HapticFeedback.lightImpact();
    // Жинхэнэ deploy origin-оос холбоос үүсгэнэ (өмнөх nightowl.ub үхмэл байсан)
    final link = profileLink(profile.id as String);
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Профайл холбоос хуулагдлаа 🔗 $link')));
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Дэлгэцийн ард зөөлөн неон гэрэлтэлт (radial blob)
class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent]),
          ),
        ),
      );
}

/// Glass round button — cover дээгүүрх үйлдлийн товч
class _GlassRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassRoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgBase.withValues(alpha: 0.55),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 19),
          ),
        ),
      );
}

/// Дөрвөлжин glass icon товч — gradient pill-ийн хажууд (48×48)
class _SquareGlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SquareGlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline2),
              color: AppColors.bgElevated.withValues(alpha: 0.72),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 19),
          ),
        ),
      );
}

/// Glass list мөр — icon + гарчиг + subtitle + chevron
class _GlassListRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _GlassListRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: AppTextStyles.bodyXs
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 18),
            ]),
          ),
        ),
      );
}

// ─── Icon-only таб — сонгогдсон үед cyan underline glow bar 24×3 ───
class _IconTab extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _IconTab(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 24,
                  color:
                      selected ? AppColors.neonCyan : AppColors.textTertiary),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color:
                      selected ? AppColors.neonCyan : Colors.transparent,
                  boxShadow: selected
                      ? AppColors.glowShadow(AppColors.neonCyan)
                      : null,
                ),
              ),
            ]),
          ),
        ),
      );
}

// ─── Posts grid (cursor pagination / infinite scroll) ───
class _PostsGrid extends StatefulWidget {
  final String userId;
  final bool reelsOnly;
  const _PostsGrid({super.key, required this.userId, this.reelsOnly = false});

  @override
  State<_PostsGrid> createState() => _PostsGridState();
}

class _PostsGridState extends State<_PostsGrid> {
  static const _pageSize = 30;
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _error = false; // татах алдаа — жагсаалт дуусснаас ялгаж retry үзүүлнэ
  DateTime? _cursor;

  static bool _isVid(String? url) => url != null && (
      url.endsWith('.mp4') || url.endsWith('.webm') ||
      url.endsWith('.mov') || url.endsWith('.m4v'));

  // Профайлын постыг (live/reel/зураг) шууд устгах (удаан дарахад)
  Future<void> _confirmDeleteTile(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ пост/бичлэгийг бүрмөсөн устгана.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Устгах', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    final me = SupabaseService.currentUser?.id;
    try {
      await SupabaseService.client.from('posts')
          .delete().eq('id', id).eq('user_id', me!);
      if (mounted) {
        setState(() => _posts.removeWhere((p) => p['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _error = false;
    try {
      var q = SupabaseService.client
          .from('posts')
          .select('id, media_url, likes_count, created_at')
          .eq('user_id', widget.userId);
      if (_cursor != null) {
        q = q.lt('created_at', _cursor!.toIso8601String());
      }
      final data = await q
          .order('created_at', ascending: false)
          .limit(_pageSize);
      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isNotEmpty) {
        _cursor = DateTime.tryParse(rows.last['created_at'] as String? ?? '');
      }
      _hasMore = rows.length == _pageSize;
      _posts.addAll(rows);
    } catch (_) {
      // Түр зуурын алдааг "жагсаалт дууссан" мэт бүү харагдуул — retry үзүүлнэ
      _error = true;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  // Detail-аас буцахад — grid-ийг чимээгүй шинэчлэх (blank flash-гүй).
  // Хуучин мөрүүд харагдсаар байгаад, шинэ page1 ирэхэд солигдоно.
  Future<void> _refreshInPlace() async {
    if (_loading) return;
    _loading = true;
    _error = false;
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id, media_url, likes_count, created_at')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(_pageSize);
      final rows = (data as List).cast<Map<String, dynamic>>();
      _posts
        ..clear()
        ..addAll(rows);
      _cursor = rows.isNotEmpty
          ? DateTime.tryParse(rows.last['created_at'] as String? ?? '')
          : null;
      _hasMore = rows.length == _pageSize;
    } catch (_) {
      // Шинэчлэл бүтэлгүйтвэл хуучин мөрүүдийг хэвээр үлдээнэ (blank хийхгүй)
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.reelsOnly
        ? _posts.where((p) => _isVid(p['media_url'] as String?)).toList()
        : _posts;

    // Эхний хуудас алдаа өгсөн бөгөөд хоосон бол — retry (хоосон төлөвтэй андуурахгүй)
    if (shown.isEmpty && _error && !_loading) {
      return SliverToBoxAdapter(child: _retryBlock());
    }

    // Хоосон (бүгд ачаалагдсан, алдаагүй) — artistic neon empty state
    if (shown.isEmpty && !_hasMore && !_loading && !_error) {
      return SliverToBoxAdapter(
        child: EmptyState(
          illustration: widget.reelsOnly
              ? 'assets/images/illustrations/empty_creator.svg'
              : 'assets/images/illustrations/empty_profile.svg',
          title: 'Одоохондоо хоосон',
          subtitle: widget.reelsOnly
              ? 'Эхний бичлэгээ хуваалцаарай'
              : 'Эхний шөнийн мөчөө хуваалцаарай',
        ),
      );
    }

    return SliverMainAxisGroup(slivers: [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _tile(shown[i]),
          childCount: shown.length,
        ),
      ),
      // Footer — алдаа/дуусаагүй байдлаас хамаарна
      SliverToBoxAdapter(
        child: _error
            ? _retryBlock()
            : _hasMore
                ? Builder(builder: (_) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _loadMore());
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(
                          color: AppColors.accentStart, strokeWidth: 2)),
                    );
                  })
                : const SizedBox(height: 24),
      ),
    ]);
  }

  // Татах алдааны retry блок — footer болон эхний хуудсанд ашиглана
  Widget _retryBlock() => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined,
            color: AppColors.textTertiary, size: 36),
        const SizedBox(height: 10),
        Text('Ачаалж чадсангүй',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () { _error = false; _loadMore(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(999)),
              child: Text('Дахин оролдох',
                  style: AppTextStyles.btn.copyWith(color: Colors.white)),
            ),
          ),
        ),
      ]),
    ),
  );

  Widget _tile(Map<String, dynamic> post) {
    final mediaUrl = post['media_url'] as String?;
    final likes = post['likes_count'] as int? ?? 0;
    final isVideo = _isVid(mediaUrl);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () async {
        await context.push('/post/${post['id']}');
        // Detail-аас буцахад grid-ийг blank хийхгүйгээр чимээгүй шинэчилнэ
        // (устгал/засварыг тусгана, гулгалт хадгалагдана)
        if (mounted) _refreshInPlace();
      },
      onLongPress: () => _confirmDeleteTile(post['id'] as String),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(fit: StackFit.expand, children: [
          if (mediaUrl != null && !isVideo)
            CachedNetworkImage(
              imageUrl: mediaUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400, // grid thumbnail — жижиг decode, хурдан
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, __) => Container(color: AppColors.bgSurface),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.bgSurface,
                child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.textTertiary)),
            )
          else if (isVideo)
            // Видеоны эхний кадрыг cover болгож харуулна (icon-гүй — grid өөрөө
            // videocam badge нэмдэг; posterOnly нь pointerEvents=none тул дарагдана).
            NetworkVideo(url: mediaUrl!, posterOnly: true, showPosterIcon: false)
          else
            Container(
              color: AppColors.bgSurface,
              child: const Icon(Icons.image_outlined, color: AppColors.textTertiary)),

          if (isVideo)
            Positioned(
              top: 6, right: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.bgBase.withValues(alpha: 0.5),
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: AppColors.neonCyan, size: 14),
              ),
            ),

          if (likes > 0)
            Positioned(
              bottom: 6, left: 6,
              child: Row(children: [
                const Icon(Icons.favorite, color: Colors.white, size: 12),
                const SizedBox(width: 3),
                Text('$likes', style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
              ]),
            ),
        ]),
      ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String count, label;
  final bool gradient;
  const _Stat({required this.count, required this.label, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    final numStyle = AppTextStyles.displaySm.copyWith(fontSize: 22, height: 1);
    final numWidget = gradient
        ? ShaderMask(
            shaderCallback: (r) => AppColors.accentGradient.createShader(r),
            child: Text(count, style: numStyle.copyWith(color: Colors.white)),
          )
        : Text(count, style: numStyle);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      numWidget,
      const SizedBox(height: 6),
      Text(label,
          style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 1.2)),
    ]);
  }
}

/// Профайлын avatar (96) — идэвхтэй story байвал storyRingGradient ринг +
/// дарж үзэх, доор нь "+" товч (шинэ story нэмэх). Instagram маягийн.
class _ProfileStoryAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final StoryRing? ring;
  const _ProfileStoryAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.ring,
  });

  @override
  Widget build(BuildContext context) {
    final hasStory = ring != null;
    return Stack(clipBehavior: Clip.none, children: [
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: hasStory
            ? () => Navigator.of(context).push(PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, __, ___) => StoryViewerScreen(rings: [ring!]),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c)))
            : () => context.push('/story/create'),
          child: hasStory
              // Story байвал — storyRingGradient ринг + неон glow
              ? Container(
                  width: 96, height: 96,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.storyRingGradient,
                    boxShadow: AppColors.glowShadow(AppColors.neonCyan),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.bgBase),
                    child: AppAvatar(
                        imageUrl: avatarUrl, initial: initial, size: 84),
                  ),
                )
              // Story-гүй — bgBase хүрээтэй цэвэр avatar (cover-оос ялгарна)
              : Container(
                  width: 96, height: 96,
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.bgBase),
                  child: AppAvatar(
                      imageUrl: avatarUrl, initial: initial, size: 88),
                ),
        ),
      ),
      // "+" товч → шинэ story
      Positioned(
        right: 0, bottom: 2,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => context.push('/story/create'),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
                border: Border.all(color: AppColors.bgBase, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentStart.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: -1,
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16)),
          ),
        ),
      ),
    ]);
  }
}

/// Профайлын cover — бүтэн өргөн 160, доошоо bgBase руу уусна,
/// байхгүй бол неон gradient fallback, солих товч (камер icon).
class _CoverImage extends StatelessWidget {
  final String? url;
  final bool busy;
  final VoidCallback onEdit;
  const _CoverImage({required this.url, required this.onEdit, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        if (url != null && url!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: 900,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => Container(color: AppColors.bgSurface),
            errorWidget: (_, __, ___) => _fallback())
        else
          _fallback(),
        // Доод fade — void bg руу бүрэн уусаж avatar ялгарна
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x66050505), AppColors.bgBase],
            stops: [0.4, 0.75, 1.0]))),
        // Upload явж байх үед — бүдгэрсэн давхарга + spinner (сунжран удаж болзошгүй)
        if (busy)
          Container(
            color: Colors.black.withValues(alpha: 0.45),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 26, height: 26,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5)),
          ),
        // Солих товч (upload үед идэвхгүй) — баруун доод, avatar-т саадгүй
        Positioned(bottom: 12, right: 16, child: MouseRegion(
          cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
          onTap: busy ? null : onEdit,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white24)),
            child: Icon(Icons.photo_camera_outlined,
              color: busy ? Colors.white38 : Colors.white, size: 18))))),
      ]),
    );
  }

  Widget _fallback() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF1A1A26), Color(0xFF23233A), Color(0xFF141420)])),
    child: Center(child: Icon(Icons.image_outlined,
      color: Colors.white.withValues(alpha: 0.14), size: 40)),
  );
}
