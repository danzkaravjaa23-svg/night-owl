# Night Owl — release бэлтгэл

## 2026-11-03 газрын мэдээлэл ба үйл ажиллагааны эх сурвалж — одоогийн хувилбар

OSM-ийн төв Улаанбаатар дахь хязгаарлагдсан хэсгийг 2026-11-03 12:16:56-д дахин татав: 16,227 эх объект, 270 газар. Нэр, байрлал, ажиллах цаг өөрчлөгдөөгүй; хоёр Facebook tracking query цэвэрлэгдсэн. 33 газарт эх сурвалжийн цаг бий, 237-д байхгүй. Энэ нь хотын бүх газрын хамрах хүрээ эсвэл өнөөдрийн үйл ажиллагааны баталгаа биш.

Яг ID-гаар таарсан 9 газрыг тусад нь нягталсан: нэгэнд огноотой албан эвентийн мэдээлэл, хоёрт нийтэлсэн цаг, зургаад нэмэлт баталгаа шаардлагатай. **261 газар үйл ажиллагааны нягтлалд хамрагдаагүй.** Hops & Rocks, Rosewood-ийн зөрүүтэй мэдээллийг хаагдсан гэж эцэслээгүй, pin шилжүүлээгүй. UB Comedy/Grandkhaan-ийн таамагласан салбарын холбоосыг оруулаагүй. Дэлгэрэнгүй sheet/place хуудас эх сурвалж, огноо, тодорхойгүй төлөвийг харуулна. 30 хоногийн дараа мэдээлэл хуучирсныг тэмдэглэнэ; унших алдаа, огт нягтлаагүй газрыг ялгаж, дахин уншина. Story-ийн гал/нойрмог түвшин нь энэ төлөвөөс тусдаа.

**Баталгаа:** 788 Flutter PASS, analyzer No issues found, 12 OSM converter тест, 13 тусгаарласан PostgreSQL metadata fixture бүлэг, өдөр/шөнийн 390px ба 320px 1.5x дөрвөн бодит widget capture, web release build PASS. Canonical server-ийн эх сурвалжийн metadata refresh амжилттай COMMIT болсон; 2026-11-03 12:28:42-ийн read-only postflight: 270/270 source date шинэ, tracking URL 2 цэвэр, хуучин/дутуу source date 0. Эзэмшигч/админ хянасан мэдээлэл, нэр/байршил/цаг, эрх эсвэл ажиллаж буй төлөвийг өөрчлөхгүй хамгаалалт fixture-д батлагдсан.

Нийтлэлийн бодит commit/hash нь public `/release.json`, delivery receipt нь ignored `build/audit/2026-11-03/venue-refresh/completion.json`. Нарийвчилсан record: `docs/BUILD_VERIFICATION.json` → `venue_refresh`. Үлдсэн нягтлал ба дараалал: [VENUE_REVIEW_HANDOFF.md](VENUE_REVIEW_HANDOFF.md). Хэрэглэгч дахин бичихэд үргэлжлүүлнэ; автомат ажил/сануулга үүсгээгүй. Apple/native/store болон бие даасан PostgreSQL migration өмнөхөөрөө хүлээгдэнэ.

## 2026-11-03 Story location ба газрын зургийн 4 түвшин — өмнөх feature release

Story дээр backend каталогийн газрыг сонгох, солих, хасах үйлдэл нэмсэн. Хайлт нь хуудсалсан, нэр/ref-ээр тогтвортой эрэмбэлэгдсэн, хуучин response-ийг үл хэрэгсдэг, алдаанаас дахин оролдоно. Сонгосон OSM газар UUID-гүй ч зөв идэвхтэй харагдана; backend-д байхгүй bundled-only газарт хиймэл foreign key үүсгэхгүй.

Өнөөдрийн танд харагдах, хугацаа дуусаагүй story-ийн тоогоор map дээр **0 — Нойрмог, 1–4 — Сэрж байна, 5–14 — Идэвхтэй, 15+ — Галтай** хөдөлгөөнт тэмдэг харуулна. Өдрийг Asia/Ulaanbaatar-ийн 00:00-оос тоолж, ирээдүйн/хугацаа дууссан story болон banned author/requester-ийг шүүнэ. Security INVOKER RPC нь одоогийн story RLS-ийг хэвээр ашиглана; private/blocked story-ийн эрхийг өргөжүүлээгүй. Эдгээр нь бодит хүн, ажиллах цаг эсвэл GPS баталгаа биш. Map-д нэгтгэсэн UUID/OSM газрын story refs алдагдахгүй, давхардахгүй.

Animation нь нэг paint clock-оор хоёр зөөлөн цикл хөдөлнө; map/tiles-ийг frame бүрээр rebuild хийхгүй. Reduced motion болон далд map/app-д зогсоно. Тоолол 60 секунд дотор, expiry/midnight болон resume үед шинэчлэгдэнэ; background polling зогсоно. Session/privacy өөрчлөгдөх эсвэл ачаалалт/алдааны үед өмнөх тоо далдлагдана; нээлттэй cluster sheet-ийн хуучин тоо мөн хаагдана. Сүлжээний алдааг 0 story гэж харуулахгүй.

**Баталгаа:** бүтэн **756 Flutter PASS**, analyzer **No issues found**, **17 SQL fixture бүлэг**, **8 өдөр/шөнийн 390px/320px 1.5x бодит widget capture**, web release build PASS. Зохиомол venue бүхий capture-ууд нь production хүний мэдээлэл биш. Backend migration SHA256 `c8240d7f736c7dfdb671e2069d88163dbb3f35cdf3cd4111dcfb1c6512686fed` production дээр COMMIT болсон; embedded assertions болон 2026-11-03 11:48:39 (Улаанбаатар)-ийн source-body MD5/RLS/ACL/index postflight бүгд PASS. Бодит anonymous RPC HTTP200, тухайн үед идэвхтэй story-той газрын мөр 0 байв. Шалгалтаар хэрэглэгчийн story нийтлэх/устгах DML хийгээгүй.

Аппын нийтлэлийн бодит commit болон JS hash: public `/release.json`. Нарийвчилсан шалгалт `docs/BUILD_VERIFICATION.json` → `story_map_activity`; локал ZIP болон completion нотолгоо `build/audit/2026-11-03/story-map/`. Apple/native/signing/store gate хэвээр.

## 2026-11-03 дахин аудитын засвар — өмнөх release

17 илэрсэн доголдлыг зассан. Нэмж Notes-ийн “найзууд харна” тайлбарыг серверийн харилцан дагалтын дүрэм, 24 цагийн expiry-тэй нийцүүлсэн. Аккаунттай холбоотой no-op/stale draft, DM уншсан төлөв, Saved map, Reels болон video lifecycle-ийг regression тестээр шалгасан.

**Шалгалт:** 732 Flutter PASS, analyzer алдаагүй, 95 Node, 34 deployment Python, 59 migration-tool Python, 15 backend Python; 22 interaction SQL болон 24 admin SQL бүлэг PASS. Production web build, ZIP CRC шалгалт амжилттай. SQL fixture нь яг нийтлэх atomic bundle-ийг ажиллуулж, эцсийн assertion унахад өмнөх DDL rollback болдгийг баталсан.

**Серверийн rollout:** 2026-11-03 10:56:58 (Asia/Ulaanbaatar) хамгаалалт чангатгах тусдаа atomic bundle амжилттай хэрэгжив: storage/account guards, consent gate, interaction/Notes/check-in/identity/TRUNCATE хамгаалалт. SHA256 `eaf4b46ced52973471e7a7d2acab5df59f66a13feaad80e8ea4889250e080478`. Bundle-ийн prerequisite/final assertions COMMIT-ээс өмнө PASS; дараах read-only production query нь Notes/profile guard, RPC-only check-in, public-table TRUNCATE хаалт, direct profile DELETE хаалт идэвхтэй, өмнөх media-read дүрэм өөрчлөгдөөгүйг баталсан. 25 interaction policy суусан. Existing application/Auth/Storage мөр устгах DML ажиллуулаагүй.

Хамгаалалтын тусдаа builder нь 003-аас зөвхөн client EXECUTE эрхгүй invoker maintenance predicate авч, 004-ийн admin-action existence prerequisite-ийг хассан; өөр хамгаалалтыг сулруулаагүй. Яг энэ artifact-ийн 10 SQL бүлэг, idempotence, rollback, хэвийн upsert/check-in болон дараа нь бүтэн bundle суух нийцэл PASS. `tools/deployment/security_restriction_release.mjs`-ээр дахин гаргана. Hosted recovery schema metadata public artifact-аас тусдаа хадгалагдсан.

