import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';
import '../providers/follow_provider.dart';

/// Дагагч / Дагаж буй хүмүүсийн жагсаалт — таб солих боломжтой.
/// Мөр бүр дээр follow/unfollow товч (өөрөөс бусад хүнд).
class FollowListScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool showFollowers; // true=Дагагч, false=Дагаж буй
  const FollowListScreen({
    super.key,
    required this.userId,
    this.showFollowers = true,
  });

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  late bool _followers = widget.showFollowers;
  bool _loading = true;
  bool _error = false; // ачаалал бүтэлгүйтсэн эсэх (хоосон төлөвөөс ялгах)
  List<Map<String, dynamic>> _people = const [];
  Set<String> _iFollow = {};
  Set<String> _requested = {};
  final _busy = <String>{}; // товч дарж байгаа id-ууд
  int _reqToken = 0; // таб солих race-аас сэргийлэх токен

  String? get _me => SupabaseService.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FollowListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.showFollowers != widget.showFollowers) {
      _followers = widget.showFollowers;
      _resetList();
      _load();
    }
  }

  void _resetList() {
    _people = const [];
    _iFollow = {};
    _requested = {};
    _loading = true;
    _error = false;
  }

  void _selectTab(bool followers) {
    if (_followers == followers) return;
    setState(() {
      _followers = followers;
      _resetList();
    });
    _load();
  }

  Future<Set<String>> _outgoingRequests(String? me) async {
    if (me == null) return {};
    final rows = await SupabaseService.client
        .from('follow_requests')
        .select('target_id')
        .eq('requester_id', me);
    return {for (final row in rows) row['target_id'] as String};
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)));

  Future<void> _load() async {
    // Хүсэлт бүрт токен — сүүлчийнх нь л _people-д бичнэ (таб солих гулгалтаас сэргийлнэ)
    final token = ++_reqToken;
    final me = _me;
    final wantFollowers = _followers;
    // Анхны/хоосон үед л бүтэн spinner; refresh үед хуучин мөрүүд харагдана
    setState(() {
      _error = false;
      if (_people.isEmpty) _loading = true;
    });
    try {
      final results = await Future.wait([
        wantFollowers
            ? FollowService.getFollowers(widget.userId)
            : FollowService.getFollowing(widget.userId),
        FollowService.myFollowingIds(),
        _outgoingRequests(me),
      ]);
      if (!mounted || token != _reqToken || me != _me) return;
      setState(() {
        _people = results[0] as List<Map<String, dynamic>>;
        _iFollow = results[1] as Set<String>;
        _requested = results[2] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken || me != _me) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _toggle(String id) async {
    final me = _me;
    if (me == null || id.isEmpty || id == me || _busy.contains(id)) return;
    final wasFollowing = _iFollow.contains(id);
    final wasRequested = _requested.contains(id);
    // A refresh started before this mutation must not replace the new status.
    ++_reqToken;
    setState(() {
      _busy.add(id);
      _loading = false;
    });
    try {
      final status =
          await DiscoveryService().follow(id, !wasFollowing && !wasRequested);
      if (!mounted || me != _me) return;
      setState(() {
        status == 'following' ? _iFollow.add(id) : _iFollow.remove(id);
        status == 'requested' ? _requested.add(id) : _requested.remove(id);
      });
      ref.read(socialVersionProvider.notifier).state++;
      ref.invalidate(followProvider(id));
      ref.invalidate(isFollowingProvider(id));
      ref.invalidate(followCountsProvider(id));
      ref.invalidate(followCountsProvider(me));
      ref.invalidate(currentProfileProvider);
      // Reload the currently selected tab after the server change, including
      // when the user switched tabs while the mutation was in flight.
      _load();
    } catch (_) {
      if (mounted && me == _me) {
        _toast('Үйлдэл амжилтгүй, дахин оролдоно уу');
      }
    } finally {
      if (mounted && me == _me) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionUserIdProvider, (_, __) {
      setState(() {
        _resetList();
        _busy.clear();
      });
      _load();
    });
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(children: [
          // ── Дээд бар — glass буцах товч + h2 гарчиг ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(children: [
              _GlassBackBtn(
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/profile'),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('Хүмүүс', style: AppTextStyles.h2)),
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
                    onTap: () => _selectTab(true)),
                _TabBtn(
                    label: 'Дагаж буй',
                    selected: !_followers,
                    onTap: () => _selectTab(false)),
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
              itemCount: _people.length + (_error ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) => _error && i == 0
                  ? _refreshError()
                  : _row(_people[i - (_error ? 1 : 0)]),
            ),
    );
  }

  Widget _refreshError() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Жагсаалтыг шинэчилж чадсангүй. Өмнөх мэдээллийг харуулж байна.',
              style: AppTextStyles.bodySm),
          TextButton(onPressed: _load, child: const Text('Дахин оролдох')),
        ]),
      );

  // Анхны ачаалалд — spinner-ийн оронд зөөлөн skeleton мөрүүд
  Widget _skeleton() => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) => i == 0
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: OwlLoading(
                    size: 40,
                    message: _followers
                        ? 'Дагагчдыг ачаалж байна'
                        : 'Дагаж буй хүмүүсийг ачаалж байна'))
            : const _RowSkeleton(),
      );

  // Ачаалал бүтэлгүйтсэн — хоосон төлөвөөс ялгаатай (дахин оролдох товчтой)
  Widget _errorState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined,
                color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 12),
            Text('Ачаалж чадсангүй',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Center(
              child: FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentStart,
                      minimumSize: const Size(0, 48)),
                  child: const Text('Дахин оролдох')),
            ),
          ]),
        ],
      );

  // Хоосон төлөв — pull-to-refresh ажиллахын тулд scrollable
  Widget _emptyScrollable() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _followers
                    ? Icons.group_outlined
                    : Icons.person_search_outlined,
                color: AppColors.textTertiary,
                size: 48),
            const SizedBox(height: 12),
            Text(_followers ? 'Дагагч алга байна' : 'Хэнийг ч дагаагүй байна',
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

    final button = _RowFollowBtn(
      following: following,
      requested: _requested.contains(id),
      busy: busy,
      onTap: () => _toggle(id),
    );
    final identity = Row(children: [
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
                        letterSpacing: 0))),
            if (verified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified_rounded,
                  semanticLabel: 'Баталгаажсан',
                  color: AppColors.neonCyan,
                  size: 15),
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
      )),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 360 &&
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final profileLink = InkWell(
          onTap: id.isEmpty ? null : () => context.push('/creator/$id'),
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
              button: true,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: identity)),
        );
        final canFollow = !isMe && _me != null && id.isNotEmpty;
        if (stacked) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                profileLink,
                if (canFollow) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: button),
                ],
              ]);
        }
        return Row(children: [
          Expanded(child: profileLink),
          if (canFollow) ...[const SizedBox(width: 10), button],
        ]);
      }),
    );
  }
}

