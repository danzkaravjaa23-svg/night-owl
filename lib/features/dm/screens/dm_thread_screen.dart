import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/stickers.dart';

class DmThreadScreen extends StatefulWidget {
  final String threadId; // partner's user_id
  final String? replyNote; // note-д хариулж байгаа бол түүний текст
  const DmThreadScreen({super.key, required this.threadId, this.replyNote});
  @override State<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<DmThreadScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _msgs = [];
  Map<String, dynamic>? _partner;
  bool _loading = true;
  bool _sending = false;
  bool _showEmoji = false;
  String _emojiTab = 'emoji'; // 'emoji' | 'sticker'

  StreamSubscription? _sub;
  String? _pendingNote; // note-д хариулж байгаа эсэх

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    final n = widget.replyNote?.trim();
    if (n != null && n.isNotEmpty) _pendingNote = n;
    _loadPartner();
    _subscribe();
  }

  Future<void> _loadPartner() async {
    try {
      final p = await SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url')
          .eq('id', widget.threadId)
          .maybeSingle();
      if (mounted) setState(() => _partner = p);
    } catch (_) {}
  }

  void _subscribe() {
    final me = _myId;
    // conversation_id-р scope — бүх messages хүснэгтийг sub хийхгүй
    final cid = ([me, widget.threadId]..sort()).join('_');
    _sub = SupabaseService.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', cid)
        .order('created_at')
        .listen((data) {
          if (!mounted) return;
          final msgs = (data as List).cast<Map<String, dynamic>>().toList()
            ..sort((a, b) => (a['created_at'] as String? ?? '')
                .compareTo(b['created_at'] as String? ?? ''));
          setState(() { _msgs = msgs; _loading = false; });
          _scrollToBottom();
          _markRead(); // ирсэн мессежийг уншсан болгоно
        });
  }

  // Партнёроос ирсэн мессежийг "уншсан" болгож тэмдэглэнэ
  Future<void> _markRead() async {
    final me = _myId;
    if (me.isEmpty) return;
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', widget.threadId)
          .eq('receiver_id', me)
          .eq('is_read', false);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() => _sendText(_ctrl.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    final noteRef = _pendingNote; // эхний мессежид л note ишлэлийг хавсаргана
    setState(() { _sending = true; _pendingNote = null; });
    try {
      await SupabaseService.client.from('messages').insert({
        'sender_id':   _myId,
        'receiver_id': widget.threadId,
        'body':        text,
        'is_read':     false,
        if (noteRef != null) 'note_text': noteRef,
      });
    } catch (_) {
      // Илгээж чадаагүй — текст + note ишлэлийг сэргээж, мэдэгдэнэ
      if (mounted) {
        _ctrl.text = text;
        setState(() => _pendingNote = noteRef);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээж чадсангүй. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  void _onEmojiTap(String e) {
    if (_emojiTab == 'sticker' || _emojiTab == 'owl') {
      _sendText(e);            // sticker → шууд илгээх
    } else {
      _ctrl.text += e;         // emoji → текстэд нэмэх
      _ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _ctrl.text.length));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username  = _partner?['username'] as String? ?? 'User';
    final avatarUrl = _partner?['avatar_url'] as String?;
    final initial   = username.replaceAll('@','').isNotEmpty
        ? username.replaceAll('@','')[0].toUpperCase() : '?';
    // Өөрийн илгээсэн хамгийн сүүлийн мессеж (түүн дор "Үзсэн" харуулна)
    final lastMineIdx = _msgs.lastIndexWhere((m) => m['sender_id'] == _myId);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      appBar: _GlassAppBar(
        username: username,
        avatarUrl: avatarUrl,
        initial: initial,
        onBack: () => context.pop(),
        onTapPeer: () => context.push('/creator/${widget.threadId}'),
      ),
      body: Stack(children: [
        // ── Aurora glow backdrop ──
        const Positioned.fill(child: _AuroraBackdrop()),
        Column(children: [
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.accentStart, strokeWidth: 2))
            : _msgs.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppAvatar(imageUrl: avatarUrl, initial: initial,
                      size: 80, showRing: true, showOnlineDot: true),
                    const SizedBox(height: 16),
                    Text(username, style: AppTextStyles.h2),
                    const SizedBox(height: 8),
                    Text('Start a conversation!',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m    = _msgs[i];
                      final isMe = m['sender_id'] == _myId;
                      final text = m['body'] as String? ?? '';
                      final time = m['created_at'] as String?;
                      // Date separator
                      final showDate = i == 0 ||
                          !_sameDay(time, _msgs[i-1]['created_at'] as String?);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDate)
                            Center(child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _DateChip(label: _dateLabel(time)))),
                          _Bubble(text: text, isMe: isMe, time: _timeStr(time),
                            storyMediaUrl: m['story_media_url'] as String?,
                            noteText: m['note_text'] as String?),
                          // "Үзсэн" — зөвхөн өөрийн сүүлийн мессеж уншигдсан үед
                          if (isMe && i == lastMineIdx && (m['is_read'] == true))
                            Padding(
                              padding: const EdgeInsets.only(right: 4, bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(Icons.done_all_rounded,
                                    size: 14, color: AppColors.neonCyan),
                                  const SizedBox(width: 4),
                                  Text('Үзсэн', style: AppTextStyles.bodyXs.copyWith(
                                    color: AppColors.neonCyan,
                                    fontWeight: FontWeight.w600)),
                                ])),
                        ]);
                    })),

          // Input + emoji panel
          SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Note-д хариулж байгаа бол ишлэл харуулна
            if (_pendingNote != null)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline)),
                child: Row(children: [
                  Container(width: 3, height: 32,
                    decoration: BoxDecoration(color: AppColors.neonCyan,
                      borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$username-ийн note-д хариулж байна',
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.neonCyan, fontWeight: FontWeight.w600)),
                      Text(_pendingNote!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textSecondary)),
                    ])),
                  GestureDetector(
                    onTap: () => setState(() => _pendingNote = null),
                    child: const Icon(Icons.close, size: 18,
                      color: AppColors.textTertiary)),
                ]),
              ),
            // ── Sticky glass input bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: AppColors.hairline2)),
                    child: Row(children: [
                      // '+' attach (visual) doubles as emoji toggle affordance
                      IconButton(
                        onPressed: () => setState(() => _showEmoji = !_showEmoji),
                        icon: Icon(
                          _showEmoji
                              ? Icons.keyboard_outlined
                              : Icons.add_circle_outline_rounded,
                          color: _showEmoji
                              ? AppColors.neonCyan
                              : AppColors.neonCyan)),
                      Expanded(child: TextField(
                        controller: _ctrl,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textPrimary),
                        textInputAction: TextInputAction.send,
                        cursorColor: AppColors.neonCyan,
                        onTap: () { if (_showEmoji) setState(() => _showEmoji = false); },
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Мессеж бичих…',
                          hintStyle: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.textTertiary),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(color: AppColors.hairline)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: AppColors.neonCyan, width: 1.5)),
                          fillColor: AppColors.bgSurface.withValues(alpha: 0.7),
                          filled: true))),
                      const SizedBox(width: 6),
                      // emoji / mic affordance (visual → opens emoji panel)
                      IconButton(
                        onPressed: () => setState(() => _showEmoji = !_showEmoji),
                        icon: const Icon(Icons.emoji_emotions_outlined,
                          size: 22, color: AppColors.textSecondary)),
                      const SizedBox(width: 2),
                      // SEND — gradient circle wired to existing handler
                      GestureDetector(
                        onTap: _send,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentEnd.withValues(alpha: 0.45),
                                blurRadius: 18, offset: const Offset(0, 8)),
                            ]),
                          child: _sending
                            ? const Padding(padding: EdgeInsets.all(13),
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded,
                                color: Colors.white, size: 20))),
                    ]),
                  ),
                ),
              ),
            ),
            if (_showEmoji) _buildEmojiPanel(),
          ])),
        ]),
      ]),
    );
  }

  bool _sameDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.parse(a); final db = DateTime.parse(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dateLabel(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso);
    final now = DateTime.now();
    if (_sameDay(iso, now.toIso8601String())) return 'Өнөөдөр';
    if (_sameDay(iso, now.subtract(const Duration(days:1)).toIso8601String()))
      return 'Өчигдөр';
    return '${d.month}/${d.day}';
  }

  String _timeStr(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildEmojiPanel() {
    final isSticker = _emojiTab == 'sticker';
    final isOwl     = _emojiTab == 'owl';
    final items     = isSticker ? _kStickers : _kEmojis;
    return Container(
      height: 240,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Row(children: [
          _emojiTabBtn('emoji',   'Emoji'),
          _emojiTabBtn('sticker', 'Sticker'),
          _emojiTabBtn('owl',     '🦉 Owl'),
        ]),
        const Divider(height: 1, color: AppColors.hairline),
        Expanded(child: isOwl
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in kOwlStickers)
                  GestureDetector(
                    onTap: () => _onEmojiTap(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(16)),
                      child: Text(s, style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                  ),
              ]))
          : GridView.count(
              crossAxisCount: isSticker ? 5 : 8,
              padding: const EdgeInsets.all(8),
              children: [
                for (final e in items)
                  GestureDetector(
                    onTap: () => _onEmojiTap(e),
                    behavior: HitTestBehavior.opaque,
                    child: Center(child: Text(e,
                      style: TextStyle(fontSize: isSticker ? 40 : 26))),
                  ),
              ],
            )),
      ]),
    );
  }

  Widget _emojiTabBtn(String key, String label) {
    final active = _emojiTab == key;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _emojiTab = key),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: active ? AppColors.neonCyan : Colors.transparent, width: 2))),
        child: Center(child: Text(label, style: AppTextStyles.bodyMd.copyWith(
          color: active ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
      )));
  }
}

