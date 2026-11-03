/// Curated story music. Add tracks only after their reuse rights and accurate
/// title/artist attribution have been recorded in docs/app-store/MEDIA_RIGHTS.md.
class StorySong {
  final String title;
  final String artist;
  final String url;
  const StorySong(this.title, this.artist, this.url);
}

// The previous demo catalogue used invented artist names for SoundHelix MP3s.
// Its upstream rights page could not be verified during the release audit.
const List<StorySong> kStorySongs = [];
