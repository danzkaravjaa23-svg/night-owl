import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:night_owl_ub/core/utils/media_picker_setup.dart';

class _OtherPlatformPicker extends ImagePickerPlatform {}

void main() {
  test('Android gallery picks use the system photo picker', () {
    final android = ImagePickerAndroid();
    ImagePickerPlatform.instance = android;
    expect(android.useAndroidPhotoPicker, isFalse);

    useSystemPhotoPicker();

    expect(android.useAndroidPhotoPicker, isTrue);
  });

  test('other platforms keep their own picker', () {
    final other = _OtherPlatformPicker();
    ImagePickerPlatform.instance = other;

    expect(useSystemPhotoPicker, returnsNormally);
    expect(ImagePickerPlatform.instance, same(other));
  });
}
