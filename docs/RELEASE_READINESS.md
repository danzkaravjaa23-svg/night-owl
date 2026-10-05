# Night Owl — release бэлтгэл

2026-10-05. Үнэгүй аппын шинэ код ба web release build бэлэн. `970f4d2` commit GitHub-д илгээгдэж, Netlify `6ac3eab4452c6d0009f932d7` дээр нийтлэгдсэн. Public JavaScript нь шалгасан локал build-тэй ижил. Native build/signing, App Store/Play Store нийтлэлт болон Apple provider-ийн бодит тохиргоо дараагийн ажлууд хэвээр.

Апп ашиглах төлбөр, subscription, premium unlock, in-app purchase идэвхтэй биш. QPay хуудас, төлбөрийн түүхийг хассан; хуучин `/qpay/:id` холбоос тухайн постыг нээнэ. Урилга нь үнэгүй хуваалцах холбоос бөгөөд unlock/reward амлахгүй. Paid-content entitlement хүснэгт/түгжээ байхгүй тул төлбөрийн backend migration шаардлагагүй. Төлбөрийн системийг deployment-ийн дараа тусдаа ажлаар шийдэх тул энэ үнэгүй release-ийн blocker биш. Газрын үйлчилгээ эсвэл эвентийн орох үнэ харагдвал энэ нь зохион байгуулагчийн мэдээлэл; апп дотор төлбөр авахгүй, бүх газар/эвент үнэгүй гэсэн утгатай биш. RSVP нь очих сонирхол/оролцоогоо тэмдэглэх үйлдэл бөгөөд тасалбар эсвэл төлбөр биш.

## 2026-10-05-ны локал UX шинэчлэлт

270 OSM газрын нэмэлт каталог, ойр pin-үүдийн бүлэглэл, эх сурвалж/утас/сайт/цагийн мэдээлэл, Instagram-аас санаа авсан бодит статистиктай профиль, ойлгомжтой эхлэлийн текст, Higgsfield owl emotion болон reduced-motion дэмждэг шилжилт нэмсэн. Google Places API key байхгүй тул Google мэдээлэл татсангүй. Бүтэн 215 тест, static analysis, JavaScript release build амжилттай. Локал preview-ийн хоригийн дараа 2026-10-06-нд нийтлэгдсэн апп дээр эхлэлийн loading, бүлэглэл/zoom, 279 газрын жагсаалт, map/list байрлал хадгалах, profile Saved, өдөр/шөнө болон газрын мэдээллийн цонхыг шалгасан. Browser error хоосон. Шинэ ZIP бэлэн, push/deploy баталгаажсан. PostgreSQL бүрэн export/cutover нууц үг, target host болон үйлчилгээний интеграци хүлээгдсэн хэвээр.

## 2026-10-06 loading шалгалт

Нийтлэгдсэн `be0c9a2` build-д шинэ owl emotion asset байхгүйг public JavaScript hash болон Netlify dashboard-аар баталсан. Локал кодын route/press motion, үндсэн loading ажилласан; хайлт, мэдэгдэл, дагагчид, creator/post detail, business болон auth loading-ийг гүйцээсэн. Web bootstrap одоо logo/status, бодит first-frame cleanup, initialization error/retry-тэй. 215 Flutter тест, 7 Node startup тест болон анализ амжилттай; шинэ release ZIP бэлэн. Шинэ хувилбар Netlify дээр нийтлэгдэж, public файл болон браузерийн ажиллагаагаар баталгаажсан.

## Баталгаажуулалтын төлөв

