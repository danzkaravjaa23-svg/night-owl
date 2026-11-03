# Night Owl UB: App Store бэлтгэлийн багц

2026-11-03, Asia/Ulaanbaatar. **Локал аудит дууссан; App Store-д илгээхэд бэлэн биш.** Хамгийн сүүлийн бүтэн Flutter шалгалтаар **686 тест PASS**; админ SQL fixture-ийн **24 бүлэг**, web admin-ийн **29 Node**, deployment-ийн **34 Python** тест PASS. Админ UI-ийн 20 локал widget visual fixture, offline web-ийн 5 screenshot шалгагдсан; эдгээр нь зохиомол өгөгдөлтэй, hosted/native device E2E эсвэл store screenshot-ийн баталгаа биш. Native compile, signing, төхөөрөмжийн туршилт болон серверийн шинэ өөрчлөлтийн баталгаажуулалт үлдсэн. Энэ удаад deploy/Git push, production migration, аккаунтад админ эрх олгох, OS шинэчлэлт, membership эсвэл төлбөрийн өөрчлөлт хийгээгүй.

GPT-6 Astra / ultra давхар review-ээр publication HTTP/session, групп чат, эвентийн UTC/RSVP болон устгалын response/Storage шалгалтууд сайжирсан. Өмнөх API шалгалтын 66 Node, 13 Deno loopback алхам, 7 isolated SQL PASS нь түүхэн тусдаа receipt; дээрх шинэ тоонуудтай нийлүүлж тоолохгүй. Өмнөх UX/UI шатны 636 Flutter тест, static analysis, JavaScript web release build болон 36 capture case / 48 PNG нь мөн тухайн шатны үр дүн. Одоогийн нотолгоог [build receipt](BUILD_VERIFICATION.json), [release тайлан](RELEASE_READINESS.md)-аас харна; hosted/native/store саадууд хэвээр.

## Одоогийн саад

| Алхам | Бодит төлөв |
|---|---|
| macOS | 15.5 (`24F74`); энэ удаад суулгалт/restart хийгээгүй |
| Xcode | Full Xcode/iPhoneOS SDK байхгүй, `xcode-select` нь CommandLineTools; 8/8 source шалгалт PASS, toolchain BLOCK |
| CocoaPods / Flutter | CocoaPods 1.17.0, Flutter 3.44.0 суусан |
| Apple Developer | Өмнөх шалгалтаар Pending / Purchase your membership байсан. 11-р сарын 3-нд гишүүнчлэлийн төлөвийг дахин баталгаажуулаагүй, төлбөр төлөөгүй |
| Signing / App Store Connect | Team/provisioning, App ID/Services ID, store record, signed archive/IPA, upload батлагдаагүй |
| Apple login | Код/entitlement байгаа; 11-р сарын 3-нд public flag `false`. Provider тохиргоо ба бодит native нэвтрэлт хүлээгдэж байна |
| Бүртгэл устгах | UI/service ба серверийн хамгаалалт локалд шалгагдсан; function default идэвхгүй. Public endpoint-ийн GET 404; устгал ажиллаж байгааг батлахгүй |
| Серверийн өөрчлөлт | Storage, deletion boundary (`001`), analytics consent (`002`), admin console (`003`) гэсэн 4 SQL migration суулгаагүй. `003`-ын өмнө `001` заавал орно; бодит Auth/Storage/FK/recovery/concurrency/Apple revoke болон админ эрх/аудитын staging шалгалт шаардлагатай |
| Support URL | Public `support.html` одоогоор Flutter fallback үзүүлж байна. Зөв static хуудсыг deploy хийж агуулгаар нь шалгана; HTTP 200 дангаараа хангалтгүй |
| Native туршилт | iPhone/iPad/simulator дээр ажилласан нотолгоо, store screenshot байхгүй |
| Контентын аюулгүй байдал | Report/block, 18+ өөрийн мэдүүлэг, community consent болон админ модерацийн хэрэгсэл локалд байгаа; нийтлэхээс өмнөх шүүлт, хариуцсан модератор ба бодит report боловсруулах ажиллагаа батлагдаагүй |