// ── Glass app bar (chevron back · neon-ring avatar w/ live dot · name + 'онлайн' · phone/video/more) ──
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String username;
  final String? avatarUrl;
  final String initial;
  final VoidCallback onBack;
  final VoidCallback onTapPeer;
  const _GlassAppBar({
    required this.username,
    required this.avatarUrl,
    required this.initial,
    required this.onBack,
    required this.onTapPeer,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: EdgeInsets.fromLTRB(12, topPad + 6, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.7),
            border: const Border(
              bottom: BorderSide(color: AppColors.hairline2)),
          ),
          child: Row(children: [
            // round glass back button
            _GlassCircleButton(
              icon: Icons.chevron_left_rounded,
              iconSize: 24,
              onTap: onBack,
            ),
            const SizedBox(width: 10),
            // avatar in neon ring + lime online dot
            GestureDetector(
              onTap: onTapPeer,
              child: AppAvatar(
                imageUrl: avatarUrl, initial: initial,
                size: 42, showRing: true, showOnlineDot: true),
            ),
            const SizedBox(width: 10),
            // name + online sub
            Expanded(child: GestureDetector(
              onTap: onTapPeer,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(username,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h2),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.lime, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('онлайн', style: AppTextStyles.bodyXs.copyWith(
                      color: AppColors.lime, fontWeight: FontWeight.w600)),
                  ]),
                ]),
            )),
            // right glass round buttons (visual)
            const _GlassCircleButton(icon: Icons.call, iconSize: 18),
            const SizedBox(width: 8),
            const _GlassCircleButton(icon: Icons.videocam_outlined, iconSize: 20),
            const SizedBox(width: 8),
            const _GlassCircleButton(icon: Icons.more_vert, iconSize: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Reusable glass round icon button ──
class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback? onTap;
  const _GlassCircleButton({
    required this.icon, this.iconSize = 20, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurface.withValues(alpha: 0.6),
          border: Border.all(color: AppColors.hairline2)),
        child: Icon(icon, size: iconSize, color: AppColors.textPrimary),
      ),
    );
  }
}

