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

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _usernameCtrl = TextEditingController();
  final _bioCtrl      = TextEditingController();
  Uint8List? _avatarBytes;
  List<String> _interests = [];
  bool _loading = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        final username = data['username'] as String? ?? '';
        setState(() {
          _isEditMode = username.isNotEmpty;
          _usernameCtrl.text = username;
          _bioCtrl.text      = data['bio'] as String? ?? '';
          _interests = List<String>.from(data['interests'] ?? []);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
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
    setState(() => _avatarBytes = bytes);
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

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username is required')));
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.authLanding);
      return;
    }
    setState(() => _loading = true);
    try {
      String? avatarUrl;

      if (_avatarBytes != null) {
        final path = '${user.id}/avatar.jpg';
        await Supabase.instance.client.storage
            .from('avatars')
            .uploadBinary(path, _avatarBytes!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg', upsert: true));
        avatarUrl = Supabase.instance.client.storage
            .from('avatars').getPublicUrl(path);
      }

      final updates = <String, dynamic>{
        'id':         user.id,
        'username':   username,
        'bio':        _bioCtrl.text.trim(),
        'interests':  _interests,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await Supabase.instance.client.from('profiles').upsert(updates);

      if (!mounted) return;
      context.go(AppRoutes.feed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isEditMode) ...[
                    Row(children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: const Icon(Icons.arrow_back_ios_new,
                          size: 20, color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 12),
                      Text('Edit Profile', style: AppTextStyles.h1),
                    ]),
                  ] else ...[
                    Text('Introduce', style: AppTextStyles.displayMd),
                    Text('Yourself',
                      style: AppTextStyles.displayMd.copyWith(
                        fontStyle: FontStyle.italic,
                        foreground: Paint()
                          ..shader = AppColors.accentGradient.createShader(
                            const Rect.fromLTWH(0, 0, 200, 40)))),
                  ],
                  const SizedBox(height: 6),
                  Text('Add a photo, username, and interests',
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar picker
                    Center(
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            Container(
                              width: 90, height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _avatarBytes == null
                                    ? AppColors.accentGradientSoft
                                    : null,
                                image: _avatarBytes != null
                                    ? DecorationImage(
                                        image: MemoryImage(_avatarBytes!),
                                        fit: BoxFit.cover)
                                    : null,
                                border: Border.all(
                                  color: AppColors.accentStart.withValues(alpha: 0.4),
                                  width: 2),
                              ),
                              child: _avatarBytes == null
                                  ? const Icon(Icons.person,
                                      color: AppColors.textTertiary, size: 40)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppColors.accentGradient,
                                ),
                                child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Username
                    Text('USERNAME', style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: '@username'),
                    ),
                    const SizedBox(height: 20),

                    // Bio
                    Text('BIO', style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bioCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'I love the nightlife...'),
                    ),
                    const SizedBox(height: 24),

                    // Interests
                    Text('INTERESTS',
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.textSecondary, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text('Choose up to 6',
                      style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.textTertiary)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: AppConstants.interestOptions.map((tag) {
                        final active = _interests.contains(tag);
                        return GestureDetector(
                          onTap: () => _toggleInterest(tag),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.accentStart.withValues(alpha: 0.18)
                                  : AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active
                                    ? AppColors.accentStart
                                    : AppColors.hairline,
                                width: active ? 1.5 : 1,
                              ),
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
                    const SizedBox(height: 40),

                    GradientButton(
                      label: _loading
                          ? 'Saving...'
                          : (_isEditMode ? 'Save Changes' : 'Get Started'),
                      onPressed: _loading ? null : _save,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
