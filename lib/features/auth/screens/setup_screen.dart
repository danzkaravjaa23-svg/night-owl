import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_compress.dart';
import '../../../core/utils/validators.dart';
import '../widgets/auth_ui.dart';

/// A saved profile name wins over the one-time name supplied by Apple.
@visibleForTesting
String resolveSetupName({
  Map<String, dynamic>? profile,
  Map<String, dynamic>? metadata,
}) {
  for (final value in [
    profile?['full_name'],
    profile?['name'],
    metadata?['full_name']
  ]) {
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return '';
}

class SetupScreen extends StatefulWidget {
  /// Профайлаас "Профайл засах" дарж нээсэн — хадгалсны дараа буцна
  /// (шинэ хэрэглэгчийн анхны setup бол false — хадгалаад Нүүр рүү).
  final bool forceEdit;
  const SetupScreen({super.key, this.forceEdit = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  // Гар дээрх "Дараах" товч хэрэглэгчийн нэрээс танилцуулга руу шилжүүлнэ
  final _bioFocus = FocusNode();
  Uint8List? _avatarBytes;
  String? _avatarUrl; // одоо байгаа аватар (edit mode-д харуулна)
  List<String> _interests = [];
  bool _loading = false;
  bool _isEditMode = false;
  bool _profileLoading = true; // профайл ачаалж байх үеийн skeleton
  bool _loadFailed = false; // ачаалж чадаагүй — retry харуулна
  String? _error;
  late final String? _setupUserId;
  StreamSubscription<AuthState>? _authSub;
  bool _profileLoaded = false;
  bool _hasSavedName = false;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.forceEdit;
    _setupUserId = SupabaseService.currentUser?.id;
    // Native Apple name metadata may arrive after signedIn opened this route.
    _authSub = SupabaseService.authStream.listen((state) {
      _fillMetadataName(state.session?.user);
    });
    _loadExistingProfile();
  }

  bool _isSetupUser(User? user) =>
      _setupUserId != null &&
      user?.id == _setupUserId &&
      SupabaseService.currentUser?.id == _setupUserId;

  void _fillMetadataName(User? user) {
    if (!mounted ||
        !_isSetupUser(user) ||
        !_profileLoaded ||
        _loading ||
        _nameEdited ||
        _hasSavedName ||
        _nameCtrl.text.trim().isNotEmpty) {
      return;
    }
    final name = resolveSetupName(metadata: user?.userMetadata);
    if (name.isNotEmpty) _nameCtrl.text = name;
  }

  Future<void> _loadExistingProfile() async {
    final user = SupabaseService.currentUser;
    if (!_isSetupUser(user)) {
      setState(() => _profileLoading = false);
      return;
    }
    _profileLoaded = false;
    setState(() {
      _profileLoading = true;
      _loadFailed = false;
    });
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user!.id)
          .maybeSingle();
      if (!mounted || !_isSetupUser(user)) return;
      final savedName = resolveSetupName(profile: data);
      _hasSavedName = savedName.isNotEmpty;
      if (data != null) {
        final username = data['username'] as String? ?? '';
        setState(() {
          // setup_complete metadata = профайлаа дуусгасан → засах горим.
          // Байхгүй бол ШИНЭ хэрэглэгч → "үүсгэх" горим (буцах товчгүй).
          _isEditMode = widget.forceEdit ||
              Supabase.instance.client.auth.currentUser
                      ?.userMetadata?['setup_complete'] ==
                  true;
          _usernameCtrl.text = username;
          if (!_nameEdited && _hasSavedName) _nameCtrl.text = savedName;
          _bioCtrl.text = data['bio'] as String? ?? '';
          _avatarUrl = data['avatar_url'] as String?;
          _interests = List<String>.from(data['interests'] ?? []);
          _profileLoading = false;
        });
      } else {
        setState(() => _profileLoading = false);
      }
      _profileLoaded = true;
      // Use the latest currentUser: Apple may have updated metadata while
      // the profile request was still loading.
      _fillMetadataName(SupabaseService.currentUser);
    } catch (_) {
      // Чимээгүй унагаахгүй — edit mode-д хоосон формоор bio дарж
      // бичихээс сэргийлж, анхааруулга + retry харуулна
      if (mounted && _isSetupUser(user)) {
        setState(() {
          _profileLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  // Back (edit mode) — pop хийх юмгүй бол профайл руу
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.profile);
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: AppConstants.imageQuality,
      maxWidth: 400,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _avatarBytes = bytes);
  }

  void _toggleInterest(String tag) {
    setState(() {
      if (_interests.contains(tag)) {
        _interests.remove(tag);
      } else if (_interests.length < 6) {
        _interests.add(tag);
      }
    });
  }

  // Хэрэглэгчийн нэрийн шалгалт — талбарын доор шууд харагдана (TextFormField)
  String? _validateUsername(String? value) {
    return Validators.username(value);
  }

  Future<void> _save() async {
    // Enter дарж давхар илгээхээс сэргийлнэ
    if (_loading) return;
    // Хэрэглэгчийн нэрийн алдаа талбарын доор inline харагдана
    if (_formKey.currentState?.validate() != true) return;
    final username = _usernameCtrl.text.trim().toLowerCase();

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.authLanding);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String? avatarUrl;

      if (_avatarBytes != null) {
        final path =
            '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
            path, await compressToJpeg(_avatarBytes!, maxDim: 400),
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true));
        // Cache-buster — ижил URL дээр хуучин зураг cache-с гарахаас сэргийлнэ
        final publicUrl =
            Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
        avatarUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      }

      final updates = <String, dynamic>{
        'id': user.id,
        'username': username,
        'full_name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'interests': _interests,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await Supabase.instance.client.from('profiles').upsert(updates);

      // "Профайл дуусгасан" тэмдгийг auth metadata-д тавина — router AuthGate
      // үүгээр л шинэ/бүртгэлтэйг ялгадаг (presence/follow update нөлөөлөхгүй)
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(data: {'setup_complete': true}));
      authGate.refresh();
      if (!mounted) return;
      if (widget.forceEdit) {
        // Засах горим — ирсэн газраа буцна (профайл/тохиргоо)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Профайл хадгалагдлаа')));
        context.canPop() ? context.pop() : context.go(AppRoutes.profile);
      } else {
        context.go(AppRoutes.feed);
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == '23505'
          ? 'Энэ хэрэглэгчийн нэр аль хэдийн ашиглагдаж байна.'
          : 'Хадгалахад алдаа гарлаа. Дахин оролдоно уу.');
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = 'Хадгалахад алдаа гарлаа. Сүлжээгээ шалгана уу.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ── Futurist Nightscape aura — auth гэр бүлтэй ижил ──
          const AuthAura(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Дээд hero — гарчиг (edit mode-д back chip + h1) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isEditMode) ...[
                        Row(children: [
                          GlassBack(onTap: _back),
                          const SizedBox(width: 14),
                          Text('Профайл засах', style: AppTextStyles.h1),
                        ]),
                      ] else ...[
                        Text('Өөрийгөө', style: AppTextStyles.displayMd),
                        Text('танилцуул',
                            style: AppTextStyles.displayMd.copyWith(
                                fontStyle: FontStyle.italic,
                                foreground: Paint()
                                  ..shader = AppColors.accentGradient
                                      .createShader(
                                          const Rect.fromLTWH(0, 0, 200, 40)))),
                      ],
                      const SizedBox(height: 6),
                      Text('Зураг, хэрэглэгчийн нэр, сонирхлоо нэмээрэй',
                          style: AppTextStyles.bodyMd
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Шилэн bottom-sheet — форм / skeleton ──
                Expanded(
                  child: _GlassSheet(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child:
                          _profileLoading ? const _FormSkeleton() : _formView(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Цайвар дэвсгэр дээр amber текст уншигдахгүй тул бараан amber
  Color get _amberInk =>
      AppColors.isDarkMode ? AppColors.amber : const Color(0xFF8A5A00);

  Widget _formView() => SingleChildScrollView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Профайл ачаалж чадаагүй анхааруулга + retry
              if (_loadFailed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.wifi_off_rounded, color: _amberInk, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('Профайл ачаалж чадсангүй',
                            style: AppTextStyles.bodySm
                                .copyWith(color: _amberInk))),
                    TapScale(
                      onTap: _loadExistingProfile,
                      child: Text('Дахин оролдох',
                          style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.neonCyan, letterSpacing: 0)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // ── Avatar hero — 96, story-ring хүрээ + gradient edit badge ──
              Center(
                child: TapScale(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Story-ring gradient хүрээ
                      Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.storyRingGradient,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          // Cutout — цайвар горимд sheet-ийн цагаан өнгөтэй нийлнэ
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.isDarkMode
                                ? AppColors.bgBase
                                : AppColors.bgElevated,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient:
                                  (_avatarBytes == null && _avatarUrl == null)
                                      ? AppColors.accentGradientSoft
                                      : null,
                              image: _avatarBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(_avatarBytes!),
                                      fit: BoxFit.cover)
                                  : (_avatarUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(_avatarUrl!),
                                          fit: BoxFit.cover)
                                      : null),
                            ),
                            child: (_avatarBytes == null && _avatarUrl == null)
                                ? Icon(Icons.person,
                                    color: AppColors.textTertiary, size: 40)
                                : null,
                          ),
                        ),
                      ),
                      // Gradient edit badge — glow-той, bgBase cutout хүрээ
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentGradient,
                            border: Border.all(
                                color: AppColors.isDarkMode
                                    ? AppColors.bgBase
                                    : AppColors.bgElevated,
                                width: 2.5),
                            boxShadow:
                                AppColors.glowShadow(AppColors.accentStart),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              const FieldLabel('Нэр'),
              const SizedBox(height: 8),
              TextFormField(
                  controller: _nameCtrl,
                  maxLength: 60,
                  style: authFieldStyle,
                  onChanged: (_) => _nameEdited = true,
                  decoration: authInputDec(
                      hint: 'Таны нэр', icon: Icons.person_outline_rounded)),
              const SizedBox(height: 18),
              // Username
              const FieldLabel('Хэрэглэгчийн нэр'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _usernameCtrl,
                style: authFieldStyle,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _bioFocus.requestFocus(),
                decoration: authInputDec(
                    hint: '@username', icon: Icons.alternate_email_rounded),
                validator: _validateUsername,
              ),
              const SizedBox(height: 18),

              // Bio
              const FieldLabel('Танилцуулга'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bioCtrl,
                focusNode: _bioFocus,
                maxLines: 3,
                maxLength: 300,
                style: authFieldStyle,
                // Олон мөрт талбар — Enter нь шинэ мөр (илгээхгүй)
                textInputAction: TextInputAction.newline,
                decoration: authInputDec(
                    hint: 'Шөнийн амьдралд дуртай...',
                    icon: Icons.edit_note_rounded),
              ),
              const SizedBox(height: 24),

              // Interests
              Text('СОНИРХОЛ', style: AppTextStyles.sectionLabel),
              const SizedBox(height: 4),
              Text('Хамгийн ихдээ 6-г сонгоно',
                  style: AppTextStyles.bodyXs
                      .copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.interestOptions.map((tag) {
                  final active = _interests.contains(tag);
                  return TapScale(
                    onTap: () => _toggleInterest(tag),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.accentStart.withValues(alpha: 0.18)
                            : AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: active
                              ? AppColors.accentStart
                              : AppColors.hairline,
                          width: active ? 1.5 : 1,
                        ),
                        boxShadow: active
                            ? AppColors.glowShadow(AppColors.accentStart,
                                alpha: 0.22, blur: 14)
                            : null,
                      ),
                      child: Text(tag,
                          style: AppTextStyles.labelSm.copyWith(
                            color: active
                                ? AppColors.accentStart
                                : AppColors.textSecondary,
                            letterSpacing: 0.2,
                          )),
                    ),
                  );
                }).toList(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 20),
                AuthErrorBox(_error!),
              ],

              const SizedBox(height: 32),
              GradientButton(
                label: _loading
                    ? 'Хадгалж байна...'
                    : (_isEditMode ? 'Хадгалах' : 'Эхлэх'),
                onPressed: _loading ? null : _save,
                borderRadius: 999,
                trailing: _loading ? const BtnSpinner() : null,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}