- Flutter 3.44.0 / Dart 3.12.0; static analysis: no issues.
- Бүтэн Flutter suite-ийн 215 тест амжилттай. Өмнөх auth/callback/profile metadata, координат/owner засвар, account isolation, feed/filter/navigation, үнэгүй холбоос/урилга, JPEG/video validation болон reference layout-ийн шалгалтууд хадгалагдсан. Шинэ шалгалтууд өдөр/шөнө/System, OS brightness, preference-ийн дараалсан хадгалалт, startup/хожуу үр дүн, `false`/exception rollback ба disposal-ийг хамарна. Profile хоёр горимд 320/1280px ба 1.5x текстээр, Settings 320px ба 2x текстээр; Feed/Messages болон map-ийн горим солих ажиллагааг мөн шалгасан.
- JavaScript web release build амжилттай. ZIP: `build/releases/night-owl-web-release.zip`; нарийвчилсан баталгаа `docs/BUILD_VERIFICATION.json`. Wasm release шалгаагүй: одоогийн secure-storage web dependency Wasm-тэй нийцэхгүй.
- Android build оролдлого: `No Android SDK found` — AAB/APK бүтээгдээгүй. Энэ Mac-д Java runtime мөн байхгүй.
- iOS build оролдлого: `Application not configured for iOS`. iOS project/bundle ID файлууд байгаа боловч Xcode tooling байхгүй учраас Flutter bundle identifier-ийг build settings-ээс уншиж чадахгүй. Бүтэн Xcode, CocoaPods шаардлагатай; IPA/Runner.app бүтээгдээгүй.
- CI тохиргоо `.github/workflows/build.yml` бэлэн, remote run хийгдээгүй. Unsigned AAB/Runner.app нь дэлгүүрт upload хийх signed release биш.
- Edge function болон SQL migration локалд бэлдсэн, серверт deploy хийгдээгүй. Deno integration шалгалт хийгдээгүй. Тусдаа PostgreSQL 17.11 зохиомол өгөгдөл дээр restore болон target RPC authorization/concurrency шалгалт амжилттай; production integration биш.
- Apple нэвтрэлт: iOS native identity-token + nonce урсгал, web/Android OAuth, provider preflight код бэлэн. 2026-10-05-ны public settings шалгалтаар `apple=false`, `google=true`, `email=true`; Apple backend идэвхгүй. Бодит Apple end-to-end нэвтрэлт, iOS binary/device туршилт хийгдээгүй.
- Шинэ web release-ийг хөтөч дээр шалгасан: Apple товч харагдаж, идэвхгүй provider-ийн тайлбарыг апп дотор үзүүлнэ. Цуцлагдсан OAuth callback цэвэр URL ба тайлбартай буцаж, reload хийхэд дахин алдаа гаргахгүй. Settings-ийн жагсаалт, хамгийн доод хэсэгт бүртгэл устгах товч байхгүй. Эдгээр нь Apple account-аар амжилттай нэвтэрсэн туршилт биш.
- Хэрэглэгчийн сонгосон reference-ийн шинэ map/feed/profile-ийг 390×844, map/footer-ийг 320×720, desktop profile-ийг 1280×900 дээр шалгасан. Fat Cat хайлт, хайлт цэвэрлэх, 12 газрын жагсаалт, Saved-ийн бодит хоосон төлөв, profile edit-ийн хадгалсан утгууд, мессежийн тогтмол цэс, Post/Story/Reels/Event үүсгэх сонголтууд ажилласан. Browser-ийн error жагсаалт хоосон; өөр хэрэглэгчид пост/мессеж илгээх эсвэл profile submit хийгээгүй. Шинэ зургууд `docs/visuals/approved-*.jpg`.
- Хэрэглэгчийн хүссэн хэмжээст icon/товч, Settings-ийн Өдөр / Шөнө / Систем сонголт, Feed/Messages-ийн нар/сар хурдан солих товч хэрэгжсэн. `SculptedIcon` нь Flutter vector давхарга/shader/сүүдэр ашигладаг UI rendering; 3D model эсвэл шинэ AI artwork биш. Approved flat owl ба reference layout хэвээр. Map tile өнгө солигдоход camera-ийн төв/zoom ба сонгосон газар хадгалагдана; профайлын cover, медиа үйлдлүүдийн цагаан дүрс хэвээр.
- Өдөр/шөнийн browser proof: [Feed — шөнө](visuals/theme-night-feed.jpg), [Feed — өдөр](visuals/theme-day-feed.jpg), [Map — шөнө](visuals/theme-night-map.jpg), [Map — өдөр](visuals/theme-day-map.jpg). [HTML харьцуулалт](design-review.html) дээр зэрэгцүүлсэн gallery бий. Өдрийн горим reload-ийн дараа, Messages-ийн хайлт горим солиход хадгалагдсан; мессеж илгээгээгүй. Эдгээр нь локал web build-ийн баталгаа; public deployment эсвэл native төхөөрөмжийн шалгалт гэсэн үг биш.

## Release-ийн зайлшгүй ажлууд