Эзэмшигч Apple-ийн тохиргоо/төлбөрийг дараа хийхээр үлдээсэн. Өмнөх 10-р сарын 22-ны тэмдэглэлд Sequoia 15.8.1 download 100% / exit 0, Xcode 26.3 татах холбоос Unauthorized байсан; эдгээр нь суулгалтын баталгаа биш. Одоогийн аудит OS, license, membership-д өөрчлөлт оруулаагүй. Тохирох macOS/Xcode суулгах, гэрээ зөвшөөрөх, membership идэвхжүүлэхийг эзэмшигч шийднэ.

### Локал Устгалын Бэлтгэл

Settings → Бүртгэл устгах; шинэ хэрэглэгч setup-ийн ижил товчоор нэвтэрч болно. Checkbox болон эцсийн dialog шаардана. Аккаунт солигдох/дэлгэц хаагдах үед хуучин response шинэ account-ын төлөвийг цэвэрлэхгүй. Амжилтыг server response-ийн owner ID-тай тулгана; 404/503, timeout/partial failure-ийг амжилт гэж үзэхгүй. [Handler-ийн enable checklist](../supabase/functions/delete-account/README.md)-ийг дагана.

`ACCOUNT_DELETION_ENABLED` default идэвхгүй. Apple-linked account grant revoke бэлэн болтол устгал нь хоригтой. Дараах өөрчлөлтүүд зөвхөн локал/isolated fixture-д шалгагдсан, серверт суулгаагүй:

- `202610220001_storage_account_guards.sql`: profile-гүй/хуучин JWT upload болон бусдын media prefix-ийн хамгаалалт.
- `202611030001_account_deletion_boundaries.sql`: profile-ийг client-ээс шууд устгах замыг хааж, Storage metadata-г шууд устгадаг хуучин trigger-ийг идэвхгүй болгох.
- `202611030002_discovery_analytics_consent.sql`: analytics-ийг зөвшөөрсөн хэрэглэгчээр сервер талд хязгаарлах.

Staging дээр бодит Auth/Storage/FK, зэрэг upload/устгал, legacy cleanup, тасалдсаны дараах recovery, Apple revoke-ийг шалгасны дараа production migration/function enable-ийг шийднэ. Fixture PASS нь эдгээр үйлчилгээний интеграцийн баталгаа биш.

### Локал админ ба модерацийн бэлтгэл

Profile болон Settings-ээс нэвтрэх админ хэсэг, тусдаа web admin локалд шинэчлэгдсэн. Report queue, хэрэглэгчийн ban/verification, post/comment хяналт, append-only аудит, featured event болон venue/pilot удирдлага холбогдсон. Хэрэглэгчийг админ болгох үйлдэл, бүх хэрэглэгчийн хувийн DM-ийг унших хэрэгсэл байхгүй.

Админ консолын RPC бүр идэвхтэй, ban хийгдээгүй админы эрхийг шалгана. Client нь тухайн session-ий token-оор хүсэлт явуулж, аккаунт солигдох эсвэл сервер эрхгүй гэсэн хариу өгөхөд хувийн админ өгөгдлийг цэвэрлэнэ; дэлгэц рүү буцахад эрхээ дахин шалгана. Модерацийн шалтгаан, зорилтот объект, report-ийн төлөв болон аудитын receipt-ийг тулгаж, үйлдэл/report closure/аудитыг нэг transaction-д хадгална. Тайлангийн insert validation, profile flag-ийн шууд өөрчлөлтийн хамгаалалт, админ CRUD-ийн аудит болон алга болсон venue-г хадгалсан мэт үзүүлэхээс хамгаалалт нэмэгдсэн.

