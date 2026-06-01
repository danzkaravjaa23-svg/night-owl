/// NightOwl брэндийн 🦉 шар шувуу sticker-ууд (DM + story-д хэрэглэнэ).
/// Эдгээр мессеж нь _isOwlSticker-ээр таньж онцгой sticker хэлбэрээр харагдана.
const kOwlStickers = [
  '🦉 ГАЛ ГАЛ 🔥',
  '🦉 ха ха ха 😂',
  '🦉 ШӨНӨ ЭХЭЛЛЭЭ ✨',
  '🦉 ПАТИ! 🎉',
  '🦉 Уулзъя 🍻',
  '🦉 Гоё шүү 😎',
  '🦉 Хөөе! 👀',
  '🦉 GG 🔥🔥',
  '🦉 Дэмжиж байна 💯',
  '🦉 Love 💜',
];

bool isOwlSticker(String s) => kOwlStickers.contains(s.trim());