// ───────────────────────── setup-only UI bits ─────────────────────────

/// Шилэн bottom-sheet бүрхүүл — дээд radius 28, bgElevated @0.85, grabber.
class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  static const List<BoxShadow> _lightShadow = [
    BoxShadow(color: Color(0x1F1A0B2E), blurRadius: 30, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0F1A0B2E), blurRadius: 8, offset: Offset(0, 3)),
  ];

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.hairline2),
          // Цайвар горимд хар 55% сүүдэр бохир харагдах тул зөөлөн ягаан сүүдэр
          boxShadow: AppColors.isDarkMode ? AppColors.shadowDock : _lightShadow,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Column(children: [
            const SizedBox(height: 10),
            // Grabber — bottom-sheet мэдрэмж
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.hairline2,
                  borderRadius: BorderRadius.circular(999)),
            ),
            Expanded(child: child),
          ]),
        ),
      );
}

// ── Профайл ачаалж байх үеийн хөнгөн skeleton — sheet дотор ──
class _FormSkeleton extends StatefulWidget {
  const _FormSkeleton();
  @override
  State<_FormSkeleton> createState() => _FormSkeletonState();
}

class _FormSkeletonState extends State<_FormSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {double r = 10}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 0.9)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _box(96, 96, r: 48)),
              const SizedBox(height: 28),
              _box(120, 12),
              const SizedBox(height: 10),
              _box(double.infinity, 48, r: 14),
              const SizedBox(height: 20),
              _box(90, 12),
              const SizedBox(height: 10),
              _box(double.infinity, 84, r: 14),
              const SizedBox(height: 22),
              _box(80, 12),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(6, (_) => _box(84, 34, r: 17))),
            ],
          ),
        ),
      );
}
