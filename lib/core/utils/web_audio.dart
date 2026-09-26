/// Платформоос хамаарсан энгийн дуу тоглуулагч (web=HTML5 audio, native=video_player).
/// audioplayers plugin-ийн оронд — web дээр MissingPluginException гардаггүй.
library;
export 'web_audio_stub.dart'
    if (dart.library.io) 'web_audio_io.dart'
    if (dart.library.html) 'web_audio_web.dart';
