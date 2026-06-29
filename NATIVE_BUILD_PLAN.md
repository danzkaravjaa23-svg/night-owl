# Native build (iOS/Android) болгох төлөвлөгөө

Одоо апп **вэб-locked** — учир нь зарим хэсэг `dart:html` (зөвхөн браузерт
байдаг) шууд ашигладаг тул `flutter build apk/ipa` амжилтгүй болно.

## Одоогийн байдал

| Файл | dart:html | Conditional уу? | Native-д блоклох уу? |
|---|---|---|---|
| core/utils/image_compress_web.dart | ✅ | ✅ stub бий | ❌ Үгүй (stub ажиллана) |
| core/widgets/video_view_web.dart | ✅ | ✅ stub бий | ❌ Үгүй |
| map/widgets/google_map_view_web.dart | ✅ | ✅ stub бий | ❌ Үгүй (stub = "Maps нээх") |
| feed/screens/story_camera_web.dart | ✅ | ✅ stub бий | ❌ Үгүй |
| **post/screens/create_post_screen.dart** | ✅ | ❌ **шууд** | 🔴 **ТИЙМ** |
| **live/screens/go_live_screen.dart** | ✅ | ❌ **шууд** | 🔴 **ТИЙМ** |

➡️ **Зөвхөн 2 файл засах хэрэгтэй.** Бусад нь conditional import-тай тул
native-д stub руу автоматаар уналт хийнэ.

---

## Алхам 1 — `create_post_screen.dart` (зураг/видео оруулах)

**Одоо:** `html.FileUploadInputElement` (файл сонгох), canvas resize,
`html.HttpRequest` (XHR upload).

**Шийдэл:** Платформ-аас хамаарсан media service гаргах:
- `lib/core/services/media_picker.dart` (barrel, conditional export)
  - `media_picker_web.dart` — одоогийн dart:html логик (зөөнө)
  - `media_picker_io.dart` — **`image_picker`** (аль хэдийн dependency)-ээр
    зураг/видео сонгох + **`flutter_image_compress`** (шинэ dep)-ээр resize +
    `SupabaseService.client.storage.uploadBinary` (ImageUploader-т аль хэдийн бий).
- create_post_screen-г UI болгож үлдээж, бүх `dart:html`-ийг service рүү зөөх.

**Хэмжээ:** Дунд (1 service + 2 impl + screen refactor). Multi-image,
progress-ийг хадгална.

---

## Алхам 2 — `go_live_screen.dart` (live дамжуулалт)

**Одоо:** `getUserMedia` (камер), `MediaRecorder` (бичлэг), `dart:ui_web`
platformView — бүгд браузерийн API.

**Шийдэл (том):** Native live нь өөр стек шаардана:
- Камерын урьдчилан харах: **`camera`** plugin.
- Жинхэнэ дамжуулалт: **LiveKit** / **Agora** / **Mux** SDK (WebRTC).
- `go_live_screen`-г conditional болгож, native дээр эхэндээ
  "Live удахгүй (зөвхөн вэб)" stub харуулж, дараа SDK холбох.

**Хэмжээ:** Том (гадны streaming SDK + данс). Эхний хувилбарт native дээр
Live-г түр нуух нь зүйтэй.

---

## Алхам 3 — Тохиргоо (аль хэдийн хийсэн)
- ✅ iOS `Info.plist` — камер/микрофон/зураг/байршил usage strings нэмсэн.
- ✅ Android `AndroidManifest.xml` — INTERNET/CAMERA/RECORD_AUDIO/LOCATION/
  READ_MEDIA permissions нэмсэн.
- Нэмж: `image_picker`-ийн iOS pod, Android Gradle min SDK 21+ шалгах.

---

## Алхам 4 — Тест
- `flutter build apk --debug` — Android compile амжилттай эсэх.
- `flutter build ios --no-codesign` — iOS compile.
- Бодит төхөөрөмж дээр камер/зураг/байршил зөвшөөрөл асуухыг шалгах.

---

## Зөвлөмж (хамгийн хурдан зам)
1. **Android-д эхэлэх:** Алхам 1 (create_post)-ийг засаад, Live-г native-д
   нуувал `flutter build apk` ажиллана → Google Play (эсвэл PWA→TWA).
2. **iOS дараа:** ижил code-base, Алхам 1 хангалттай (Live нууя).
3. **Live native** — хамгийн сүүлд, streaming SDK сонгоод холбоно.

> Тэмдэглэл: Вэб хувилбар (одоогийнх) бүрэн ажилласаар байна — энэ төлөвлөгөө
> бол *нэмэлт* native платформд гаргах зам.