**Админ backend идэвхжүүлсэн:** хэрэглэгч private post/comment болон хавсаргасан post media-ийн хяналтын эрхийг тодорхой зөвшөөрсний дараа бүтэн atomic bundle SHA256 `b9b1d72f012ecf3601f9cdf67a5d7732f7ff3327573f835b513cc7072804e55e` production дээр амжилттай COMMIT болсон. Өмнөх restriction subset-ийн дээр суусан; бүх embedded assertion PASS. 2026-11-03 11:15:43 (Asia/Ulaanbaatar)-ийн read-only postflight нь 6 admin RPC, schema/search-path/ACL, private action context, шууд хандах боломжгүй append-only audit болон interaction хамгаалалтыг баталсан. Байхгүй хэрэглэгчийн synthetic authenticated claim-тай 5 read RPC хүсэлт `42501`-оор хаагдсан; бодит anonymous HTTP-ийн 7 хүсэлт `401 / 42501`-оор хаагдсан. Одоо байгаа 5 идэвхтэй админы эрх ашиглагдана; шинэ админ аккаунт олгоогүй, шалгалтаар хэрэглэгчийн content-д moderation бичилт хийгээгүй. Recovery metadata, postflight JSON болон API нотолгоо: `build/audit/2026-11-03/admin-activation/`.

Production дээр админ болж нэвтрээд content өөрчлөх E2E хийгээгүй: одоогийн browser login community-rule setup руу орж байгаа бөгөөд хэрэглэгчийн өмнөөс гэрээ/насны нөхцөл зөвшөөрөөгүй. Энэ нь серверийн rollout-ийг хаахгүй; бодит moderation-ийн эцсийн UX баталгааг тусад нь хийнэ.

**Нийтлэл:** app commit `5e8fdde247041a3e8a3fa7c9e771da38b62d25a0` GitHub `night-owl-features` дээр push хийгдсэн; баримт бичгийн `6673147326f4e82167f90744166880a543922696` commit-ийн Netlify deploy `6ae94df360692ac1ca8edf0c` Published болсон. App код ижил. Public JavaScript SHA256 `ea02e7657748a285f677d986450fe443a0680df6fae84e7b507af36b1d9e7b8e` локал шалгасан build-тэй byte бүрээрээ таарсан. Public support/policy/admin HTML нь Netlify-ийн badge/notice болон pretty-URL хувиргалтыг тооцсоны дараа агуулга/бүтцээрээ таарсан. Guest browser дээр Explore map/list/Saved, 279 газар (270 байршилтай), event/video хэсгийг шалгаж, error/warning log хоосон байсан. Public `/release.json` нь тухайн нийтлэлийн commit болон JS SHA256-ийг харуулна; эцсийн баримт бичгийн commit app кодыг өөрчлөхгүй. Нарийвчилсан төлөв: `docs/BUILD_VERIFICATION.json` → `audit_repairs`; нотолгоо `build/audit/2026-11-03/release-fixes/`. Apple/native/signing/store болон disabled account-deletion Edge Function-ийн үлдсэн gate хэвээр; store submission-д бүрэн бэлэн гэсэн дүгнэлт биш.

Доорх хэсгүүд өмнөх ажлын үеийн баримт; дээрх current record нь хамгийн шинэ шалгалт юм.

## 2026-11-03 нэгдсэн админ ба аюулгүй байдал — өмнөх локал build

Өмнө байсан админ панелийг сайжруулж **Profile / Settings → Админ панел** замаар апп дотор нэгтгэв. Код болон JavaScript web release локалд бэлэн. **Шинэ серверийн migration суулгаагүй, live deploy, аккаунтад админ эрх олгох, Git push хийгээгүй.** Өмнөх Supabase болон үнэгүй аппын тохиргоо хэвээр.

- **Удирдлага:** гомдлын дараалал, хайлт/хуудсалсан хэрэглэгчид, ban/unban, verification, нийтлэл/сэтгэгдэл хянах, үйлдлийн түүх. Featured event, pilot болон газар шалгах хуучин урсгалыг нэгдсэн эрхийн хамгаалалттай холбосон. Веб админ мөн шинэчлэгдсэн.
- **Эрхийн хамгаалалт:** дэлгэц нээхээс өмнө сервер идэвхтэй админ эсэхийг шалгана; хүсэлт тухайн session-ийн токентой. Аккаунт солигдох, шинэ login, эрх цуцлагдах үед өмнөх контент болон нээлттэй цонх далдлагдана. Буцаж нээсэн админ дэлгэц эрхээ дахин батална. Migration байхгүй бол тохиргоо дутууг ил тод харуулна.
- **Модераци:** шалтгаан шаарддаг RPC нь өөрчлөлт, холбогдох гомдлын шийдвэр, audit мөрийг нэг transaction-д хийж, буцсан receipt-ийг клиент шалгана. Давхар даралт, хожим ирсэн хариу, буруу target/report, амжилттай мэт no-op болон тодорхойгүй timeout-ийг хамгаалсан. Админ эрх олгох клиент үйлдэл, бүх DM унших хэсэг байхгүй.
- **Серверийн локал хамгаалалт:** private action context, profile privilege ба report write guards, report давтамж/давхардлын хязгаар, өөрчлөх/устгах client эрхгүй audit хүснэгт, legacy venue/event/pilot өөрчлөлтийн audit. Хувийн post media-д зөвхөн review хийх боломжтой мөртэй холбогдсон объектын нарийн эрх нэмсэн; DM/Story-ийн бүх объектыг нээгээгүй. DB оператор DDL өөрчлөх боломжтой тул audit-ийг бүрэн tamper-proof гэж үзэхгүй.
- **Харагдах байдал:** navy/lavender өнгө, өдөр/шөнийн гадаргуу, 44px удирдлага, алдаа/хоосон/дахин оролдох төлөв; 320px том бичвэрт мөрүүд тасрахгүй, гүйлгэн хүрнэ. Privacy тайлбарт админы контент хяналт болон audit өгөгдлийн хүрээг тусгасан.

**Шалгалт:** бүтэн **686 Flutter тест PASS**, анализ **No issues found**, **24 PGlite SQL шалгалтын бүлэг**, **29 веб админ Node тест**, **34 deployment Python тест PASS**. **20 Flutter capture case → 20 PNG** (390px ба 320px / 1.5×, өдөр/шөнө), **5 офлайн Chrome screenshot** шалгасан. Эдгээр нь зохиомол өгөгдөлтэй локал шалгалт; hosted authorization/concurrency, production хэрэглэгч эсвэл native төхөөрөмжийн E2E биш.

Нотолгоо: `build/audit/2026-11-03/admin-security/`; дүрслэлийн тойм `index.html`; веб Chrome нотолгоо `build/audit/2026-11-03/admin-refresh/`.

- Web ZIP: `build/releases/night-owl-admin-security-2026-11-03.zip` — **89 файл, 22,905,036 byte**; SHA256 `5c984355248ecf6e0b7a3408583797b1e5f88960ce7626a99c92a97c2a14e922`.
- Backend ZIP: `build/releases/night-owl-admin-backend-2026-11-03.zip` — **7 файл, 16,256 byte**; дөрвөн pending SQL, preflight/postflight, admin заавар. SHA256 `97930fafdf633df5f9dccb04b31b30a879007132d53a7ac2311e41802283fde6`.
- ZIP CRC болон файл бүр эх build/source-той таарсан. Дөрвөн public support/policy хуудас, generated admin client шалгагдсан. Файлын нэр/private-key marker smoke check нь бүрэн secret audit биш.

**Rollout үлдсэн:** одоо суусан social/featured backend prerequisite-ийг нягталж, дөрвөн pending migration-ийг timestamp дарааллаар disposable hosted staging дээр шалгана. `202611030003_admin_console.sql` нь `202611030001_account_deletion_boundaries.sql`-ийн хамгаалалтгүй бол суухгүй. `admin_console_preflight.sql`-ийг 003-ийн өмнө, `admin_console_postflight.sql`-ийг дараа ажиллуулна. Бодит admin/member/banned session, private media, legacy owner flow болон олон холболтын concurrency-г баталсны дараа сервер/client rollout хийнэ; хуучин root SQL-ийг бөөнөөр дахин ажиллуулахгүй. [Админ заавар](../web/admin/README.md), [submission checklist](APP_STORE_SUBMISSION.md)-ийг дагана. Disabled deletion function, Apple тохиргоо, native build/signing/төхөөрөмж, нийтлэхээс өмнөх контент шүүлт болон модераторын бодит хариу ажиллагаа тусдаа үлдсэн.

## 2026-11-03 UX/UI шинэчлэлт — өмнөх build

Night Owl-ийн owl брэнд, midnight navy / lavender өнгийг хадгалж, гол дэлгэцүүдийн мэдээллийн дараалал, 20px зай, үйлдлийн харагдах байдал, өдөр/шөнийн гадаргууг нэг стандарттай болголоо. **Код болон шинэ JavaScript web build локалд бэлэн; live deploy хийгээгүй.**

