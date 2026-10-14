# Midnight Violet — frontend шинэчлэл

2026-10-11. Одоогийн owl, navy/violet өнгө, таван үйлдэлтэй footer дээр
тулгуурлан илүү тансаг гадаргуу, үйлдэлд хариулах хөдөлгөөн нэмэв.

- **Нийтлэл:** satin gradient карт, нарийн lavender хүрээ, зөөлөн сүүдэр,
  том гарчиг, story цагирагийн гэрэлтэлт. Эхний картууд дараалж гарч ирнэ.
- **Газрууд:** монгол гарчиг, гэрэлтэлттэй header, хүрээтэй хайлт,
  өнгөө зөөлөн сольдог gradient шүүлтүүр, сонгосон газрын картын entrance,
  гэрлийн эффекттэй “Чиглэл авах” товч. Map camera/cache логик хэвээр.
- **Доод цэс:** дугуйрсан midnight violet dock. Богино гэрэлт зурааснаас
  доошоо тэлж бүдгэрэх violet гэрэл, идэвхтэй дүрс ба жижиг доод цэг.
  Гэрэл нь сонгосон цэс рүү 420ms-д гулсаад тогтвортой болно.
  Үүсгэх товчны glow/sheen болон бүх цэсийн нэр, үйлдэл хадгалагдсан.
- **Профайл:** зөөлөн entrance, avatar-ын halo, сонгосон tab-ыг дагаж
  гулсах underline. Хэрэглэгчийн бодит cover/avatar/stat логик хэвээр.
- **Мессеж:** бусад дэлгэцтэй нийцсэн violet header гэрэлтэлт.
- **Үндсэн товч:** hover, keyboard focus, дарахад нэг удаагийн light sweep.

`ActionSheen` нь child-аа frame бүрд rebuild хийхгүй, өөрийн painter-ийг
шинэчилнэ. 640ms-д дуусаад idle болно. Entrance нь 420–570ms, сонголтын
шилжилт 240–420ms. Blur анимац болон байнга давтагдах шинэ эффект нэмээгүй.
Disable Animations / Accessible Navigation болон TickerMode-ийг хүндэтгэнэ.

## Локал урьдчилсан харагдац

`tools/design_preview.dart` нь үндсэн аппын бодит widget-үүдийг тусдаа
жишээ өгөгдөлтэй үзүүлнэ. “ДИЗАЙНЫ ТУРШИЛТ · ЖИШЭЭ ӨГӨГДӨЛ” гэсэн
тайлбартай. Mock HTTP client нь GET болон feed унших RPC-г локалд хариулж,
mutation-ийг 405-аар татгалзана; production хаягаар нэвтрэхгүй, серверт
өгөгдөл нийтлэхгүй. Профайлын хаяг солигдох хамгаалалтыг шалгахын тулд
зөвхөн memory-д жишээ session ашиглана; жинхэнэ серверт хүчинтэй credential
агуулаагүй, session хадгалах сан нь `EmptyLocalStorage`.

```sh
flutter run -d web-server --web-port 5601 --no-pub -t tools/design_preview.dart
```

Preview нь анх 390px өргөнөөр харагдана. `?theme=light` нь өдрийн горим,
`?desktop=1` нь өргөн layout-ийг сонгоно. Үндсэн Netlify/CI entrypoint нь
`lib/main.dart` хэвээр; preview-д зориулж deployment тохиргоог солиогүй.

## Шалгалт

- Flutter analysis: цэвэр.
- Flutter: 227 тест амжилттай, үүнд light sweep-ийн activation, idle,
  reduced-motion ба footer-ийг хурдан дараалан солих шалгалтууд багтсан.
  Сонгосон цэсийн төлөв, нэр, үйлдэл дэлгэц уншигчид нэг control болж очно.
  ThemeReveal-ийг ашиглаагүй байхад устгах lifecycle алдааг давтан гаргах
  тестээр баталгаажуулж, controller-ийг initState-д үүсгэдэг болгон засав.
- Web/deployment tooling: 11 тест амжилттай. Windows дээр UTF-8 болон
  workspace доторх temporary directory ашигласан.
- Үндсэн production web build болон тусдаа debug preview build амжилттай.
- Браузерт утасны өргөнд өдөр/шөнийн feed, map, profile-ийг шалгав.
  Газрын зураг/жагсаалт, профайлын Хадгалсан таб, footer navigation болон
  горим солих үйлдэл ажилласан. Browser error log хоосон.

| Дэлгэц | Шөнө | Өдөр |
|---|---|---|
| Нийтлэл | [Зураг](visuals/premium-night-feed.jpg) | [Зураг](visuals/premium-day-feed.jpg) |
| Газрууд | [Зураг](visuals/premium-night-map.jpg) | [Зураг](visuals/premium-day-map.jpg) |
| Профайл | [Зураг](visuals/premium-night-profile.jpg) | [Зураг](visuals/premium-day-profile.jpg) |

Доод цэсийн spotlight хувилбар:
[Шөнийн харагдац](visuals/spotlight-night-feed.jpg),
[Өдрийн харагдац](visuals/spotlight-day-feed.jpg).

Бодит утсан дээрх FPS benchmark болон store build энэ UI ажлын хүрээнд
хэмжигдээгүй. Өөрчлөлтийг commit/push хийгээгүй.

2026-10-12-ны дараагийн сайжруулалт: [UI refinement тайлан](UI_REFINEMENT.md).
