// Story/Reel-д зориулсан удирдлагатай видео (pause/mute notifier,
// duration/ended callback) + blob URL туслахууд.
// Веб дээр l HTML5 <video>, бусад дээр placeholder.
export 'story_video_stub.dart'
    if (dart.library.html) 'story_video_web.dart';
