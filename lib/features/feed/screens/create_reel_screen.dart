import 'package:flutter/material.dart';

import '../../discovery/widgets/venue_picker.dart';
import '../../post/screens/create_post_screen.dart';
import '../../post/services/content_publication.dart';
import '../../post/utils/post_media.dart';

/// Reel publication shares the post composer's captured account, immutable
/// retry and draft protections. Reels remain single-video posts on the server.
class CreateReelScreen extends StatelessWidget {
  final ContentPublicationService? publicationService;
  final Future<List<PickedMediaFile>> Function({bool multiple})? mediaPicker;
  final VenueCatalogLoader? venueLoader;

  const CreateReelScreen({
    super.key,
    this.publicationService,
    this.mediaPicker,
    this.venueLoader,
  });

  @override
  Widget build(BuildContext context) => CreatePostScreen(
        videoOnly: true,
        publicationService: publicationService,
        mediaPicker: mediaPicker,
        venueLoader: venueLoader,
      );
}
