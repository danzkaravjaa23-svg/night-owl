/// Платформоос хамаарсан энгийн дуу тоглуулагч (web=HTML5 audio, бусад=no-op).
/// audioplayers plugin-ийн оронд — web дээр MissingPluginException гардаггүй.
export 'web_audio_stub.dart'
    if (dart.library.html) 'web_audio_web.dart';