// ── Aurora glow backdrop (radial cyan/magenta wash on void) ──
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bgBase),
      child: Stack(children: [
        Positioned(
          top: -40, right: -30,
          child: _glow(220, AppColors.accentPurple.withValues(alpha: 0.18))),
        Positioned(
          bottom: -60, left: -40,
          child: _glow(240, AppColors.neonCyan.withValues(alpha: 0.10))),
      ]),
    );
  }

  Widget _glow(double size, Color c) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [c, Colors.transparent]),
    ),
  );
}

// ── Centered glass date-divider chip ──
class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline)),
          child: Text(label, style: AppTextStyles.labelSm.copyWith(
            color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

// Эмодзи / стикер жагсаалт (UB шөнийн амьдралын сэдэвт тохируулсан)
const _kEmojis = [
  '😀','😁','😂','🤣','😊','😍','😘','😎','🤩','🥳','😜','😏',
  '😢','😭','😡','😴','🤔','😅','🙄','😱','🥰','😋','🤤','🤗',
  '👍','👎','👏','🙏','💪','🙌','🤙','✌️','👌','🤝','🫶','👀',
  '🔥','✨','🎉','💯','❤️','🧡','💛','💚','💙','💜','🖤','💔',
  '🍻','🍺','🍷','🍸','🍹','🥂','🍾','🎶','🎵','🎤','🎧','🎸',
  '🕺','💃','🌃','🌙','⭐','🎂','🎁','📸','💋','💎','🚬','🥃',
];
const _kStickers = [
  '🎉','🔥','❤️','😂','👍','🥳','🍻','🌃','🎶','💃',
  '🕺','💯','😍','🙌','✨','😎','💋','🥂','🤩','🫶',
];

// Зөвхөн эмодзиос бүрдсэн богино мессежийг том (sticker) хэлбэрээр харуулна
bool _isEmojiOnly(String s) {
  final t = s.trim();
  if (t.isEmpty || t.runes.length > 8) return false;
  return !RegExp(r'[A-Za-z0-9]').hasMatch(t);
}

class _Bubble extends StatelessWidget {
  final String text, time;
  final bool isMe;
  final String? storyMediaUrl;
  final String? noteText;
  const _Bubble({required this.text, required this.isMe, required this.time,
    this.storyMediaUrl, this.noteText});

  // Тэдний (партнёрын) шилэн bubble — translucent glass
  BoxDecoration get _themGlass => BoxDecoration(
    color: AppColors.bgElevated.withValues(alpha: 0.85),
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(22), topRight: Radius.circular(22),
      bottomLeft: Radius.circular(7), bottomRight: Radius.circular(22)),
    border: Border.all(color: AppColors.hairline),
  );

  // Миний bubble — magenta→purple gradient + neon glow
  BoxDecoration get _meGrad => BoxDecoration(
    gradient: AppColors.accentGradient,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(22), topRight: Radius.circular(22),
      bottomLeft: Radius.circular(22), bottomRight: Radius.circular(7)),
    boxShadow: [
      BoxShadow(
        color: AppColors.accentEnd.withValues(alpha: 0.35),
        blurRadius: 22, offset: const Offset(0, 10)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // 📝 Note-д хариулсан → note ишлэл + хариу bubble
    if (noteText != null && noteText!.trim().isNotEmpty) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(isMe ? 'Note-д хариулсан' : 'Таны note-д хариулсан',
                style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
              const SizedBox(height: 3),
              // Note ишлэл
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  border: const Border(left: BorderSide(
                    color: AppColors.neonCyan, width: 3))),
                child: Text(noteText!, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: isMe ? _meGrad : _themGlass,
                child: Text(text, style: AppTextStyles.bodyMd.copyWith(
                  color: isMe ? Colors.white : AppColors.textPrimary)),
              ),
              const SizedBox(height: 3),
              Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // 📷 Story-д хариулсан → story thumbnail + тэмдэг + хариу bubble
    if (storyMediaUrl != null) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 30, height: 42,
                    child: Image.network(storyMediaUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.bgSurface,
                        child: const Icon(Icons.auto_stories,
                            size: 16, color: AppColors.textTertiary)))),
                ),
                const SizedBox(width: 6),
                Text(isMe ? 'Story-д хариулсан' : 'Таны story-д хариулсан',
                  style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
              ]),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: (isMe ? _meGrad : _themGlass).copyWith(
                  border: Border(left: BorderSide(
                    color: isMe ? Colors.white54 : AppColors.neonCyan, width: 3))),
                child: Text(text, style: AppTextStyles.bodyMd.copyWith(
                  color: isMe ? Colors.white : AppColors.textPrimary)),
              ),
              const SizedBox(height: 3),
              Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // 🦉 Owl sticker → онцгой gradient pill
    if (isOwlSticker(text)) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentEnd.withValues(alpha: 0.4),
                      blurRadius: 20, offset: const Offset(0, 8)),
                  ]),
                child: Text(text, style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 3),
              Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // Sticker / emoji-only → дэвсгэргүй, том хэмжээгээр
    if (_isEmojiOnly(text)) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 46)),
              const SizedBox(height: 2),
              Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // Энгийн текст bubble
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
              decoration: isMe ? _meGrad : _themGlass,
              child: Text(text, style: AppTextStyles.bodyMd.copyWith(
                color: isMe ? Colors.white : AppColors.textPrimary)),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: EdgeInsets.only(left: isMe ? 0 : 6, right: isMe ? 6 : 0),
              child: Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ),
          ])));
  }
}
