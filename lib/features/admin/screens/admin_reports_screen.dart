import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/services/block_report_service.dart';

/// Админ — мэдээлэгдсэн контентыг хянах дэлгэц
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _busy; // '<reportId>:<action>' — тухайн картын аль товч ажиллаж буйг заана

  static const _reasonLabels = {
    'spam': 'Спам', 'harassment': 'Дарамт', 'nudity': 'Бэлгийн агуулга',
    'violence': 'Хүчирхийлэл', 'hate': 'Үзэн ядалт', 'other': 'Бусад',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Жагсаалт байхад spinner-ээр бүрхэхгүй — RefreshIndicator өөрөө харуулна
    if (_reports.isEmpty) setState(() => _loading = true);
    try {
      final data = await SupabaseService.client
          .from('reports')
          .select('*, reporter:profiles!reporter_id(username, avatar_url)')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _reports = (data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : null));
  }

  // Устгах/хориглох мэт эргэлт буцалтгүй үйлдэлд баталгаажуулах dialog
  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text(title, style: AppTextStyles.h2),
        content: Text(body,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action, style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _resolve(String reportId) async {
    setState(() => _busy = '$reportId:resolve');
    try {
      await SupabaseService.client
          .from('reports').update({'status': 'resolved'}).eq('id', reportId);
      if (!mounted) return;
      // Амжилттай үед л жагсаалтаас хасна
      setState(() => _reports.removeWhere((r) => r['id'] == reportId));
    } catch (_) {
      _snack('Алдаа гарлаа — дахин оролдоно уу', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _banUser(String userId, String reportId) async {
    final okConfirm = await _confirm('Хэрэглэгчийг хориглох уу?',
        'Энэ хэрэглэгч аппд нэвтрэх боломжгүй болно.', 'Хориглох');
    if (!okConfirm) return;
    if (!mounted) return;
    setState(() => _busy = '$reportId:ban');
    final err = await BlockReportService.setBanned(userId, true);
    if (err == null) {
      try {
        await SupabaseService.client
            .from('reports').update({'status': 'resolved'}).eq('id', reportId);
      } catch (_) {} // ban амжилттай — resolve бүтэлгүйтвэл карт үлдэнэ, refresh-ээр дахин гарна
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      // Ban амжилтгүй бол картыг хэвээр үлдээнэ
      if (err == null) _reports.removeWhere((r) => r['id'] == reportId);
    });
    _snack(err == null ? 'Хэрэглэгч хориглогдлоо' : 'Алдаа: $err', error: err != null);
  }

  Future<void> _deletePost(String postId, String reportId) async {
    final okConfirm = await _confirm('Постыг устгах уу?',
        'Пост бүр мөсөн устана. Буцаах боломжгүй.', 'Устгах');
    if (!okConfirm) return;
    if (!mounted) return;
    setState(() => _busy = '$reportId:delete');
    var ok = false;
    try {
      // posts RLS — админ устгаж болно. Storage trigger файлыг цэвэрлэнэ.
      await SupabaseService.client.from('posts').delete().eq('id', postId);
      ok = true;
      await SupabaseService.client
          .from('reports').update({'status': 'resolved'}).eq('id', reportId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (ok) _reports.removeWhere((r) => r['id'] == reportId);
    });
    _snack(ok ? 'Пост устгагдлаа' : 'Алдаа гарлаа — пост устгагдсангүй', error: !ok);
  }

  void _openTarget(String type, String id) {
    switch (type) {
      case 'post':  context.push('/post/$id'); break;
      case 'user':  context.push('/creator/$id'); break;
      case 'venue': context.push('/venue/reviews/$id'); break;
    }
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
        title: Text('Мэдээллүүд', style: AppTextStyles.h2),
        actions: [
          if (isAdmin)
            IconButton(onPressed: _load,
              icon: const Icon(Icons.refresh, color: AppColors.textPrimary)),
        ],
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
              : _loading
                  ? const _SkeletonCards()
                  : _reports.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('✅', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('Хүлээгдэж буй мэдээлэл алга',
                              style: AppTextStyles.bodyMd.copyWith(
                                  color: AppColors.textSecondary)),
                        ]))
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accentStart,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _reports.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _card(_reports[i]),
                          ),
                        ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final type = r['target_type'] as String? ?? '';
    final targetId = r['target_id'] as String? ?? '';
    final reportId = r['id'] as String;
    final reason = r['reason'] as String? ?? '';
    final reporter = (r['reporter'] as Map<String, dynamic>?)?['username'] as String?;
    final isPost = type == 'post';
    final isUser = type == 'user';
    final cardBusy = _busy != null && _busy!.startsWith('$reportId:');

    Widget btnChild(String action, IconData icon, String label) =>
        _busy == '$reportId:$action'
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14), const SizedBox(width: 5), Text(label)]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
            child: Text(_reasonLabels[reason] ?? reason,
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text(type.toUpperCase(), style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textSecondary)),
          const Spacer(),
          if (reporter != null)
            Text('@$reporter', style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textTertiary)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: cardBusy ? null : () => _openTarget(type, targetId),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Үзэх'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairline2),
              minimumSize: const Size(0, 40)),
          )),
          const SizedBox(width: 8),
          if (isPost)
            Expanded(child: ElevatedButton(
              onPressed: cardBusy ? null : () => _deletePost(targetId, reportId),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40)),
              child: btnChild('delete', Icons.delete_outline, 'Устгах'),
            )),
          if (isPost) const SizedBox(width: 8),
          if (isUser)
            Expanded(child: ElevatedButton(
              onPressed: cardBusy ? null : () => _banUser(targetId, reportId),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40)),
              child: btnChild('ban', Icons.gavel, 'Хориглох'),
            )),
          if (isUser) const SizedBox(width: 8),
          Expanded(child: TextButton(
            onPressed: cardBusy ? null : () => _resolve(reportId),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 40)),
            child: _busy == '$reportId:resolve'
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textSecondary))
              : const Text('Шийдсэн'),
          )),
        ]),
      ]),
    );
  }
}

// ─── Эхний ачаалалтын skeleton картууд ───
class _SkeletonCards extends StatefulWidget {
  const _SkeletonCards();
  @override
  State<_SkeletonCards> createState() => _SkeletonCardsState();
}

class _SkeletonCardsState extends State<_SkeletonCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
    lowerBound: 0.4, upperBound: 0.9)..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 108,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
