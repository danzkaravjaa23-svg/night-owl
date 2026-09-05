import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/block_report_service.dart';

/// Админ — хэрэглэгч хайх, хориглох / сэргээх
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String? _busyId; // хориглох/сэргээх ажиллаж буй хэрэглэгчийн id
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load(''); // эхэнд сүүлийн хэрэглэгчид
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q));
  }

  Future<void> _load(String q) async {
    // Жагсаалт байхад spinner-ээр солихгүй — хайлт хийх зуур хуучин үр дүн харагдана
    setState(() => _loading = true);
    try {
      var query = SupabaseService.client
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_banned, is_admin');
      if (q.trim().isNotEmpty) {
        // username + full_name хоёуланд нь хайна (.or filter-т таслал/хаалт эвдэрдэг тул цэвэрлэнэ)
        final safe = q.trim().replaceAll(RegExp(r'[,()]'), ' ');
        query = query.or('username.ilike.%$safe%,full_name.ilike.%$safe%');
      }
      final data = await query.order('created_at', ascending: false).limit(50);
      // Race guard — хариу ирэхэд хайлтын утга өөрчлөгдсөн бол хаяна
      if (!mounted || q.trim() != _ctrl.text.trim()) return;
      setState(() {
        _users = (data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Алдаа гарлаа — дахин оролдоно уу'),
        backgroundColor: AppColors.error));
    }
  }

  Future<void> _toggleBan(Map<String, dynamic> u) async {
    final banned = u['is_banned'] == true;
    final uname = (u['username'] as String? ?? 'user').replaceAll('@', '');
    // Хориглох нь эргэлт буцалтгүй хүнд үйлдэл — баталгаажуулна
    if (!banned) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgElevated,
          title: Text('@$uname-г хориглох уу?', style: AppTextStyles.h2),
          content: Text('Энэ хэрэглэгч аппд нэвтрэх боломжгүй болно.',
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary))),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Хориглох', style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.error, fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busyId = u['id'] as String);
    final err = await BlockReportService.setBanned(u['id'] as String, !banned);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (err == null) {
      setState(() => u['is_banned'] = !banned);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!banned ? 'Хориглолоо' : 'Сэргээлээ')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Алдаа: $err'), backgroundColor: AppColors.error));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final isAdmin = profileAsync.value?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          // Deep link-ээр орж ирсэн үед pop хийх юмгүй — админ панел руу
          onPressed: () {
            if (context.canPop()) { context.pop(); } else { context.go('/admin'); }
          },
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Хэрэглэгчид', style: AppTextStyles.h2),
      ),
      body: profileAsync.isLoading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : !isAdmin
              // URL-ээр шууд орж ирэхээс хамгаална — зөвхөн админ
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 56, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  Text('Хандах эрхгүй', style: AppTextStyles.h2),
                  const SizedBox(height: 6),
                  Text('Энэ хэсэг зөвхөн админд зориулагдсан.',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                ]))
              : Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: AppColors.textTertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Хэрэглэгч хайх (нэр, @username)...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.zero))),
              if (_loading) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accentStart)),
                const SizedBox(width: 12),
              ],
            ]),
          ),
        ),
        Expanded(
          child: _loading && _users.isEmpty
              ? const _SkeletonRows()
              : _users.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.person_search_rounded, size: 44,
                        color: AppColors.textTertiary),
                      const SizedBox(height: 10),
                      Text('Хэрэглэгч олдсонгүй',
                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary)),
                    ]))
                  // Хайлт явж байхад хуучин жагсаалтыг бүдэгрүүлж үлдээнэ
                  : AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _loading ? 0.55 : 1,
                      child: ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (_, i) => _row(_users[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> u) {
    final uname = (u['username'] as String? ?? 'user').replaceAll('@', '');
    final banned = u['is_banned'] == true;
    final isAdmin = u['is_admin'] == true;
    final busy = _busyId == u['id'];
    return ListTile(
      onTap: () => context.push('/creator/${u['id']}'),
      leading: AppAvatar(
        imageUrl: u['avatar_url'] as String?,
        initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?',
        size: 40),
      title: Row(children: [
        Flexible(child: Text('@$uname', style: AppTextStyles.labelMd,
            overflow: TextOverflow.ellipsis)),
        if (isAdmin) ...[
          const SizedBox(width: 6),
          const Icon(Icons.shield, color: AppColors.accentStart, size: 14),
        ],
        if (banned) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text('Хориглосон', style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.error))),
        ],
      ]),
      subtitle: (u['full_name'] as String?)?.isNotEmpty == true
          ? Text(u['full_name'] as String, style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textSecondary))
          : null,
      trailing: isAdmin
          ? null // админыг хориглохгүй
          : TextButton(
              onPressed: busy ? null : () => _toggleBan(u),
              child: busy
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.textSecondary))
                  : Text(banned ? 'Сэргээх' : 'Хориглох',
                      style: AppTextStyles.bodyMd.copyWith(
                          color: banned ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w600))),
    );
  }
}

// ─── Эхний ачаалалтын skeleton мөрүүд ───
class _SkeletonRows extends StatefulWidget {
  const _SkeletonRows();
  @override
  State<_SkeletonRows> createState() => _SkeletonRowsState();
}

class _SkeletonRowsState extends State<_SkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
    lowerBound: 0.4, upperBound: 0.9)..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.bgElevated)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 12, width: 140,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 7),
              Container(height: 10, width: 90,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(5))),
            ])),
        ]),
      ),
    ),
  );
}
