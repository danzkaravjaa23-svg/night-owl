import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../profile/services/block_report_service.dart';

/// Админ — мэдээлэгдсэн контентыг хянах дэлгэц
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

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
    setState(() => _loading = true);
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

  Future<void> _resolve(String reportId) async {
    try {
      await SupabaseService.client
          .from('reports').update({'status': 'resolved'}).eq('id', reportId);
    } catch (_) {}
    setState(() => _reports.removeWhere((r) => r['id'] == reportId));
  }

  Future<void> _banUser(String userId, String reportId) async {
    final err = await BlockReportService.setBanned(userId, true);
    if (err == null) {
      await SupabaseService.client
          .from('reports').update({'status': 'resolved'}).eq('id', reportId);
    }
    if (mounted) {
      setState(() => _reports.removeWhere((r) => r['id'] == reportId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Хэрэглэгч хориглогдлоо' : 'Алдаа: $err')));
    }
  }

  Future<void> _deletePost(String postId, String reportId) async {
    try {
      // posts RLS — админ устгаж болно. Storage trigger файлыг цэвэрлэнэ.
      await SupabaseService.client.from('posts').delete().eq('id', postId);
      await SupabaseService.client
          .from('reports').update({'status': 'resolved'}).eq('id', reportId);
    } catch (_) {}
    if (mounted) {
      setState(() => _reports.removeWhere((r) => r['id'] == reportId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост устгагдлаа')));
    }
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
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Мэдээллүүд', style: AppTextStyles.h2),
        actions: [
          IconButton(onPressed: _load,
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart))
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
    final reason = r['reason'] as String? ?? '';
    final reporter = (r['reporter'] as Map<String, dynamic>?)?['username'] as String?;
    final isPost = type == 'post';
    final isUser = type == 'user';

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
            onPressed: () => _openTarget(type, targetId),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Үзэх'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.hairline2),
              minimumSize: const Size(0, 40)),
          )),
          const SizedBox(width: 8),
          if (isPost)
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _deletePost(targetId, r['id'] as String),
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Устгах'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40)),
            )),
          if (isPost) const SizedBox(width: 8),
          if (isUser)
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _banUser(targetId, r['id'] as String),
              icon: const Icon(Icons.gavel, size: 14),
              label: const Text('Хориглох'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40)),
            )),
          if (isUser) const SizedBox(width: 8),
          Expanded(child: TextButton(
            onPressed: () => _resolve(r['id'] as String),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 40)),
            child: const Text('Шийдсэн'),
          )),
        ]),
      ]),
    );
  }
}