- **Feed / Explore:** цэгцтэй гарчиг ба шүүлтүүр, 4:3 зурагтай карт, тодорхой хайлт/ангилал, эвент-бичлэг рүү орох хэсэг. Том бичвэртэй үед газрын жагсаалтад хангалттай зай үлдээнэ; map state, clustering болон байршлын логикийг хадгалсан.
- **Профайл / тохиргоо:** уншигдах identity, үйлдлүүд, media grid, тайлбартай хоосон төлөв; appearance сонголтын жижиг preview, нууцлал/мэдэгдлийн бүлэг. Томруулсан бичвэрт таб ба горимын нэрийг таслахгүй, босоо мөрөөр харуулна.
- **Мессеж / хайлт / мэдэгдэл:** тод гарчиг, ойлгомжтой unread төлөв, харагдах focus, keyboard нээгдсэн үеийн хайлт ба retry. Одоогийн account/session хамгаалалтыг хадгалсан.
- **Нийтлэг UX:** 44px-аас багагүй жижиг primary/icon товч, busy үед үйлдлийн нэр хэвээр, бага өндөртэй recovery төлөв scroll-оор хүрэх боломжтой. Navigation ба үүсгэх цонхны keyboard ажиллагаа, focus хүрээ, том бичвэрийн байрлалыг зассан. Горимын эффект брэндийн нил ягаан өнгөтэй, тогтсон төлөвт тасралтгүй animation ажиллуулахгүй.

**Баталгаа:** бүтэн **636 Flutter тест PASS**, анализ **No issues found**, JavaScript release build PASS. **36 тусдаа capture case PASS → 48 PNG**: жишээ өгөгдөл, bundled font/icon/зурагтай бодит widget-үүд; 390px болон 320px / 1.5× бичвэр. Гол төлөөлөх хувилбаруудыг дүрслэлээр шалгаж, илэрсэн font/avatar/таб/жагсаалтын viewport/төвийн нэмэх icon-ы асуудлыг засаж дахин дүрсэлсэн. 2× бичвэр, keyboard/focus/retry үйлдлүүд автомат тестэд хамрагдана. Эдгээр нь production хэрэглэгч, live map tile, browser эсвэл бодит төхөөрөмжийн E2E биш.

- Тойм: `build/audit/2026-11-03/visual-refresh/index.html`
- Лог, manifest: `build/audit/2026-11-03/visual-refresh/`
- Web ZIP: `build/releases/night-owl-ux-refresh-2026-11-03.zip` — **89 файл, 22,890,482 byte**. CRC болон archive-ийн файл бүр build/web-тэй таарсан. SHA256: `955cef5825c840ac05ad2038ad1edf9119bf8852b593016be33d5bf005192f71`.
- `main.dart.js` SHA256: `b70d9f655af1390fe9c28c1a7e39ae2f2d47eed383a1f4386d72887f5e152d66`.

Сервер, төлбөр, PostgreSQL migration болон Apple тохиргоог энэ UI ажлаар өөрчлөөгүй. Өмнөх API/backend staging, native build/signing, төхөөрөмжийн шалгалт болон App Store-ийн gate-ууд хэвээр. Git push/deploy хийгээгүй.

## 2026-11-03 GPT-6 Astra / ultra review — өмнөх API бэлтгэл

Хэрэглэгчийн хүссэн **GPT-6 Astra, ultra** тохиргоотой хоёр бие даасан review-ээр Auth/нийтлэх transport болон серверийн SQL/устгалын кодыг нягталж, групп чат, эвентийн урсгалыг давхар засаж нэгтгэв. **Код ба JavaScript web build локалд бэлэн; production болон App Store-д нийтлээгүй.** Өмнөх дизайн, үнэгүй горим, Supabase ашиглах шийдвэр хэвээр.

- **API / session:** post/story insert ба duplicate lookup нь тухайн session-ийн токентой шууд HTTP ашиглана. Хугацаа дууссан хуучин хүсэлт SDK-ийн refresh-ээр шинэ login-ийг сольдог замыг хаав. Authorization header-ийн давхардсан casing болон буруу олон мөртэй duplicate хариуг зассан.
- **Групп чат:** өөр аккаунт, шинээр нэвтрэх, өөр группийн route-д хуучин мессеж/ноорог/гишүүний цонх үлдэхгүй. Token refresh нооргийг хадгална. Илгээх явцад текстийг солихгүй; алдаа/удаан хүсэлтэд ноорог үлдэж, тодорхойгүй үр дүнг амжилт гэж харуулахгүй. 20 секундын хязгаар, account-bound member actions, retry хайлт, шууд холбоосын буцах зам нэмэгдсэн.
- **Эвент:** UTC+8 цагийг серверт UTC гэж андууран илгээхийг засав. Ирээдүйн огноо/үнэ/талбар шалгана; зураг, тайлбар, газар нь нийтлэх үед тогтмол. Cover upload алдах нь зураггүй эвент нийтлэхгүй. Тодорхойгүй хариуг нэг ID/нэг payload-аар дахин батална. Session солигдоход ноорог болон хувийн газрын picker цэвэрлэгдэнэ.
- **Оролцох төлөв (RSVP):** давхар даралт сериал ажиллана; серверийн тоо/өөрийн төлөвийг дахин уншиж батална. Сүлжээний алдаа, буруу count хариуг 0 оролцогч гэж харуулахгүй; дахин оролдох боломжтой.
- **Серверийн устгал:** remove-ийн амжилттай no-op эсвэл буруу response дангаараа амжилт болохгүй. Auth устгахаас өмнө дөрвөн bucket-ийн хэрэглэгчийн prefix бүгд хоосон эсэх, дараа нь устгасан user ID-г шалгана. Storage RLS-д цэвэрлэх боломжгүй хоосон/trailing path segment-ийг хориглов. Энэ нь зэрэг upload-ийг lock хийдэг атомик transaction биш; handler идэвхгүй хэвээр.
- **Багц:** Finder-ийн `.DS_Store` файлыг public build-ээс хасдаг болгож, web ZIP болон серверийн staging ZIP-ийн CRC/файл бүрийн SHA256-г шалгав.

**Баталгаа:** бүтэн **625 Flutter тест PASS** (өмнөх 589 + 36); анализ **No issues found**; **66 Node** устгалын тест, **Deno typecheck +13 pinned-SDK loopback алхам**, **7 тусгаарласан SQL fixture**, **34 Python deployment тест**, **8/8 iOS source preflight PASS**. Нэмэлт focused 66/12/19 тест нь 625-д орсон, дээр нь нэмж тоолоогүй. Лог: `build/audit/2026-11-03/astra-pass/`; Deno / 7 SQL-ийн үр дүн agent tool output-д хадгалагдсан, тусдаа log файлгүй. Бодит production/төхөөрөмжийн E2E гэсэн утгатай биш.

Локал багцууд:

- `build/releases/night-owl-astra-reviewed-2026-11-03.zip`: **89 файл, 22,818,207 byte**; JavaScript release. `main.dart.js` SHA256: `105977ed474b10e9ff522a3de5954455d94a5d0381b56718917293c727fabc91`.
- `build/releases/night-owl-astra-backend-2026-11-03.zip`: **6 файл, 10,703 byte**; гурван pending migration, disabled handler/заавар, hash бүхий staging manifest. Production-д суулгасан гэсэн үг биш.

**Үлдсэн бодит хязгаар:** шинэ SQL/function-ийн hosted staging, legacy/FK/recovery, зэрэг upload/устгал, Apple revoke; Xcode/iOS SDK, native compile/бодит төхөөрөмж, signing/Apple provider/store, moderation болон public policy/support rollout шаардлагатай хэвээр. Draft ба recovery ID санах ойд байдаг; orphan cleanup worker байхгүй. Group timeout нь серверийн хүсэлтийг цуцлахгүй, exactly-once мессежийн баталгаа биш. Git push/deploy, production бичилт, OS/Apple enrollment энэ удаад хийгээгүй. [Нарийвчилсан receipt](BUILD_VERIFICATION.json)-ийн `astra_api_readiness` болон [store бэлтгэл](APP_STORE_SUBMISSION.md)-ийг харна.

## 2026-11-03 IT / UX / UI давхар review — өмнөх бэлтгэл

Хэрэглэгчийн дараагийн хүсэлтээр профайл, хайлт, inbox, мэдэгдэл, нийтлэх болон нууц үгийн урсгалыг дахин review хийж, бодитоор давтагдсан алдааг засав. Өмнөх дизайн/хамгаалалтын ажлыг хадгалсан. Энэ хэсэг нь доорх өмнөх бэлтгэлийн audit-аас хойших өөрчлөлтийг тайлбарлана.