Эдгээр серверийн өөрчлөлт нь **суулгаагүй** `202611030003_admin_console.sql`-д байна; өмнө нь `202611030001_account_deletion_boundaries.sql` суусан байхыг шаарддаг. Read-only preflight/postflight SQL болон isolated fixture бэлэн. Бодит серверт migration суулгах, админ эрх олгох, эрх цуцлалт/Storage/RLS/аудитыг staging дээр батлах ажил хийгдээгүй. Хэрэгсэл бэлэн болсон нь модераторын ээлж, report-д хариулах хугацаа, escalation эсвэл App Store UGC шаардлагын ажиллагааг батлахгүй.

## Build Дараалал

Apple-ийн [SDK шаардлага](https://developer.apple.com/news/upcoming-requirements/) болон [нийцлийн хүснэгт](https://developer.apple.com/xcode/system-requirements)-ээр Xcode 26+ / iOS 26 SDK+ хэрэгтэй. Sequoia 15.8.1 + Xcode 26.3 нь эхний сонгосон нийцэх хос; шинэ төхөөрөмжийн iOS хувилбарт илүү шинэ Xcode шаардлагатай эсэхийг тусад нь шалгана.

```sh
# Repo-ийн үндсэн фолдероос. Эхнийх нь Xcode шаардахгүй.
python3 tools/deployment/ios_preflight.py --source-only
python3 tools/deployment/ios_preflight.py
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
sh tools/deployment/build_ios.sh --no-pub
```

`build_ios.sh` хаанаас ч дуудагдаж болно. Backend public config-ийг вебтэй ижил validator-аар үүсгэнэ, Device Preview-г хаана, unsigned release compile хийнэ. Зөвхөн `--no-pub` нэмэлтээр зөвшөөрнө; дураар endpoint/secret/signing define оруулахгүй. Xcode дутуу бол compile-оос өмнө зогсоно. License зөвшөөрөх, SDK татах, sudo, migration, upload, purchase хийхгүй.

Unsigned `build/ios/iphoneos/Runner.app` нь дэлгүүрт илгээх IPA биш. Орчны саадыг арилгахаас нийтлэх хүртэл:

1. Эзэмшигч Xcode license-ээ өөрөө уншиж зөвшөөрнө; Xcode developer directory, first launch, iOS SDK/runtime бэлэн болсныг шалгана. Flutter-ийн CocoaPods/SPM dependency resolution-ийг бодит build-ээр батална; одоогийн Podfile байхгүй нь дангаараа build алдааны нотолгоо биш. `geolocator_apple`-ийн foreground-only permission тохиргоог ашигласан dependency manager-т нь тулган шалгана.
2. Unsigned compile болон simulator run-ийг батална. Бодит iPhone туршилт нь signing тохируулсны дараа хийгдэнэ. Үнэгүй Personal Team-ийн capability хязгаар нь энэ аппын Apple entitlement-тэй provisioning-ийг хааж болох тул paid capability-г үнэгүй ажиллана гэж амлахгүй. TestFlight нь paid membership шаарддаг; үнэгүй local build-ийг TestFlight гэж нэрлэхгүй.
3. Гишүүнчлэл идэвхжсэний дараа native App ID/Services ID, Sign in with Apple, Team/provisioning тохируулна. [Apple login заавар](APPLE_SIGN_IN_SETUP.md)-ын callback-ийг мөрдөнө. Signing key, `.p8`, secret, test-account password-ийг repo/чатад бичихгүй.
4. `ios/Runner.xcworkspace`-г Xcode-д нээж бодит Team сонгоно. Гурван configuration-ийн bundle ID-г `com.nightowl.ub.nightOwlUb` хэвээр шалгана. Version `1.0.0`, build `1`-ийг App Store Connect-д өмнө ашигласан эсэхийг шалгаж байж build number сонгоно. USB iPhone-оо Trust/Developer Mode-той холбож device test хийнэ; төхөөрөмжийн зөвшөөрөл, Apple sign-in-г хүн өөрөө хийнэ.
5. Тусдаа зөвшөөрөлтэй signed `flutter build ipa --release --dart-define=DEVICE_PREVIEW=false --dart-define-from-file=build/backend-defines.json` эсвэл Xcode Archive хийнэ. Organizer дээр Validate, privacy report, entitlement, signing болон export compliance-ийг нягтална. Зөвхөн дараа нь upload/TestFlight; review submit ба public release нь дахин тусдаа шийдвэр.

## Store Текстийн Ноорог

Доорхыг автоматаар App Store Connect-д submit хийхгүй. Нэрийн боломж, primary language, category болон тайлбарыг эзэмшигч батална. Аппын одоогийн үндсэн UI монгол; listing-ийн locale-ийг App Store Connect-ийн бодит сонголтоос сонгоно.

| Талбар | Ноорог |
|---|---|
| Name | Night Owl UB |
| Subtitle | Places, creators and events |
| Primary category | Social Networking; Lifestyle-ийг secondary болгон нягтлах |
| SKU санал | NIGHTOWL-UB-IOS (өмнө ашиглагдаагүйг шалгана) |
| Keywords | Ulaanbaatar,UB,places,creators,events,nightlife,map,cafe,social |
| Price | Free; IAP/subscription зарлахгүй |
| Privacy URL | `https://nightowl-ub.netlify.app/privacy.html` |
| Support URL | `https://nightowl-ub.netlify.app/support.html` (11-р сарын 3-нд Flutter fallback; зөв static support агуулга нийтлэгдсэнийг шалгасны дараа ашиглана) |
| Contact | Одоогийн support: `osokhe@gmail.com`; review contact-ийн нэр/утсыг эзэмшигч тусад нь өгнө |

Description draft:

> Discover places and creators in Ulaanbaatar with Night Owl UB. Browse a map of local venues, explore venue-linked posts and short videos, follow creators, and save places for later.
>
> Share photos and videos, keep up with the people you follow, and manage who can contact you. Report inappropriate content or block an account from the app.
>
> Night Owl UB is free to use. Venue and event prices are information from organizers; the app does not sell tickets or process payments. Place information may change, so confirm details directly with the venue. The app's main interface is in Mongolian.

Зохиомол creator, баталгаажаагүй газрыг “шалгасан түнш”, хэрэгжээгүй live/call/push, тасалбар, төлбөр, GPS tracking, dating/objectification боломж гэж сурталчлахгүй. Store description нь дээрх боломжуудын бодит native шалгалт PASS болсны дараа л нийтлэгдэх ноорог.

## Privacy ба Насны Ангилал

[Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/)-ийн асуулгыг эзэмшигч бодит binary, сервер, SDK-тай тулгаж бөглөнө. Энэ нь автоматаар submit хийх хариулт биш. Нэг хэрэглэгчийн ID-тай холбогдсон мэдээллийг “unlinked” гэж бүү тэмдэглэ.

| Код/серверээс харагдах мэдээлэл | App Privacy-д нягтлах ангилал / зорилго |
|---|---|
| Имэйл, нэр, username, Auth UUID | Contact Info / Identifiers; account functionality; linked |
| Avatar, photo/video, post/story/reel, comment/review/bio | User Content; app functionality; linked; хэрэглэгч нийтлэхээ сонгодог |
| DM болон group message | User Content / Emails or Text Messages; app functionality; linked; нийтэд зориулагдаагүй |
| Follow, save, interests, settings | Product Interaction / Other Data-д тохирох төрлийг нягтлах; app functionality; linked |
| Pilot session/profile view/directions/follow/save/publish | Product Interaction; analytics; `discovery_activity` нь хэрэглэгчийн ID-тай холбогдоно. Локал client default off; серверийн consent guard migration хүлээгдэж байна |
| Venue check-in | Coarse Location-д хамаарах эсэх; хадгалсан газар + хугацаа нь linked; нарийвчилсан GPS биш |
| GPS, медиа metadata | Төхөөрөмж дээр ашигласан GPS дангаараа server collection биш. Гэхдээ map provider-ийн IP/tile request болон сонгосон видео/зураг дахь EXIF/GPS-ийг network/file шалгалтаар нягталж байж Precise Location-ийн хариуг шийднэ |
| Сервер/SDK-ийн IP, technical logs | Diagnostics, identifiers, retention болон гуравдагч талын зорилгыг бодит тохиргооноос нягтлах |

Settings-ийн “Хэрэглээний статистик” нь сонголттой, default off; зөвхөн `discovery_analytics_consent == true` үед client зөвшөөрсөнд тооцно. Хадгалалт амжилттай болохоос өмнө UI зөвшөөрсөн мэт өөрчлөгдөхгүй. Metadata update нь аккаунт солигдсон үеийн хуучин response-ийг хэрэглэхгүй; шинэ token-ийг хадгална. Серверийн guard SQL суулгаагүй тул public backend дээр consent enforcement хэрэгжсэн гэж үзэхгүй.

IDFA, ATT tracking SDK, advertising/IAP код идэвхтэй харагдаагүй. Энэ нь бүх гуравдагч талын “No Tracking / No Data Collected” баталгаа биш; Supabase, map болон authentication provider-ийн практикийг хамруулна. Font-ууд локал bundle-д орсон, runtime Google Fonts таталт хаалттай. `web/privacy.html`, `legal/PRIVACY_POLICY.md`, бодит серверийн ажиллагаа болон устгалын урсгалыг нийтлэхийн өмнө тулган батална.

`ios/Runner/PrivacyInfo.xcprivacy` нь Runner resources-д холбогдсон. Аппын container дахь түр файл/cache-ийн timestamp хэрэглээнд `C617.1`, аппын өөрийн SharedPreferences хэрэглээнд `CA92.1` reason нэмсэн; эдгээрийг [Apple-ийн required-reason API тайлбар](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)-тай тулгасан. Энэ manifest нь App Privacy асуулга эсвэл “мэдээлэл цуглуулдаггүй” мэдэгдэл биш. Бодит archive-ийн [privacy manifest](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), SDK manifest/signature болон Organizer privacy report-ийг шалгах шаардлага хэвээр.

Шинэ болон өмнөх хэрэглэгчид account setup дээр 18+ өөрийн мэдүүлэг ба community rules зөвшөөрлийг өгнө. `adult_confirmed`, `community_rules_version`, UTC `community_rules_accepted_at` хадгална; guest Explore нээлттэй. Энэ нь нас/иргэний үнэмлэхийн баталгаажуулалт эсвэл App Store rating биш. [Age-rating асуулга](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)-д UGC, messaging, creator контент, alcohol/nightlife зэрэг бодит хэрэглээг үнэн зөв өгч, Apple-ийн ангиллыг батална. Kids category сонгохгүй; нийтлэхээс өмнөх шүүлт ба модерацийн ажиллагааг тусад нь батална.

## Review ба Төхөөрөмжийн Нотолгоо

- [ ] Sign-up/login/reset/logout/account switch; email/Google, идэвхжүүлсний дараа Apple; cancel, offline, expired callback.
- [ ] Camera/photo/location: deny/allow/limited, Settings-ээс буцаах, iPad picker, том видео, upload алдаа, replay/playback, background/resume.
- [ ] Хоёр disposable account: private follow approval, block/DM, profile/place collections, шинэ ба хугацаа дууссан signed media.
- [ ] [In-app account deletion](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion): confirm/cancel, reauthentication, retry, Storage/Auth/FK, Apple revoke; email-only support хангалтгүй. Production аккаунтаар туршихгүй.
- [ ] [UGC safeguard](https://developer.apple.com/app-store/review/guidelines/#user-generated-content): нийтлэхээс өмнөх шүүлт, report-ийг админ бодитоор хүлээн авч боловсруулах, block, нийтэд contact; Terms-д тайлбарласан шуурхай шалгах ажиллагаа, хариуцсан хүн болон escalation урсгалыг бодитоор батлах.
- [ ] Бодит iPhone/iPad screenshot: нэвтрэх, map/place, Feed/Following, creator profile, save/privacy. App Store Connect-ийн одоогийн device-size сонголтод тааруулна; web Device Preview эсвэл зохиомол render-ийг native screenshot гэж ашиглахгүй.
- [ ] Reviewer-ийн өөрийн зөвшөөрөлтэй, ажилладаг non-admin test account ба seed контент; нууц үгийг App Review Information-д шууд эзэмшигч оруулна. Backend review-ийн турш ажиллана.
- [ ] Review notes-д actual navigation, free/no IAP, location optional, privacy/report/deletion замыг үнэн зөв заана. Устгах client зам бэлдсэн ч hosted fulfillment, review credential, contact phone батлагдаагүй тул notes-ийг дууссан гэж үзэхгүй.
- [ ] Encryption/export compliance-ийг binary/dependencies, түгээх улс болон хэрэглэх encryption-тай тулгаж эзэмшигч шийднэ; нотолгоогүйгээр `ITSAppUsesNonExemptEncryption=false` нэмэхгүй.

Эхлээд TestFlight validation/internal testing, дараа нь хэрэглэгчийн зөвшөөрлөөр review submit; эхний release-д manual release санал болгож байна. Бүх checkbox-ийн төхөөрөмж/OS/build ID/огноо/үр дүнг тэмдэглэсний дараа л нийтлэх шийдвэр гаргана.

## Давхар IT / UX / UI review

Өмнөх review-ээр inbox/search/group/profile account scope, post/story draft/publish retry, password recovery/autofill болон responsive form засварууд нэмэгдсэн. Тухайн шатны бүтэн 589 тест, дараах polish-ийн 41 холбогдох тест PASS нь түүхэн үр дүн; хамгийн сүүлийн бүтэн тоо дээр 686 гэж тэмдэглэгдсэн. Дэлгэрэнгүйг [одоогийн release тайлан](RELEASE_READINESS.md)-аас харна. Durable draft, orphan media cleanup, бодит төхөөрөмж/серверийн E2E болон дээрх store саадууд хэвээр; эдгээр засвар production-д deploy хийгдээгүй.

## Өмнөх Бэлтгэлийн Шалгалт

2026-11-03-ны өмнөх шатны түүхэн локал үр дүн (одоогийн нийт тоо биш):

- **589 Flutter тест PASS**, `flutter analyze --no-pub` асуудалгүй, JavaScript web release build PASS. Энэ нь native эсвэл Wasm build биш.
- **132 Python тест PASS**: deployment 34 (үүнд iOS preflight 20), migration 59, venues 24, backend 15. Web startup-ийн **7 Node тест PASS**.
- Source preflight **8/8 PASS**; iOS plist/project syntax болон manifest/resource wiring шалгалт PASS.
- Social discovery, hosted client RPC, featured events, backend readiness-ийн **4 isolated PGlite fixture PASS**; storage/deletion/consent-ийн нэмэлт локал fixture-үүд мөн PASS. Бодит PostgreSQL олон холболтын concurrency болон hosted Auth/Storage integration ажиллуулаагүй.
- Policy link fallback, analytics default off/хадгалалт/account switch, 320px том үсэг, metadata response-ийн account/session guard нь Flutter тестэд хамрагдсан. Нийт 589 дотор орсон тул дээр нь нэмж тоолохгүй.

Локал аудитын лог: `build/audit/2026-11-03/` (Git-д орохгүй). Full iOS preflight / `build_ios.sh` нь Full Xcode байхгүй тул BLOCK; native compile эхлээгүй. Remote CI, signed archive/IPA, төхөөрөмжийн туршилт, TestFlight/upload, review submit хийгээгүй. Энэ удаад Git push/deploy, SQL/function enable, бодит аккаунт устгах, OS/membership өөрчлөх үйлдэл хийгээгүй; public апп нь өмнөх release хэвээр.
