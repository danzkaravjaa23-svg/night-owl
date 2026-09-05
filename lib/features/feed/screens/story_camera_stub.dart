import 'dart:typed_data';
import 'package:flutter/widgets.dart';

/// Камерын үр дүн — cancel (юу ч хийхгүй) болон unsupported (file picker
/// fallback) хоёрыг ялгана.
class StoryCameraResult {
  final Uint8List? bytes;
  final bool unsupported;
  const StoryCameraResult._(this.bytes, this.unsupported);
  const StoryCameraResult.captured(Uint8List b) : this._(b, false);
  const StoryCameraResult.cancelled() : this._(null, false);
  const StoryCameraResult.unsupported() : this._(null, true);
}

/// Веб бус — unsupported буцаавал дуудагч image_picker камер руу шилжинэ.
Future<StoryCameraResult> openStoryCamera(BuildContext context) async =>
    const StoryCameraResult.unsupported();