- **Аккаунтын тусгаарлалт:** inbox, мэдэгдэл, хайлтын хуучин мөр/ноорог, групп үүсгэх сонголт өөр аккаунтад үлдэхгүй. Query A → B → A үед анхны A хариу шинэ хайлтыг дардаг зөрчлийг request хувилбараар хаав. Хоцорсон группийн хариу шинэ session-д навигац хийхгүй; token refresh нь зөв session-д ажиллана.
- **Мэдэгдэл ба inbox:** дэлгэц нээх нь бүх мэдэгдлийг автоматаар уншсан болгохгүй. Тодорхой унших үйлдэл давхардахгүй; серверийн алдаа unread төлөвийг хадгалж, retry харуулна. Группийн хүсэлт алдахад ажиллаж буй DM жагсаалт хэвээр, retry баннертай үлдэнэ. Группийн нэрээр хайна.
- **Профайл:** cover picker-ийн давхар нээлт, cancel/error/disposal болон аккаунт солигдсоны дараах upload/PATCH-ийг засав. Сервер үнэхээр профайлын мөрийг өөрчилснийг батална. Сүүлийн хуудсанд хүрсний дараа refresh retry ажиллана; устгасан пост хуучин refresh-ээс дахин нэмэгдэхгүй. Буруу username-ийн талбарт фокус/scroll очиж, алдаа харагдана.
- **Post / Story:** нийтлэх хүсэлт эхэлсний дараа медиа, тайлбар, газрын immutable snapshot ашиглана. Post-ийн хэмжээ 50 MB bucket лимиттэй таарсан. Picker цуцлах/алдах нь өмнөх draft-ийг устгахгүй. Давхар илгээлт, аккаунт солигдсоны дараах insert-ийг хаав; батлагдаагүй publish-ийг ижил UUID-аар дахин шалгаж, нэг дэлгэцийн retry давхар пост үүсгэхгүй. Зөв MIME/JPEG, видео үргэлжлэх хугацаа, timeout ба overlay бэлдэх алдааг ил тод болгосон. Гарахад draft хаяхыг асууна.
- **Нууц үг:** өөрчлөх/сэргээх нь metadata-тай ижил owner/session хамгаалсан transport ашиглана. Хуучин response шинэ аккаунт/session-ийг солих эсвэл logout хийхгүй. Найман тэмдэгтийн нэг ижил шалгалттай; зөвшөөрөгдсөн серверийн алдааг аюулгүй, ойлгомжтой харуулна. Autofill-д зөвхөн сервер баталсан нууц үгийг хадгална. Шинэ recovery холбоос хуучин draft-ийг цэвэрлэж, шинэ session-д зөв холбогдоно; fresh sign-in нь хуучин recovery redirect-ийг зогсооно. Native сэргээх холбоос тохирох app callback ашиглана.
- **UX/UI:** гурван password дэлгэц нэг scroll/focus/layout стандарттай, keyboard/320px/том текстийн үед хүрэх боломжтой. Хамгийн бага уртын зааврыг тайрах placeholder-оос тусдаа бүрэн текст болгов; contrast, семантик label, show/hide tooltip, continuous aura дэвсгэрийг сайжруулав. Onboarding дуусмагц ажиллахгүй push delivery-д зориулсан browser permission асуухгүй; байршлыг газрын зураг дээр тухайн үйлдлийн үед асууна.

**Баталгаа:** бүтэн **589 Flutter тест PASS** (өмнөх 504-өөс 85 нэмэгдсэн); сүүлийн copy/visual polish-ийн дараах холбогдох **41 тест PASS**; `flutter analyze --no-pub` **No issues found**. Энэ нь хоёр нэмэлт PNG capture тесттэй нийлүүлэн тоолсон тоо биш. Бодит bundled Inter, Material icons-тай өдөр/шөнийн хоёр password PNG-г root хараад баталсан; 320px / 1.5x текст орсон. Эдгээр нь зохиомол local widget fixture болохоос browser/native төхөөрөмжийн нотолгоо биш. Командын лог ба receipt: ignored `build/audit/2026-11-03/ux-pass/`.

Web release ZIP: `build/releases/night-owl-professional-ux-2026-11-03.zip` (**89 файл, 22,881,778 byte**). CRC болон архивын бүх файл build-тэй ижил; дөрвөн public хуудас source-той таарсан. `main.dart.js` SHA256: `41a51ccc90450455c751baeea8337a0ee5d8377e9591b96d412de66a8fc51880`. Нарийвчилсан receipt: [BUILD_VERIFICATION.json](BUILD_VERIFICATION.json)-ийн `professional_ux_audit`. ZIP нь native installer биш, нийтлээгүй.

**Хүрээний хязгаар:** draft ба pending publish UUID нь одоогоор тухайн дэлгэцийн санах ойд байна; refresh/reload/хаасны дараа сэргээдэг durable draft биш. Дэлгэцээс гарах нь серверт эхэлсэн хүсэлтийг цуцлахгүй. Тасалдсан upload orphan файл үлдээж болно; аюултай cleanup автоматаар хийгээгүй. Бодит Auth/Storage/browser/mobile формат, төхөөрөмжийн keyboard/autofill/password-provider, moderation болон native signing-ийн E2E шалгалт үлдэнэ. Өмнөх pending SQL/deletion/Apple/Xcode саадууд хэвээр. Энэ pass шинэ schema, live migration, production бичилт, deployment эсвэл Git commit/push хийгээгүй.

## 2026-11-03 Apple Developer-ийн өмнөх audit — өмнөх бэлтгэлийн багц

**Локал код, UI болон web build шалгагдсан. App Store submission хараахан бэлэн биш.** Доорх огноотой хэсгүүд нь түүхэн тэмдэглэл; одоогийн төлөвийг энэ хэсэг болон [submission багц](APP_STORE_SUBMISSION.md) тодорхойлно. Supabase хэвээр, апп үнэгүй. Энэ audit production өгөгдөл, migration, function, Git push, deployment, OS эсвэл Apple бүртгэлийг өөрчлөөгүй.

### Зассан зүйлс

- **Нэвтрэлт ба аккаунт:** email/Google/Apple хүсэлтүүд давхар эхлэхгүй; хожим ирсэн metadata response өөр аккаунтын session-ийг солихгүй. Google/Apple ашигласан шинэ болон хуучин хэрэглэгчид setup дээр одоогийн 18+ community дүрмийг батална. Хувилбар, UTC хугацааг хадгална; энэ нь өөрийн мэдүүлэг бөгөөд нас баталгаажуулалт биш. Бүртгэлгүйгээр нийтэд нээлттэй газруудыг үзнэ.
- **Жижиг дэлгэц ба дизайн:** login/register/Reels-ийн 320px, том текстийн халилт; followers/following-ийн хуучин жагсаалт, retry ба private follow хүсэлтийн буруу төлөвийг засав. Удирдлагын хүрэх талбай, сонгогдсон төлөвийн accessibility тайлбарыг сайжруулав. Намхан desktop цэс гүйлгэнэ. Өдөр/шөнийн үндсэн owl брэнд хэвээр.
- **Хүлээлт ба гүйцэтгэл:** апп ард ороход presence хүсэлт зогсоно, буцаж нээхэд шинэчлэгдэнэ; давхар heartbeat үүсэхгүй. Ашигладаг 10 фонтын файлыг лиценз, checksum-тай нь багцалж, runtime Google Fonts таталтыг хаав. Story-ийн Latin-only фонт Монгол үсэгт Inter fallback ашиглана. Төхөөрөмж дээр FPS/санах ойн хэмжилт хийгдээгүй.
- **Нууцлал:** хэмжилт анхнаасаа унтраалттай, Settings-ээс зөвшөөрч/цуцална. Клиент зөвхөн яг boolean `true` үед илгээнэ. Шинэ серверийн migration мөн authoritative Auth consent шалгана; **энэ migration live дээр суулгагдаагүй** тул нийтлэхээс өмнө серверийн хамгаалалтыг суулгаж шалгах шаардлагатай. Зөвшөөрөл цуцлах нь өмнөх мөрүүдийг автоматаар устгахгүй. Бүрэн бодлого/нөхцөл/тусламжийг нээдэг холбоос, алдааны contact fallback, лицензийн дэлгэц нэмэв.
- **Устгал ба Storage:** profile-ийг шууд DELETE/TRUNCATE хийх тойруу зам, хэрэглэгчийн медиа URL-д итгэдэг privileged cleanup trigger-ийг локал SQL-аар хаав. Setup/settings-ийн баталгаажуулалттай устгал, malformed Storage list ба partial failure хамгаалалт, logout-ийн хугацааны хязгаар нэмэв. Хуучин bucket setup private медиа bucket-ийг дахин public болгохгүй. **Шинэ SQL/function production-д суулгаагүй.** Apple revoke, бодит Auth/Storage/FK/recovery болон зэрэг upload/устгал хүлээгдэнэ.
- **iOS бэлтгэл:** шаардлагын шалтгаант app privacy manifest (`C617.1`, `CA92.1`) Runner resources-д орсон; bundle ID/entitlement ба manifest-ийн preflight нэмэгдэв. Ашигладаггүй Android microphone permission-ийг хасав. CI нь шинэ SQL хамгаалалтыг шалгаж, дутуу build artifact дээр алдана. Manifest source зөв байх нь archive/privacy label баталгаажуулалт биш.

### Шалгалтын нотолгоо

| Шалгалт | Үр дүн ба хүрээ |
|---|---|
| Flutter regression | **504 PASS**, `flutter test --no-pub`; бодит аккаунт/төхөөрөмж биш |
| Static analysis | `flutter analyze --no-pub`: **No issues found** |
| Offline tooling | **132 Python**, **7 web-startup Node** тест PASS |
| Deletion handler | **52 Node** тест, Deno typecheck ба жинхэнэ pinned SDK-тай **8 loopback алхам** PASS; hosted integration биш |
| SQL | **7 тусгаарласан PGlite fixture** PASS: social, hosted RPC, featured events, backend readiness, Storage guard, deletion boundary, analytics consent; production болон PostgreSQL concurrency биш |
| Dependency advisory | Түгжигдсэн **214 hosted Pub dependency**-г official OSV-ээр шалгахад мэдэгдсэн тааралтгүй; engine/native/edge dependency-ийн бүрэн баталгаа биш |
| Native source | Preflight source **8/8**, Python preflight regression **20**, plist/project lint PASS |
| Web | JavaScript **release build PASS**; Wasm release биш |
| iOS build | Wrapper **BLOCK / exit 1**: full Xcode байхгүй. Runner.app/IPA бүтээгээгүй |