1. Staging Supabase-д `supabase/migrations/202610050001_check_in_venue.sql`-г шалгаж хэрэгжүүлэх. Шинэ client энэ RPC-г шаарддаг; хэрэглэгчийн id болон хугацааг сервер шийднэ. Нэг хаягаас зэрэг хоёр хүсэлт, хоёр төхөөрөмж, expired check-in, өөр хүний мөрийг өөрчлөх оролдлогоор турших.
2. Хэрэглэгчийн хүсэлтээр Settings-ийн бүртгэл устгах товчийг хассан. `web/delete-account.html`, нууцлалын бодлого болон нөхцөлд устгах хүсэлтийг одоогийн support хаяг `osokhe@gmail.com` руу илгээхээр заасан; хүсэлт боловсруулах бодит ажиллагаа, хугацаа, гүйцэтгэл шалгагдаагүй. `supabase/functions/delete-account/index.ts` локалд бэлэн хэвээр боловч deploy хийгдээгүй, апп дотор дуудах замгүй. Дэлгүүрт илгээхээс өмнө өөр ашиглаж болох in-app account-deletion замыг шийдэж, staging-д disposable account дээр Auth, FK cascade, avatar/posts/stories/venues storage cleanup, давтан хүсэлт, storage алдаа, unauthenticated/GET хүсэлтийг турших. [Apple-ийн account-deletion заавар](https://developer.apple.com/support/offering-account-deletion-in-your-app/) бүртгэл үүсгэдэг апп дотроос устгал эхлүүлэх боломж шаарддаг; энэ төрлийн аппын email-only support зам хангалтгүй. [Google Play-ийн заавар](https://support.google.com/googleplay/android-developer/answer/13327111) in-app зам болон ажилладаг web request resource шаарддаг. Товчийг хассан хувилбарыг store submission-д бэлэн гэж үзэхгүй. Production deployment тусдаа зөвшөөрөлтэй ажил.
3. [Apple нэвтрэлтийн тохиргооны заавар](APPLE_SIGN_IN_SETUP.md)-аар provider-ийг идэвхжүүлж баталгаажуулах. Services ID-г Supabase Apple Client IDs-ийн эхний утга, native bundle ID `com.nightowl.ub.nightOwlUb`-г нэмэлт audience болгоно. Apple Return URL: `https://jbbdnpsvstwxtgtjoeru.supabase.co/auth/v1/callback`; Supabase app redirect allow-list: `com.nightowl.ub://login-callback/`, `http://127.0.0.1:8765/`, бодит HTTPS web origin. Signing key/secret зөвхөн серверт; OAuth secret-ийг хугацаа дуусахаас өмнө зургаан сарын дотор шинэчилнэ. Native entitlement гурван build config-д холбоотой ч Apple Developer capability, team/provisioning тохиргоо болон бодит нэвтрэлтийн шалгалт шаардлагатай. Google provider-ийн public flag идэвхтэй байгаа нь бүтэн OAuth/device туршилт хийсэн гэсэн үг биш.
4. Android SDK/JDK17-тай орчинд CI болон native build хийх. `android/key.properties.example`-ээс локал `android/key.properties` үүсгэж upload key тохируулах. Одоо debug key-г release signing болгож ашиглахгүй. Keystore/нууц үг ignored.
5. Xcode-тай Mac дээр CocoaPods, provisioning/team тохируулж `flutter build ipa --release` хийх. Bundle ID: `com.nightowl.ub.nightOwlUb`. Android ID: `com.nightowl.ub.night_owl_ub`.
6. Бодит утсанд камер/media picker, story/reel playback, Android lost-picker recovery, буцах ажиллагаа, location denied/disabled/allowed, Google/Apple callback, профайл upload, удаан сүлжээ, account switch-ийг турших. Одоогийн тест native төхөөрөмжийн баталгаа биш.
7. Үйлчилгээний одоогийн хязгаарыг release-д зөв тусгах: Live media transport, voice/video calls, push notifications, private accounts хараахан хэрэгжээгүй. Live browser prototype зөвхөн локал бичлэг хийдэг байсан; шинэ release route үүнийг live гэж зарлахгүй. Хэрэгжээгүй боломжийг идэвхтэй үйлчилгээ гэж сурталчлахгүй. “Бүх функц ажилладаг” гэж үзэхгүй.
8. Газрын байршлын найман жишээ координатыг эзнээр нь засуулах, үлдсэн баталгаажаагүй хоёр pin-ийг нягтлах. 700 load-test мөр client дээр нуугдсан, серверээс устгаагүй.
9. Production-д map provider сонгох, `MAP_TILE_URL`, `MAP_ATTRIBUTION`, `MAP_ATTRIBUTION_URL`, `PUBLIC_APP_URL`-ийг бодит public origin-той тохируулах. Газрын зураг native-д flutter_map-ийн built-in HTTP-header cache, web-д browser cache ашигладаг; bulk download байхгүй.
10. Дэлгүүрийн тайлбар, screenshots, app review test account, насны ангилал, privacy/data-safety мэдээлэл, support контакт, moderation үйл ажиллагааг эзэмшигч баталгаажуулах. [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/) болон [Google account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)-ийн одоогийн шаардлагыг дагана. Энэ release-д аппын үнэ үнэгүй; subscription болон in-app purchase зарлахгүй. Ирээдүйн төлбөртэй хувилбарын QPay/IAP ба дэлгүүрийн шаардлагыг тусдаа ажлаар шийднэ.

## Build хийх

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub --release --dart-define=DEVICE_PREVIEW=false
# Android SDK-тай орчинд: unsigned, эсвэл key.properties байвал signed
flutter build appbundle --no-pub --release
# Xcode-тай орчинд CI шалгалт:
flutter build ios --no-pub --release --no-codesign
# Provisioning/signing тохируулсны дараа:
flutter build ipa --no-pub --release
```

`python3 scripts/export_icons.py` нь хэрэглэгчийн сонгосон reference-ээс сэргээн бүтээсэн owl icon-ыг одоогийн iOS/Android/web asset slot-уудад дахин экспортлоно (Pillow шаардлагатай).

## Үндсэн ажиллагааны матриц

| Ажиллагаа | Шинэ код | Баталгаажуулалт / хязгаар |
|---|---|---|
| Auth/session | Public route хил, stale profile request хамгаалалт; Apple iOS identity-token + nonce, web/Android OAuth, provider preflight | Apple backend flag идэвхгүй (`apple=false`, 2026-10-05); provider/callback/signing тохиргоо ба бодит Apple E2E/native шалгалт хүлээгдэж байна |
| Профайл | Нэр/био/username/avatar, tab labels, session scope | Validation/JPEG тест; production profile засвар submit хийгээгүй |
| Feed/like/save/follow | Хаяг солих төлөв, давхар like/follow guard, disposed async хамгаалалт, алдааны rollback | Нүүрийг браузерт үзсэн; өөр хэрэглэгчид like/follow/post/message явуулаагүй |
| Map | Бодит OSM tile, category/query/selected detail/directions/location; reference-ийн owl pin, цайвар карт; өдөр/шөнийн tile/control, camera хадгалах; bookmark хаяг/төхөөрөмж тус бүрт | Браузерийн хайлт/жагсаалт/320px карт ба хоёр горимын proof; coordinate, camera ба persistence/isolation/алдааны тест; bookmark cloud sync биш, precise-location permission олгоогүй |
| Бизнес самбар | Бодит пост, ирэх эвент, эзэмшдэг газар, хугацаатай check-in; олон газар тусад нь засах | Жишээ үзэлт/орлого/графикийг хассан; browser read-only шалгалт |
| Check-in | Server transaction + expiry timer | Migration deploy болон Postgres integration тест хүлээгдэж байна |
| Settings | Account scoped notifications/activity, presence clear, notification stream opt-out; төхөөрөмжийн Өдөр/Шөнө/Систем appearance | Persistence/isolation/rollback, startup/latest request/disposal/System тест; 320px ба 2x текстийн layout |
| Account deletion | Settings товчийг хассан; public заавар support email рүү чиглэнэ; prepared function хадгалсан | Апп дотор устгал эхлүүлэх замгүй; email хүсэлтийн fulfillment болон destructive test хийгээгүй; deploy болон store-д нийцэх зам хүлээгдэж байна |
| Posts/story/reels/DM/events | Одоогийн implementation хадгалсан, post venue picker live data-тай, JPEG format зассан | Бүрэн хоёр хэрэглэгчтэй staging/device тест хүлээгдэж байна |
| Үнэгүй ашиглалт | QPay/төлбөрийн түүхийг хассан; урилга unlock/reward амлахгүй; subscription/premium/IAP идэвхгүй | Төлбөрийн интеграци энэ release-ийн шаардлага биш; газрын/эвентийн бодит үнэ бол мэдээлэл; RSVP нь тасалбар/төлбөр биш |
| Live/calls/push/private | Бүрэн интеграци байхгүй | Хэрэгжээгүй боломжийг ажилладаг гэж зарлахгүй; үйлчилгээний хязгаар хэвээр |

Веб build бэлэн болох нь App Store/Play Store review-д бэлэн гэсэн баталгаа биш.
