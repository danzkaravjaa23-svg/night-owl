/// Story хөгжмийн цуглуулга.
///
/// ⚠️ Эдгээр нь royalty-free (чөлөөтэй ашиглах) аудио замууд — апп дотор
/// жинхэнэ сонсогдоно. Арилжааны жинхэнэ дуу (Spotify/Apple Music каталог)
/// нэмэхийн тулд тусгай лиценз шаардлагатай; лиценз авсны дараа доорх
/// `url`-уудыг солиход хангалттай.
class StorySong {
  final String title;
  final String artist;
  final String url;
  const StorySong(this.title, this.artist, this.url);
}

const String _base = 'https://www.soundhelix.com/examples/mp3';

const List<StorySong> kStorySongs = [
  StorySong('Шөнийн жолоо', 'NightOwl Mix', '$_base/SoundHelix-Song-1.mp3'),
  StorySong('Неон',         'UB Beats',     '$_base/SoundHelix-Song-2.mp3'),
  StorySong('Lounge Vibe',  'Owl Records',  '$_base/SoundHelix-Song-3.mp3'),
  StorySong('Хотын гэрэл',  'Aurora',       '$_base/SoundHelix-Song-4.mp3'),
  StorySong('Midnight',     'Pulse',        '$_base/SoundHelix-Song-5.mp3'),
  StorySong('Дулаан шөнө',  'Velvet',       '$_base/SoundHelix-Song-6.mp3'),
  StorySong('Electric',     'Skyline',      '$_base/SoundHelix-Song-7.mp3'),
  StorySong('Огторгуй',     'Lunar',        '$_base/SoundHelix-Song-8.mp3'),
  StorySong('Afterparty',   'Groove Lab',   '$_base/SoundHelix-Song-9.mp3'),
  StorySong('Sunrise',      'Echo',         '$_base/SoundHelix-Song-10.mp3'),
];