// ── Glass дугуй буцах товч ──
class _GlassBackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Буцах',
        onPressed: onTap,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: AppColors.bgElevated.withValues(alpha: 0.72),
          side: BorderSide(color: AppColors.hairline2),
        ),
        icon: Icon(Icons.arrow_back_ios_new,
            color: AppColors.textPrimary, size: 17),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.bgSurface)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 7),
                Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
              width: 96,
              height: 36,
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
        child: MergeSemantics(
            child: Semantics(
          selected: selected,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.exit),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(999),
            ),
            child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                foregroundColor:
                    selected ? Colors.white : AppColors.textSecondary,
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd.copyWith(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0)),
            ),
          ),
        )),
      );
}

class _RowFollowBtn extends StatelessWidget {
  final bool following;
  final bool requested;
  final bool busy;
  final VoidCallback onTap;
  const _RowFollowBtn(
      {required this.following,
      required this.requested,
      required this.busy,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = !following && !requested;
    final label = requested
        ? 'Хүсэлттэй'
        : following
            ? 'Дагасан'
            : 'Дагах';
    return Semantics(
      label: busy ? 'Хүлээнэ үү' : null,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.exit),
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.bgSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: AppColors.hairline2),
        ),
        child: TextButton(
          onPressed: busy ? null : onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(96, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            foregroundColor: filled ? Colors.white : AppColors.textSecondary,
          ),
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: filled ? Colors.white : AppColors.textSecondary))
              : Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
