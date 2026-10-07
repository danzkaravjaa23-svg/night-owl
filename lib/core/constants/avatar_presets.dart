/// Built-in Night Owl identities. These stable references are saved in the
/// existing avatar_url field; no demographic information is inferred or stored.
class NightOwlAvatarPreset {
  final String id;
  final String label;
  final String assetPath;

  const NightOwlAvatarPreset(this.id, this.label, this.assetPath);

  String get value => 'nightowl://avatar/$id';
}

abstract final class NightOwlAvatars {
  // A consistent visual fallback only, never a guess about the account owner.
  static const defaultPreset = NightOwlAvatarPreset(
      'young-man', 'Залуу эрэгтэй', 'assets/images/avatars/owl_young_man.webp');

  static const all = <NightOwlAvatarPreset>[
    defaultPreset,
    NightOwlAvatarPreset('young-woman', 'Залуу эмэгтэй',
        'assets/images/avatars/owl_young_woman.webp'),
    NightOwlAvatarPreset('older-man', 'Ахимаг эрэгтэй',
        'assets/images/avatars/owl_older_man.webp'),
    NightOwlAvatarPreset('older-woman', 'Ахимаг эмэгтэй',
        'assets/images/avatars/owl_older_woman.webp'),
  ];

  static NightOwlAvatarPreset? fromValue(String? value) {
    final normalized = value?.trim();
    for (final preset in all) {
      if (preset.value == normalized) return preset;
    }
    return null;
  }

  static bool isNetworkPhoto(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }
}
