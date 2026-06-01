/// Form validators
abstract class Validators {
  static String? email(String? v) {
    if (v == null || v.isEmpty) return 'Email required';
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v)) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password required';
    if (v.length < 8) return 'Min 8 characters';
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v != original) return 'Passwords do not match';
    return null;
  }

  static String? required(String? v, [String field = 'This field']) {
    if (v == null || v.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? username(String? v) {
    if (v == null || v.isEmpty) return 'Username required';
    if (v.length < 3) return 'Min 3 characters';
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(v)) {
      return 'Only letters, numbers, _ and . allowed';
    }
    return null;
  }
}