Web ZIP: `build/releases/night-owl-pre-apple-audit-2026-11-03.zip` (**89 файл, 22,871,015 byte**). CRC болон архивын файл бүр build-тэй таарч байгааг шалгасан; дөрвөн public хуудас эцсийн source-той ижил. `main.dart.js` SHA256: `c6e6a4e0610ff52217851d423cb095358b54b240f9bcac26cba86590f029d4f0`. Энэ нь native аппын installer биш.

Дэлгэрэнгүй машинд уншигдах баримт: [BUILD_VERIFICATION.json](BUILD_VERIFICATION.json)-ийн `pre_apple_audit`. Командын лог, эхлэх үеийн worktree diff, зохиомол UI дүрслэл ба release ZIP нь ignored `build/audit/2026-11-03/`, `build/releases/` дотор байна. Эхлэхэд байсан өөрчлөлтийг хадгалж, audit-д хамруулсан; Git commit/push хийгээгүй.

### Нийтлэхээс өмнө үлдсэн бодит саад

1. **Native орчин:** macOS 15.5 / CommandLineTools; full Xcode 26+ болон iOS SDK хэрэгтэй. Нийцэх macOS/Xcode сонгож, unsigned build, simulator/бодит iPhone дээр permission/login/upload/playback/удаан сүлжээ/account switch-ийг шалгана. `geolocator_apple`-ийн SPM build-д foreground-only authorization macro үнэхээр үйлчлэхийг archive-аар нягтална.
2. **Backend staging:** `202610220001_storage_account_guards.sql`, `202611030001_account_deletion_boundaries.sql`, `202611030002_discovery_analytics_consent.sql` болон disabled deletion handler-ийг disposable staging дээр шалгана. Legacy binary/JSON/FK өгөгдөл, recovery, хуучин JWT, зэрэг upload/устгал ба Apple grant revoke шийдэгдээгүй. Нэг постын orphan binary cleanup worker тусдаа үлдсэн.
3. **Нэвтрэлт ба public хуудас:** 2026-11-03 read-only шалгалтаар Apple provider **false**, Google/email **true**; `delete-account` GET **404**; `support.html` HTTP 200 боловч Flutter app-shell fallback байсан. Шинэ хуудсуудыг дараагийн deployment-ээр нийтэлж, бодит хуудас/холбоосыг шалгана. GET нь устгалын POST ажилладаг гэсэн баталгаа биш.
4. **Store ба moderation:** бодит нийтлэхээс өмнөх UGC шүүлт, report-ийн хариу ажиллагаа, reviewer account, privacy/age-rating мэдүүлэг ба device screenshot хэрэгтэй. Apple Developer/team/signing/App Store Connect/IPA/upload одоогоор батлагдаагүй. [Apple Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [SDK шаардлага](https://developer.apple.com/news/upcoming-requirements/).

Энэ багцыг шууд production-д нийтэлсэн эсвэл App Store зөвшөөрөхөд бэлэн гэж тайлагнахгүй. Дараагийн аюулгүй дараалал: staging хамгаалалт ба бодит устгал → web нийтлэлт → native төхөөрөмжийн баталгаа → signing/store review.

## 2026-10-22 Үнэгүй бэлтгэлийн үргэлжлэл (түүхэн)

Эзэмшигчийн хамгийн сүүлийн чиглэлээр Apple-ийн төлбөр/гишүүнчлэлийг түр үлдээж, боломжтой локал ажлыг үргэлжлүүлэв. Доорх нь одоогийн төлөв; түүнээс дооших огноотой audit-ууд нь тухайн үеийн түүхэн нотолгоо.

- Settings болон профайлаа дуусгаагүй setup-ээс `/settings/delete-account` нээгдэнэ. Үр дагаврын checkbox, эцсийн confirm/cancel, busy/алдаа/амжилтын төлөвтэй. Нэвтрээгүй хүн эхлээд login хийж буцна. Аккаунт солигдох, A→B→A болон дэлгэц хаагдсаны дараах хариу өөр аккаунтыг logout хийхгүй.
- Клиент caller bearer + зөвхөн `confirmation=DELETE` илгээнэ; server-ийн strict success + тохирох user ID-гүй бол устгасан гэж хэлэхгүй. Timeout/тасалдалд устгал үргэлжилсэн байж болохыг тайлбарлана, автоматаар дахин устгахгүй.
- Handler нь `ACCOUNT_DELETION_ENABLED=true` биш бол хаалттай; default идэвхгүй. Auth алдаатай user object-ийг зөвшөөрөл гэж үзэхгүй. Бүх bucket-ийг жагсааж дуусаад cleanup эхэлнэ; хожуу жагсаалтын алдаа өмнөх медиа устгахгүй. Partial cleanup-ийг rollback амлалгүй мэдээлнэ. Apple-linked аккаунт grant revoke бэлэн болтол хаалттай.
- Хадгалсан metadata дахь өргөн Storage INSERT policy-уудын эрсдэлийг тусгаарласан fixture давтав: бусдын prefix болон profile-гүй хуучин JWT upload. `202610220001_storage_account_guards.sql` нь дөрвөн bucket-д active profile + өөрийн UUID prefix шаардах restrictive INSERT/UPDATE/DELETE guard нэмнэ. Legacy permissive policy-тай нийлсэн ч fixture-д хаагдсан; public read, бусад bucket ба service-role cleanup-ийн хүрээг өөрчлөөгүй. **Production-д суулгаагүй**, saved metadata нь одоогийн live policy-г дахин шалгасан нотолгоо биш.
- Public deletion/privacy/terms/support source нь шинэ in-app зам болон бодит backend-ийн хязгаарыг тайлбарлана; pilot disclosure-ийг MD/web дээр нийцүүлсэн. Эдгээр нь нийтлэгдээгүй, эзэмшигчийн хууль/retention/moderation ажиллагааны баталгаа биш.
- Локал баталгаа: **413 Flutter тест**, analyze no issues, **31 deployment Python**, **36 Node VM handler** тест, **Deno 2.9.8 typecheck + жинхэнэ pinned SDK-ийн localhost HTTP 7 алхам**, Storage guard болон social/RPC SQL fixture, JavaScript release web build PASS. SDK/HTTP doubles нь hosted Auth/Storage/FK integration биш. Шинэ CI алхмууд remote run хийгдээгүй.
- Устгалын UI 320px/390px болон 2x текстийн тесттэй; браузерт confirm болон unavailable хариуг isolated HTTP fixture дээр шалгасан. Бодит аккаунт/устгал, native iPhone screenshot биш.

macOS 15.5, full Xcode байхгүй хэвээр. `softwareupdate --download 'macOS Sequoia 15.8.1-24H32'` нь **100% / exit 0** дууссан; зөвхөн татсан, суулгах/restart хийгээгүй. Дараах `sw_vers` нь 15.5 (`24F74`) гэж баталсан; backup байгаа эсэхийг батлаагүй. Major macOS upgrade, Apple төлбөр, гэрээ/license зөвшөөрөх үйлдэл хийгээгүй. `build_ios.sh --no-pub` нь дахин Xcode дээр BLOCK/exit 1, compile/IPA бүтээгээгүй. Түр fixture browser tab/серверийг хаасан.

**Үлдсэн саад:** нийцэх macOS/Xcode ба native build/бодит төхөөрөмж; disposable staging дээр legacy медиа, Auth/FK/JSON хувийн мэдээлэл, partial retry, зэрэг upload/устгал ба хуучин JWT; Apple revoke; насны gate/контент шүүлт/бодит moderation; privacy declaration ба reviewer account. Устгах API болон шинэ Storage migration deploy/enable тусдаа зөвшөөрөлтэй. Production change, шинэ бодит account, Git push, deployment болон store upload хийгээгүй. [Шинэчилсэн submission pack](APP_STORE_SUBMISSION.md).

## 2026-10-22 Эхний App Store audit (түүхэн)

Restart-ийн дараах бодит шалгалтаар macOS 15.5 (`24F74`), CommandLineTools хэвээр, full Xcode байхгүй. CocoaPods 1.17.0 ба Flutter 3.44.0 ажиллана. Chrome-ийн шинэ extension session-ээр Apple-ийн Xcode 26.3 Apple silicon холбоосыг дахин шалгахад Unauthorized руу шилжсэн; Account нь Pending / Purchase your membership гэж байна. Download/install амжилттай болсон гэж үзэхгүй, $99 төлөх болон гэрээ зөвшөөрөх үйлдэл хийгээгүй. OS шинэчлэл/restart-ийн тодорхой зөвшөөрөл хүлээгдэж байна.

Нэмсэн [App Store бэлтгэлийн багц](APP_STORE_SUBMISSION.md) нь identifiers, store текстийн ноорог, privacy өгөгдлийн матриц, age-rating/moderation/review/device checklist болон signing/upload-ийн дараалалтай. In-app deletion-ийг буцаах эсэх тухай хариу ирээгүй тул өмнөх хэрэглэгчийн шийдвэрийг далдуур буцаагаагүй. Устгах API/retry/Apple revoke, насны gate, нийтлэхээс өмнөх контент шүүлт ба бодит модерацийн ажиллагаа, signed native build/төхөөрөмжийн тест нь бодит үлдсэн саад.

`ios_preflight.py` нь source болон toolchain-ийг тусад нь шалгана; permission тайлбар, HTTPS хамгаалалт, callback/entitlement, icon catalog/1024px opaque PNG; full Xcode 26+, iPhoneOS SDK 26+, license/first-launch төлөв, CocoaPods ба pinned Flutter. Өөрөө license зөвшөөрөх, SDK суулгахгүй; source PASS нь дэлгүүрийн бэлэн байдлын баталгаа биш. `build_ios.sh` нь одоогийн public-config validator ашиглан unsigned release хийх бөгөөд endpoint/signing override flag-ийг хаана; CI-д холбосон, remote run хийгээгүй. Энэ Mac дээр уг wrapper нь Xcode байхгүйг илрүүлж exit 1 болсон, native compile/IPA үүсээгүй.

iOS камерын тайлбар одоогийн зураг авах урсгалыг хэлдэг болсон; хэрэгжээгүй live амлалт, native урсгалд ашигладаггүй microphone/Photos-add purpose key-ийг хассан. Нэмсэн `web/support.html`-ийг Settings-ийн Тусламж нээнэ, browser алдахад contact fallback хэвээр. Source нь локал; support URL-ийг production-д байна гэж хараахан үзэхгүй.

Локал баталгаа: 384 Flutter тест, analyze, deployment-ийн 30 Python тест (17 preflight/2 support/11 өмнөх config), устгах handler-ийн өмнөх 18 SDK-double тест, plist/project lint болон JavaScript release build PASS. Support page 1512px ба 320px дээр хэвтээ халилтгүй, logo ачаалсан; түр test server-ийг зогсоосон. Wasm compatibility dry-run-ийн өмнөх dependency анхааруулга хэвээр. Production function/migration/deletion, шинэ аккаунт, paid membership, signing key, App Store/TestFlight upload/review болон Git push хийгээгүй.

## 2026-10-21 iOS ба устгалын бодит шалгалт

**Дүгнэлт: App Store-д илгээхэд хараахан бэлэн биш.** Энэ шалгалтаар төлбөр, production устгал, migration, шинэ аккаунт, function deploy эсвэл Git push хийгээгүй. Өмнө хассан Settings-ийн устгах товчийг буцааж нэмээгүй.

| Шалгалт | Үр дүн / нотолгоо |
|---|---|
| Native файлын синтакс | `Info.plist`, `Runner.entitlements`, `AppFrameworkInfo.plist`, `project.pbxproj` нь `plutil -lint` PASS; энэ нь compile/signing баталгаа биш |
| Бүрэн Xcode | `/Applications/Xcode.app` болон `Xcode-beta.app` байхгүй; `xcode-select -p` зөвхөн `/Library/Developer/CommandLineTools`; `xcodebuild -version` ажиллахгүй |
| Dependency tooling | Анхны шалгалтаар `pod` байгаагүй. Дараагийн орчны бэлтгэлээр Homebrew CocoaPods 1.17.0 суулгаж, `pod --version` болон `flutter doctor -v`-ээр баталсан; project нь Flutter-generated Swift package reference-тэй боловч generated plugin metadata-д iOS SPM идэвхгүй. Dependency resolution-ийг native build-ээр батлаагүй |
| iOS release build | `flutter build ios --no-pub --release --no-codesign --dart-define=DEVICE_PREVIEW=false` нь exit 1, `Application not configured for iOS`; IPA/Runner.app бүтээгээгүй. Project файлууд байгаа тул энэ алдаагаар iOS source-ийг байхгүй гэж дүгнэхгүй |
| Бодит iPhone / simulator | `flutter devices --device-timeout 10` зөвхөн macOS, Chrome харуулсан; iPhone/simulator дээр ажиллуулаагүй. Xcode tooling байхгүй тул энэ нь бүх USB/утасны inventory биш |
| Flutter regression | Бүтэн 381 тест PASS, `flutter analyze --no-pub` no issues; native төхөөрөмжийн шалгалтыг орлохгүй |
| Устгах in-app зам | Settings, router болон client service-д account-deletion эхлүүлэх зам байхгүй; `web/delete-account.html` нь support имэйл рүү чиглэнэ |
| Hosted устгах API | Одоогийн Supabase project-ийн Edge Functions dashboard дээр `Deploy your first edge function` харагдсан; `delete-account` deploy хийгдээгүй. Endpoint-ийг дуудаж эсвэл бодит хаяг устгаж туршаагүй |
| Устгах локал handler | Жинхэнэ TypeScript handler-ийг Node VM-д ажиллуулсан 18 regression тест PASS; Supabase SDK/Auth/Storage нь сүлжээгүй doubles. Deno compilation, Supabase integration, database FK cascade болон binary cleanup баталгаа биш |

Устгах кодын хоёр бодит алдааг шинэ fixture эхлээд давтсан: нэг хавтсын 20,001 файл лимитийг давж амжилттай үргэлжилж байсан; алдааны дотоод мэдээлэл response-д буцаж байсан. Локал засвар нь файл нэмэх бүрд 20,000 хязгаарыг шалгаж, бүх 500 response-д generic тайлбар буцаана. CI-д энэ fixture-ийн command нэмсэн; энэ audit remote CI run эхлүүлээгүй. Node `--experimental-vm-modules` болон TypeScript stripping ашигладаг, SDK-г татаж/ажиллуулдаггүй.

**Үлдсэн устгалын эрсдэл:** Storage cleanup ба Auth deletion атомик биш. Дараагийн bucket эсвэл Auth устгал алдахад өмнө устгасан медиа буцахгүйг fixture илэрхий шалгадаг. Бүрэн устгал гэж сурталчлах эсвэл deploy хийхээс өмнө retry/recovery урсгал, хуучин media-ийн бүх байрлал, Auth session болон Apple token revocation, FK cascade/SET NULL дараах хувийн мэдээллийг disposable staging account дээр шалгах шаардлагатай. Зөвхөн profile мөр устгах SQL нь Auth account устгал биш.

[Apple-ийн 5.1.1(v)](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion) нь апп дотроос устгал эхлүүлэх боломж шаарддаг; энэ social app-ийн email-only support зам хангалтгүй. Manual backend боловсруулалт боломжтой ч хэрэглэгчийг заавал support email/chat руу явуулж болохгүй. Sign in with Apple ашиглах үед token revoke мөн шаардлагатай.

Build орчны дараагийн алхам: [одоогийн SDK шаардлага](https://developer.apple.com/news/upcoming-requirements/) нь App Store Connect upload-д Xcode 26+ болон iOS 26 SDK+ гэж байна. [Apple-ийн нийцлийн хүснэгт](https://developer.apple.com/xcode/system-requirements)-ээр Xcode 26 нь macOS 15.6+, харин энэ Mac 15.5. Иймээс нийцэх macOS/Xcode хос сонгож, OS upgrade-ийн backup/зөвшөөрөл, Xcode license-ийг эзэмшигчтэй шийднэ. Анхны audit орчныг өөрчлөөгүй; дараагийн бэлтгэлээр зөвхөн CocoaPods суусан. OS/Xcode суулгалт, signing team болон App Store/TestFlight upload хийгдээгүй.

Дараа нь бодит iPhone дээр Google/email/Apple login (Apple provider идэвхжсэний дараа), camera/photo/mic/location зөвшөөрөл, profile/post/story/reel upload/playback, удаан сүлжээ, account switch, private follow/block/DM болон устгалын баталгаажуулалт/цуцлалт/алдааг шалгана. Төхөөрөмжийн model, iOS хувилбар, build ID, үр дүнг тэмдэглэнэ; одоогоор эдгээрийг PASS гэж бүртгээгүй.

Локал давтах команд:

```sh
node --experimental-vm-modules --test tools/deployment/tests/delete_account_handler.test.mjs
flutter test --no-pub
flutter analyze --no-pub
plutil -lint ios/Runner/Info.plist ios/Runner/Runner.entitlements ios/Flutter/AppFrameworkInfo.plist ios/Runner.xcodeproj/project.pbxproj
flutter doctor -v
flutter devices --device-timeout 10
# Бүрэн Xcode/dependencies тохируулсны дараа:
flutter build ios --no-pub --release --no-codesign --dart-define=DEVICE_PREVIEW=false
```

### macOS/Xcode орчны бэлтгэл

2026-10-21: энэ Mac нь `Mac16,8`, `arm64`, macOS 15.5 (`24F74`), Data volume ойролцоогоор 350 GiB сул зайтай. Homebrew-ээс CocoaPods 1.17.0 болон Ruby хамаарлыг суулгав. `pod --version` exit 0, `flutter doctor -v` CocoaPods 1.17.0-ийг таньсан; full Xcode байхгүй анхааруулга хэвээр. Android SDK байхгүй нь энэ iOS ажлын тусдаа асуудал.

`softwareupdate --list` болон Settings хоёулаа Sequoia 15.8.1 (`24H32`, restart шаардлагатай) санал болгосон. Apple-ийн хүснэгтээр нийцэх Xcode 26.3 + iOS 26.2 SDK-тай хосыг эхний build-д сонгов. Settings дээр зөвхөн Sequoia 15.8.1 сонгож, macOS 27 болон Safari шинэчлэлийг сонгоогүй; `Update Now` дараагүй. Эзэмшигч нээлттэй ажлаа хадгалж, чухал файлаа нөөцөлсний дараа OS суулгалт/restart-ийг зөвшөөрнө. Нөөц байгаа эсэхийг энэ шалгалт батлаагүй.

Apple-ийн нэвтэрсэн албан ёсны [More Downloads](https://developer.apple.com/download/all/?q=Xcode%2026.3) дээр тогтвортой Xcode 26.3 Apple silicon архив (2.11 GB) олдсон. Chrome таталт `Download 35 failed` гэж дууссан; татаж/суулгаж дууссан гэж үзэхгүй. Дараагийн UI шалгалтад Mac түгжигдсэн байсан тул эзэмшигч өөрөө unlock хийх шаардлагатай; таталтын алдааны шалтгаан тогтоогдоогүй.

Үргэлжлүүлэх дараалал: Mac unlock, зөвшөөрөлтэй OS шинэчлэл/restart, Xcode архивын таталтыг батлах ба `/Applications/Xcode.app` суулгах, эзэмшигч license-ээ уншиж зөвшөөрөх, developer directory/first-launch/iOS platform тохируулах, doctor ба unsigned build, дараа нь simulator/бодит iPhone. Одоогоор Xcode license зөвшөөрөөгүй, iOS SDK/simulator суулгаагүй, iOS build амжилттай болоогүй. $99 гишүүнчлэл, signing key, production deploy болон Git push хийгээгүй.

## 2026-10-20 Production backend засвар

Эзэмшигчийн шууд зөвшөөрлөөр одоогийн `night owl / main Production` Supabase дээр social discovery, OSM каталог, hosted client RPC гэсэн 3 migration-ийг нэг transaction-аар суулгав. Endpoint, Supabase provider болон Auth/Storage/Realtime хэвээр. Тестэлсэн ба ажиллуулсан SQL багцын SHA256: `11f50f8f9c8d92c297e8511c1b25ac0633fd218235cd9f495a2c0b8064d9846c`. SQL Editor амжилттай дууссан; metadata-only postflight нь `PASS: hosted RPC, RLS, private media and pilot grants` гэж баталсан.

- Дутуу Feed/Following, follow/DM хүсэлт, creator discovery, газрын хадгалалт/цуглуулга, туршилтын RPC болон серверийн `create_group`, `check_in_venue` нэмэгдсэн. Хуучин schema-д байгаагүй `venues.address` талбарыг нэмж нийцүүлсэн. Өмнө суусан featured-event RPC-уудыг дахин суулгаагүй. Social migration нь profile-flag trigger-ийг идэвхтэй админ шалгадаг хувилбараар шинэчилсэн; жирийн хэрэглэгч өөрийгөө админ болгох оролдлогыг тусгаарласан тестээр хаасныг баталсан.
- Шинэ social хүснэгтүүдийн хэт өргөн API эрхийг нарийсгаж, хэмжилт/туршилтын хүснэгтийг зөвхөн RPC-ээр ашиглана. Группийн гишүүн биш хүн унших, дур мэдэн өөрийгөө нэмэхийг хаасан; owner урилга, гишүүний гарах/бичих урсгалыг тусгаарласан fixture-д шалгасан.
- Posts/Stories bucket private болсон. Шинэ клиент зөвшөөрөгдсөн signed URL авна; хуучин аппыг шинэчилж нээх шаардлагатай. Өмнө татсан эсвэл гаднын cache-д үлдсэн файлыг буцаан нууцалж чадахгүй.
- Суулгахын өмнө 26 public хүснэгтийн 998 мөр, schema metadata болон bucket тохиргооны хязгаарлагдмал хувийн snapshot-ийг Git-ээс гадна хадгалсан. Auth, медиа binary, Vault болон бүх серверийн тохиргоо ороогүй тул бүрэн database backup биш. Blocked-follow хос 0 байсан; wrapper нь шинэ ийм хос гарвал нөөцлөөгүй устгал хийхгүйгээр зогсооно. Аккаунт, пост, мессеж, медиа binary устгаагүй.

Локал баталгаа: 381 Flutter тест, analyze, тусгаарласан social/featured-event/hosted-RPC SQL шалгалтууд, 11 client-config, 7 web-startup тест болон JavaScript release build амжилттай. Production-оос авсан хоосон public schema/policy/application-function хуулбар дээр бүтэн багц болон rollback guard-ийг туршсан; Auth/Storage mock учраас бүрэн restore эсвэл бодит аккаунтын E2E шалгалт биш. Web `main.dart.js` SHA256: `79bb58f9c5e311ba9e8a9973476ee1a25f613d80b5d9f9e4056267d2cd8741a3`, өмнөх шалгасан live клиенттэй ижил. Wasm build биш; dependency-ийн өмнөх Wasm dry-run анхааруулга хэвээр.

Live браузерт All/Following feed, зөвшөөрөгдсөн медиа, creator/газрын discovery, газрын хуудас, DM жагсаалт болон хоосон туршилтын самбар ачаалсан. Бодит мессеж/follow/check-in/pilot өөрчлөлт submit хийгээгүй. Accessibility идэвхтэй browser smoke-ийн шууд hash холбоосоор шилжихэд GoRouter registry-ийн null exception бүртгэгдсэн ч зорьсон самбар нээгдсэн; энэ нь RPC биш клиент навигацын тусдаа үлдсэн асуудал. Бүх browser log алдаагүй эсвэл бүх апп E2E баталгаатай гэж үзэхгүй.

Үлдсэн: хоёр бодит аккаунт/төхөөрөмжөөр private follow approval, block/DM, upload болон зэрэгцээ check-in; Apple/native/store шаардлага; зөвшөөрөлтэй бодит creator, шалгасан газар, контент бүрдүүлэх. 270 OSM газар нь эх сурвалжтай каталог болохоос шалгасан түнш эсвэл бүрдсэн pilot биш. Төлбөртэй үйлчилгээ, реклам, шинэ сервер эхлүүлээгүй. Энэ багцыг дахин эсвэл хуучин public-bucket setup SQL-ийг дараа нь бүү ажиллуул.

Доорх dated хэсгүүд тухайн үеийн түүхэн төлөв; дээрх production засвар нь өмнөх hosted social/check-in суулгаагүй гэсэн саадыг шинэчилнэ.

## 2026-10-20 DM нууцлалын засвар

Supabase/PostgreSQL, Auth, Storage, Realtime болон одоогийн endpoint хэвээр байна. Тусдаа сервер авах, database нүүлгэх ажил хойшлогдсон. Энэ release зөвхөн DM клиент ба регрессийн тестүүдийг хамарна; database migration, hosted эрх/өгөгдөл өөрчлөхгүй.

Аккаунт эсвэл ярианы хүн солигдоход хуучин мессеж, ноорог, reply note болон зөвшөөрлийн төлөв шинэ чатад үлдэхээс хамгаалав. Хоцорсон profile/message/permission/send хариу өөр аккаунтын дэлгэцийг өөрчлөхгүй. Logout нь чат/нооргийг арилгаж, polling/subscription-ийг зогсооно; ижил аккаунтын session шинэчлэгдэхэд ноорог хэвээр.

Локал баталгаа: 381 Flutter тест (9 шинэ scope тесттэй), analyze, тусгаарласан social SQL/preflight, 11 client-config, 7 web-startup тест болон JavaScript release build амжилттай. Wasm build биш. Бодит хоёр аккаунт/төхөөрөмжийн шалгалт болон hosted social/featured-events migration-уудын өмнөх саад хэвээр; энэ клиент засвар тэдгээрийг суулгасан эсвэл бүх апп бүрэн ажилладаг гэсэн баталгаа биш. Нийтлэлтийн төлөвийг commit болон public artifact-аар тусад нь батална.

Доорх нь өмнөх release-үүдийн түүхэн төлөв.

2026-10-06. Үнэгүй аппын шинэ код ба web release build бэлэн. `7c277c7` commit GitHub-д илгээгдэж, Netlify `6ac415570767e000085a73fd` дээр нийтлэгдсэн. Public JavaScript нь шалгасан локал build-тэй ижил. Native build/signing, App Store/Play Store нийтлэлт болон Apple provider-ийн бодит тохиргоо дараагийн ажлууд хэвээр.

Газрын зураг zoom18–19 үед газар бүрийг тусдаа pin болгож харуулна. Давхцсан pin-үүд зайтай байрлаж, бодит координаттайгаа шугамаар холбогдоно. Pin сонгоход камер/zoom хэвээр; жижигрүүлэхэд бүлэглэл сэргэнэ. Нийт219, газрын зургийн14 тест амжилттай; public апп дээр сонголт, zoom-in/out, алдаагүй ажиллагааг шалгасан.

Апп ашиглах төлбөр, subscription, premium unlock, in-app purchase идэвхтэй биш. QPay хуудас, төлбөрийн түүхийг хассан; хуучин `/qpay/:id` холбоос тухайн постыг нээнэ. Урилга нь үнэгүй хуваалцах холбоос бөгөөд unlock/reward амлахгүй. Paid-content entitlement хүснэгт/түгжээ байхгүй тул төлбөрийн backend migration шаардлагагүй. Төлбөрийн системийг deployment-ийн дараа тусдаа ажлаар шийдэх тул энэ үнэгүй release-ийн blocker биш. Газрын үйлчилгээ эсвэл эвентийн орох үнэ харагдвал энэ нь зохион байгуулагчийн мэдээлэл; апп дотор төлбөр авахгүй, бүх газар/эвент үнэгүй гэсэн утгатай биш. RSVP нь очих сонирхол/оролцоогоо тэмдэглэх үйлдэл бөгөөд тасалбар эсвэл төлбөр биш.

## 2026-10-07 Профайлын Night Owl аватар

Higgsfield GPT Image 2.5-аар одоогийн owl logo-г reference болгон залуу эрэгтэй/эмэгтэй, ахимаг эрэгтэй/эмэгтэй дөрвөн 3D owl аватар үүсгэсэн. App asset нь тус бүр 512×512 WebP, дөрвүүлээ нийт 112,122 byte. Job ID, prompt болон эх сурвалж `docs/AVATAR_ASSETS.json`-д байна.

Профайл үүсгэх/засах дэлгэц дөрвөн сонголт болон өөрийн зураг оруулах товчтой. Сонголт existing `avatar_url` текст талбарт `nightowl://avatar/<id>` байдлаар хадгалагдана; зураггүй үед тогтмол анхны owl харагдана. Нас, хүйсийг автоматаар таахгүй. Өмнөх өөрийн зураг хэрэглэгч солих хүртэл хадгалагдана. Profile, feed, story, message, settings дахь renderer-үүд ижил asset-ийг ашиглана. Галерей цуцлах, upload/profile алдаа, давхар хадгалалт, хаяг солигдсон үеийн оройтсон үр дүнг шалгасан; completed profile засахад Auth metadata-г дахин бичихгүй.

Аватар өөрөө шинэ серверийн SQL эсвэл storage bucket шаардахгүй. Одоогийн runtime багцад өмнөх Explore шинэчлэлт хамт байгаа тул public нийтлэлт түүний Supabase баталгаажуулалтыг хүлээж байна. Аватарыг production серверт хадгалах бодит хэрэглэгчийн өөрчлөлт хийгээгүй; локал widget шалгалтад зохиомол хэрэглэгч болон mock сервер ашигласан. Нарийвчилсан build баталгаа `docs/BUILD_VERIFICATION.json`-ийн `avatar_update` хэсэгт байна.

## 2026-10-07 Explore: онцгой эвент ба богино бичлэг

Шинэ код локалд бэлэн; энэ хэсгийн Supabase шинэчлэл болон web нийтлэлт одоогоор хийгдээгүй. Одоогийн public хувилбар дээрх `7c277c7` хэвээр.

- Газрууд дэлгэцийг доош гүйлгэхэд “Онцгой эвентүүд”, “Богино бичлэгүүд” гарна. Газрын зураг, zoom болон сонгосон газар хадгалагдана; доорх хэсэг рүү болон газрын зураг руу буцах товчтой.
- Эвентүүдийг зөвхөн одоогийн идэвхтэй Night Owl админ `Админ самбар → Онцгой эвентүүд` хэсгээс сонгож/хасна. Сервер эрхийг үйлдэл бүр дээр шалгана. Жирийн газрын эзэн өөрийн эвентээ автоматаар онцолж чадахгүй; дууссан эвент харагдахгүй; анхандаа сонголт хоосон байна.
- Богино бичлэгийн асуулга видеог эхлээд серверт шүүж, дараа нь хамгийн сүүлийн 50-ийг авна. Explore-ийн зураг дээр дарахад тухайн бичлэг нээгдэнэ; жагсаалтаас хуучин бичлэгийн холбоосыг тусад нь уншина. Урьдчилсан зураг дуугүй; дэлгэц далдрахад тоглолт зогсоно.

Серверт хэрэгжүүлэх дараалал: `supabase_protect_profile_flags.sql` болон `supabase_featured_events.sql`-ийн агуулгыг нэг transaction-д ажиллуулах. Хоёр дахь файлын гаднах `begin;`/`commit;`-ийг нэгтгэх үед хасна. Feature migration дангаар ажиллахдаа prerequisite trigger байхгүй бол бүхэлдээ rollback хийнэ. Энэ нь хуучин эвент, хэрэглэгчийн мөрүүдийг устгахгүй, шинэ event_features хүснэгт хоосон үүсгэнэ. Live preflight дээр хамгаалалтын trigger байгаагүй тул companion patch шаардлагатай. SQL Editor-ийн “Potential issue detected” баталгаажуулалт дээр хэрэглэгчийн зөвшөөрөл хүлээгдэж байна. Серверийн функцүүдийг суулгаж шалгасны дараа runtime commit-ийг push хийнэ (энэ branch Netlify автоматаар нийтэлдэг).

Тусдаа PostgreSQL 18.3 (PGlite 0.5.8) зохиомол өгөгдөл дээр атомик хэрэгжилт/дахин ажиллуулах, prerequisite rollback, админ/энгийн/бан авсан хэрэглэгчийн эрх, өөрийгөө админ болгох хамгаалалт, нийтэд унших/хугацаа дуусах, сонгох/эрэмбэлэх/хасахыг шалгасан. Бодит хэрэглэгчийн эвент онцлох өөрчлөлт хийгээгүй. Локал шалгалт болон archive-ийн сүүлийн мэдээлэл `docs/BUILD_VERIFICATION.json`-ийн `explore_discovery_update` хэсэгт байна.

## 2026-10-05-ны локал UX шинэчлэлт

270 OSM газрын нэмэлт каталог, ойр pin-үүдийн бүлэглэл, эх сурвалж/утас/сайт/цагийн мэдээлэл, Instagram-аас санаа авсан бодит статистиктай профиль, ойлгомжтой эхлэлийн текст, Higgsfield owl emotion болон reduced-motion дэмждэг шилжилт нэмсэн. Google Places API key байхгүй тул Google мэдээлэл татсангүй. Бүтэн 219 тест, static analysis, JavaScript release build амжилттай. Локал preview-ийн хоригийн дараа 2026-10-06-нд нийтлэгдсэн апп дээр эхлэлийн loading, бүлэглэл/zoom, 279 газрын жагсаалт, map/list байрлал хадгалах, profile Saved, өдөр/шөнө болон газрын мэдээллийн цонхыг шалгасан. Browser error хоосон. Шинэ ZIP бэлэн, push/deploy баталгаажсан. PostgreSQL бүрэн export/cutover нууц үг, target host болон үйлчилгээний интеграци хүлээгдсэн хэвээр.

## 2026-10-06 loading шалгалт

Нийтлэгдсэн `be0c9a2` build-д шинэ owl emotion asset байхгүйг public JavaScript hash болон Netlify dashboard-аар баталсан. Локал кодын route/press motion, үндсэн loading ажилласан; хайлт, мэдэгдэл, дагагчид, creator/post detail, business болон auth loading-ийг гүйцээсэн. Web bootstrap одоо logo/status, бодит first-frame cleanup, initialization error/retry-тэй. 215 Flutter тест, 7 Node startup тест болон анализ амжилттай; шинэ release ZIP бэлэн. Шинэ хувилбар Netlify дээр нийтлэгдэж, public файл болон браузерийн ажиллагаагаар баталгаажсан.

## Баталгаажуулалтын төлөв

- Flutter 3.44.0 / Dart 3.12.0; static analysis: no issues.
- Бүтэн Flutter suite-ийн 219 тест амжилттай. Өмнөх auth/callback/profile metadata, координат/owner засвар, account isolation, feed/filter/navigation, үнэгүй холбоос/урилга, JPEG/video validation болон reference layout-ийн шалгалтууд хадгалагдсан. Шинэ шалгалтууд өдөр/шөнө/System, OS brightness, preference-ийн дараалсан хадгалалт, startup/хожуу үр дүн, `false`/exception rollback ба disposal-ийг хамарна. Profile хоёр горимд 320/1280px ба 1.5x текстээр, Settings 320px ба 2x текстээр; Feed/Messages болон map-ийн горим солих ажиллагааг мөн шалгасан.
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
