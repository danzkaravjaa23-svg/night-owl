import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/follow_provider.dart';

/// Дагагч / Дагаж буй хүмүүсийн жагсаалт — таб солих боломжтой.
/// Мөр бүр дээр follow/unfollow товч (өөрөөс бусад хүнд).
class FollowListScreen extends StatefulWidget {
  final String userId;
  final bool showFollowers; // true=Дагагч, false=Дагаж буй
  const FollowListScreen({
    super.key,
    required this.userId,
    this.showFollowers = true,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late bool _followers = widget.showFollowers;
  bool _loading = true;
  bool _error = false; // ачаалал бүтэлгүйтсэн эсэх (хоосон төлөвөөс ялгах)
  List<Map<String, dynamic>> _people = const [];
  Set<String> _iFollow = {};
  final _busy = <String>{}; // товч дарж байгаа id-ууд
  int _reqToken = 0; // таб солих race-аас сэргийлэх токен

  String? get _me => SupabaseService.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2)));

  Future<void> _load() async {
    // Хүсэлт бүрт токен — сүүлчийнх нь л _people-д бичнэ (таб солих гулгалтаас сэргийлнэ)
    final token = ++_reqToken;
    final wantFollowers = _followers;
    // Анхны/хоосон үед л бүтэн spinner; refresh үед хуучин мөрүүд харагдана
    setState(() { _error = false; if (_people.isEmpty) _loading = true; });
    try {
      final results = await Future.wait([
        wantFollowers
            ? FollowService.getFollowers(widget.userId)
            : FollowService.getFollowing(widget.userId),
        FollowService.myFollowingIds(),
      ]);
      if (!mounted || token != _reqToken) return; // хуучирсан хүсэлт — үл тоомсорло
      setState(() {
        _people = results[0] as List<Map<String, dynamic>>;
        _iFollow = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _toggle(String id) async {
    if (_busy.contains(id)) return;
    final wasFollowing = _iFollow.contains(id);
    setState(() {
      _busy.add(id);
      if (wasFollowing) {
        _iFollow.remove(id);
      } else {
        _iFollow.add(id);
      }
    });
    try {
      if (wasFollowing) {
        await FollowService.unfollow(id);
      } else {
        await FollowService.follow(id);
      }
    } catch (_) {
      // rollback + хэрэглэгчид мэдэгдэх (чимээгүй эргэх нь glitch мэт харагддаг)
      if (mounted) {
        setState(() {
          if (wasFollowing) {
            _iFollow.add(id);
          } else {
            _iFollow.remove(id);
          }
        });
        _toast('Үйлдэл амжилтгүй, дахин оролдоно уу');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(children: [
          // ── Дээд бар — glass буцах товч + h2 гарчиг ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(children: [
              _GlassBackBtn(
                onTap: () => context.canPop()
                    ? context.pop()
                    : context.go('/profile'),
              ),
              const SizedBox(width: 14),
              Text('Хүмүүс', style: AppTextStyles.h2),
            ]),
          ),
          // ── Таб солигч — pill segmented ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.bgElevated.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(children: [
                _TabBtn(
                    label: 'Дагагч',
                    selected: _followers,
                    onTap: () {
                      if (_followers) return;
                      setState(() => _followers = true);
                      _load();
                    }),
                _TabBtn(
                    label: 'Дагаж буй',
                    selected: !_followers,
                    onTap: () {
                      if (!_followers) return;
                      setState(() => _followers = false);
                      _load();
                    }),
              ]),
            ),
          ),
          // ── Жагсаалт ──
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    // Зөвхөн жагсаалт хоосон + анх ачаалж байх үед л бүтэн skeleton
    if (_loading && _people.isEmpty) return _skeleton();
    if (_error && _people.isEmpty) return _errorState();
    return RefreshIndicator(
      color: AppColors.neonCyan,
      backgroundColor: AppColors.bgElevated,
      onRefresh: _load,
      child: _people.isEmpty
          ? _emptyScrollable()
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: _people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) => _row(_people[i]),
            ),
    );
  }

  // Анхны ачаалалд — spinner-ийн оронд зөөлөн skeleton мөрүүд
  Widget _skeleton() => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, __) => const _RowSkeleton(),
      );

  // Ачаалал бүтэлгүйтсэн — хоосон төлөвөөс ялгаатай (дахин оролдох товчтой)
  Widget _errorState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 120),
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 12),
            Text('Ачаалж чадсангүй',
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: _load,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(999)),
                    child: Text('Дахин оролдох',
                        style: AppTextStyles.btn.copyWith(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ]),
        ],
      );

  // Хоосон төлөв — pull-to-refresh ажиллахын тулд scrollable
  Widget _emptyScrollable() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 120),
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _followers
                    ? Icons.group_outlined
                    : Icons.person_search_outlined,
                color: AppColors.textTertiary,
                size: 48),
            const SizedBox(height: 12),
            Text(
                _followers ? 'Дагагч алга байна' : 'Хэнийг ч дагаагүй байна',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textTertiary)),
          ]),
        ],
      );

  // Цэвэр template мөр — карт хүрээгүй: avatar 44 + нэр + pill товч
  Widget _row(Map<String, dynamic> p) {
    final id = p['id'] as String? ?? '';
    final username = p['username'] as String? ?? 'user';
    final fullName = p['full_name'] as String?;
    final avatar = p['avatar_url'] as String?;
    final verified = p['is_verified'] == true;
    final isMe = id == _me;
    final following = _iFollow.contains(id);
    final busy = _busy.contains(id);
    // AppAvatar initial-д зөвхөн эхний тэмдэгт (бүтэн нэр өгвөл дугуйнаас халина)
    final initial = username.isNotEmpty ? username[0] : '?';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => context.push('/creator/$id'),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          AppAvatar(imageUrl: avatar, initial: initial, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLg.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0)),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded,
                        color: AppColors.neonCyan, size: 15),
                  ],
                ]),
                if (fullName != null && fullName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: 10),
            _RowFollowBtn(
                following: following, busy: busy, onTap: () => _toggle(id)),
          ],
        ]),
      ),
      ),
    );
  }
}

// ── Glass дугуй буцах товч ──
class _GlassBackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackBtn({required this.onTap});

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
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                color: AppColors.textPrimary, size: 17),
          ),
        ),
      );
}

// ── Мөрийн skeleton (анхны ачаалалд) — цэвэр мөртэй ижил хэмжээс ──
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.bgSurface)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: 120,
                  decoration: BoxDecoration(color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 7),
                Container(height: 10, width: 80,
                  decoration: BoxDecoration(color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 96, height: 36,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(999))),
        ]),
      );
}

// ── Таб товч (pill segmented) ──
class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.accentStart.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMd.copyWith(
                    color:
                        selected ? Colors.white : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0)),
          ),
        ),
        ),
      );
}

// ── Мөрийн follow/unfollow товч — pill 96×36 ──
class _RowFollowBtn extends StatelessWidget {
  final bool following;
  final bool busy;
  final VoidCallback onTap;
  const _RowFollowBtn(
      {required this.following, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = !following;
    return MouseRegion(
      cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 96,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.bgSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: AppColors.hairline2),
          // Primary (Дагах) үед неон glow
          boxShadow: filled && !busy
              ? [
                  BoxShadow(
                    color: AppColors.accentStart.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: filled ? Colors.white : AppColors.textSecondary))
            : Text(following ? 'Дагасан' : 'Дагах',
                style: TextStyle(
                    color:
                        filled ? Colors.white : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
      ),
      ),
    );
  }
}
