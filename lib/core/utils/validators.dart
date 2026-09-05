/// Form validator-ууд — монгол хэл дээрх мессежтэй.
/// Auth/профайл формуудад нэгдсэн validation-д ашиглана.
abstract class Validators {
  static String? email(String? v) {
    if (v == null || v.isEmpty) return 'Имэйл шаардлагатай';
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v)) {
      return 'Зөв имэйл хаяг оруулна уу';
    }
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Нууц үг шаардлагатай';
    if (v.length < 8) return 'Хамгийн багадаа 8 тэмдэгт';
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v != original) return 'Нууц үг таарахгүй байна';
    return null;
  }

  static String? required(String? v, [String field = 'Энэ талбар']) {
    if (v == null || v.trim().isEmpty) return '$field шаардлагатай';
    return null;
  }

  static String? username(String? v) {
    if (v == null || v.isEmpty) return 'Хэрэглэгчийн нэр шаардлагатай';
    if (v.length < 3) return 'Хамгийн багадаа 3 тэмдэгт';
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(v)) {
      return 'Зөвхөн латин үсэг, тоо, _ болон . зөвшөөрнө';
    }
    return null;
  }
}
