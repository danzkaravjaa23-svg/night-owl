import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:night_owl_ub/features/post/utils/post_media.dart';

/// Records which gallery request the post composer's picker makes.
class _RecordingPicker extends ImagePickerPlatform {
  final calls = <String>[];

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    calls.add('media multiple=${options.allowMultiple} limit=${options.limit}');
    return const [];
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions(
      {MultiImagePickerOptions options =
          const MultiImagePickerOptions()}) async {
    calls.add('images limit=${options.limit}');
    return const [];
  }

  @override
  Future<XFile?> getImageFromSource(
      {required ImageSource source,
      ImagePickerOptions options = const ImagePickerOptions()}) async {
    calls.add('image source=${source.name}');
    return null;
  }
}

void main() {
  late _RecordingPicker picker;
  setUp(() => ImagePickerPlatform.instance = picker = _RecordingPicker());

  test('a new post asks the gallery for up to 10 photos or videos', () async {
    expect(await pickPostMedia(limit: 10), isEmpty);
    expect(picker.calls, ['media multiple=true limit=10']);
  });

  test('adding to a photo post asks for photos only, up to the free slots',
      () async {
    await pickPostMedia(limit: 9, imagesOnly: true);
    await pickPostMedia(limit: 2, imagesOnly: true);
    expect(picker.calls, ['images limit=9', 'images limit=2']);
  });

  test('one free slot opens a single pick (multi-select needs 2 or more)',
      () async {
    await pickPostMedia(limit: 1, imagesOnly: true);
    await pickPostMedia(limit: 1);
    await pickPostMedia(multiple: false);
    expect(picker.calls, [
      'image source=gallery',
      'media multiple=false limit=null',
      'media multiple=false limit=null',
    ]);
  });
}
