import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Makes gallery picks on Android (post, story, reel, avatar, cover) open the
/// system photo picker: a grid of the phone's photos and videos with albums,
/// and no storage permission needed. Without this, image_picker opens the
/// document browser (ACTION_GET_CONTENT), which looks like a file manager.
/// Other platforms are unchanged. Call once at startup.
void useSystemPhotoPicker() {
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
}
