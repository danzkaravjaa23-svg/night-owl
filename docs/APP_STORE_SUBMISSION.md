# Night Owl UB — App Store эхний хувилбарын бэлтгэл

Шинэчилсэн: **2026-11-04, Asia/Ulaanbaatar**. Client `b4e60b3`, backend forward fix `8d4db32`; нийтэд ажиллаж буй web `e0e1d45` (privacy-only; runtime `7cc568e`-тэй ижил).

**Apple membership Active; Team `DAVM2JZ4NN` дээр App ID болон App Store Connect record үүссэн.** Explicit App ID **`com.nightowl.ub.nightOwlUb`**, description **Night Owl UB**, Sign in with Apple capability **primary** байдлаар бүртгэгдсэн. [App Store Connect — Apple ID `6830714135`](https://appstoreconnect.apple.com/apps/6830714135/distribution): iOS, **Night Owl UB**, **en-US**, SKU **`night-owl-ub-ios`**, төлөв **Prepare for Submission**.

Connect-ийн **1.0.0** хувилбарт promotional text, description, keywords болон support URL хадгалагдсан; App Information-д subtitle, **Social Networking / Lifestyle** ангилал хадгалагдсан. Эзэмшигчийн сонгосон **After Approval** автомат нийтлэх тохиргоог хадгалсан.

Privacy Policy URL **https://nightowl-ub.netlify.app/privacy.html** хадгалсан. US/USD **0.00** суурь үнийн schedule батлагдсан; хадгалсан Prices popover-ийг дахин нээж бүх **175** дүн **0.00** байгааг шалгасан. Түгээлтийг **зөвхөн Монгол** гэж хадгалсан: **Availability (1 Country or Region)**, **Mongolia — Available on App Release**; бусад **174** улс/бүс боломжгүй, шинээр нэмэгдэх улс/бүсийг автоматаар нээх сонголт unchecked. 2026-11-05-нд App Privacy-ийн **16 төрөл** болон төрөл бүрийн purpose/linkage/tracking хариу хадгалагдсаныг баталсан; **Set Up** үлдээгүй. **Publish** боломжтой боловч дараагүй; эцсийн эзэмшигчийн хяналт ба нийтлэх алхам хүлээгдэнэ. Насны асуулга хадгалагдаж, хуудсыг бүтнээр дахин нээхэд батлагдсан: Apple-ийн тооцоолсон **18+** нь **173 улс/бүсэд**, **Бразил 16+**, **Солонгос 19+**; OS 26-аас өмнөх хувилбарын ерөнхий ангилал **17+**, бүсийн онцлог ангилалтай. Override хийгээгүй. [Бүртгэл ба metadata нотолгоо](app-store/evidence/apple-store-setup.json).

Эзэмшигч Agree дарсан гэж мэдээлсэн ч шинэчилсэн license banner харагдсан хэвээр; шийдэгдсэн гэж батлаагүй, агент гэрээ зөвшөөрөөгүй. Staging Services ID **`com.nightowl.ub.web.staging`** primary native App ID-тай холбогдож, **`sreojqqqhdzkfsrbvlpl.supabase.co`** domain болон **`https://sreojqqqhdzkfsrbvlpl.supabase.co/auth/v1/callback`**-ийг хадгалж дахин нээж баталсан. Эзэмшигчийн зөвшөөрлөөр зөвхөн Sign in with Apple зориулалттай **Night Owl UB Apple Login** key (**`KW5USR3XYB`**) үүссэн. Apple **Downloaded** гэж харуулсан ч `.p8`-ийн байрлал/материал болон хамгаалсан хадгалалт батлагдаагүй; 0700 хавтас байгаа нь key хүлээн авсан гэсэн үг биш. Private key handoff, Supabase provider activation, бодит login/revoke, signed IPA, TestFlight upload болон review submission хүлээгдэнэ.

Суурь `23a7258`-ийн 886 Flutter тест PASS; газрын нэр болон шинэ conflict handling-д focused шалгалтууд нэмж давсан. Одоогийн `b4e60b3` unsigned iPhone/simulator build болон iPhone/iPad startup PASS; архивын checksum, bundle/12 privacy manifest болон эхлэх дэлгэцүүдийг татаж баталгаажуулсан. Backend `8d4db32`-ийн бодит local Auth/Storage/Edge 10 бүлэг PASS. Staging baseline+008/009+`202611040001` сууж, minimum Auth/media85 болон moderation58+setup17 API шалгалт PASS; scoped fixture cleanup дууссан. Local DB/медиа recovery батлагдсан ч hosted recovery/ACL/operator gate үлдэнэ.

Staging `delete-account` deploy/enable хийгдсэн: зөвхөн энэ function-д `verify_jwt=false`, `ACCOUNT_DELETION_ENABLED=true`. Хоёр synthetic email аккаунтын бодит run **27 + 17 шалгалт PASS**, **67 HTTP хүсэлт**; Auth устсаны дараах receipt-only recovery болон бусдын медиаг хадгалахыг баталж, хоёр аккаунтын зургаан scoped тооллого бүгд0 болсон. Нэг completed journal хадгалагдсан. [Exact source hashes, dashboard тохиргоо ба acceptance receipt](app-store/evidence/staging-edge-erasure-acceptance.json). Public email delivery, Apple/provider ба signed device/UI, hosted failure/concurrency/legacy/shared-content acceptance, recovery parity, retention/moderator ажиллагаа, coordinated production rollout ба Store мэдүүлгүүд дутуу. Unsigned compile нь signing болон бодит Apple login-ийг орлохгүй. [Одоогийн receipt](BUILD_VERIFICATION.json) · [release тайлан](RELEASE_READINESS.md) · [эзэмшигчийн алхам](app-store/OWNER_NEXT_STEPS.md).

## Оруулсны дараа засаж болох уу?

| Өөрчлөлт | Хүргэх арга |
|---|---|
| Flutter дизайн, animation, шинэ дэлгэц, функц, binary дахь алдаа | Жишээ нь `1.0.0` → `1.0.1`; өссөн build number, шинэ signed build, Apple review, дараа хэрэглэгч update хийнэ |
| Одоо байгаа боломжийн хүрээнд газруудын мэдээлэл, эвент, пост, story, серверийн мэдээлэл | Backend/admin-аар шинэчилнэ; тухайн өгөгдөл cache шинэчлэгдэхэд харагдана |
| Store promotional text | Шинэ binary submission шаардахгүйгээр шинэчилж болно |
| Нэр, тайлбар, screenshot зэрэг listing талбар | Талбараас хамааран editable төлөв/шинэ хувилбар шаардана; бүгдийг хүссэн үедээ сольдог гэж үзэхгүй |

Backend шинэчлэлт нь суулгасан Flutter binary-г өөрчлөхгүй. Netlify deploy хийснээр iPhone-ийн Store хувилбар автоматаар шинэчлэгдэхгүй. Шалгалтаас нуугдсан шинэ үндсэн боломжийг remote switch-ээр дараа нь нээхээр төлөвлөхгүй.

Эх сурвалж: [шинэ хувилбар үүсгэх](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/), [listing-ийн талбарууд](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), [app мэдээлэл засах](https://developer.apple.com/help/app-store-connect/create-an-app-record/view-and-edit-app-information/).

## Хугацаа ба гишүүнчлэл

Apple-ийн одоогийн review-status хуудсанд submission-ийн **50%-ийг 24 цагийн дотор, 90%-ийг 48 цагийн дотор** шалгах зорилттой гэж байна. Энэ нь approval-ийн баталгаа, бүх аппын дээд хугацаа биш. Засвар нэхвэл дахин илгээж, хугацаа нэмэгдэнэ. Зөвшөөрөгдсөн release дэлгүүрт харагдах хүртэл дахин **24 цаг хүртэл** үргэлжилж болно. [Review хугацаа](https://developer.apple.com/help/app-review/after-submitting-for-review/review-status), [нийтлэх үйл явц](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store).

Энэ аппын бэлтгэл дуусаагүй тул “өнөөдрөөс 48 цагийн дараа Store-д орно” гэж тооцохгүй. Гишүүнчлэл/Xcode бэлэн болсны дараах native build, төхөөрөмжийн шалгалт, Apple login ба бүрэн account deletion ажлыг дуусгах **төлөвлөлтийн эхний нөөц 3–7 ажлын өдөр**; unsigned native compile батлагдсан ч signed төхөөрөмж, Apple provider болон hosted deletion acceptance үлдсэн тул баталгаатай ETA биш. Дараа нь Apple review/release-ийн хугацааг нэмнэ. OS таталт, enrollment verification, шинэ алдаа, review rejection энэ хүрээг сунгана.

Apple Developer Program **жилд 99 USD**, боломжтой оронд дотоод валютаар. Апп үнэгүй байсан ч Store түгээлтэд гишүүнчлэл хэрэгтэй. Төлбөр, хэнээр бүртгүүлэх (individual/organization), гэрээг эзэмшигч шийднэ. Individual бүртгэлд хууль ёсны нэр seller name болдог; байгууллагад D-U-N-S зэрэг баталгаажуулалт шаардаж болно. [Enrollment](https://developer.apple.com/help/account/membership/program-enrollment), [бүртгэлийн шаардлага](https://developer.apple.com/programs/enroll/).

## 2026-11-03-ны суурь шалгалт (түүхэн)

| Зүйл | 2026-11-03-нд баталсан төлөв | Дараагийн шалгалт |
|---|---|---|
| Гишүүнчлэл | Эзэмшигч: идэвхжүүлээгүй | Active membership, Team, App Store Connect хандалт |
| macOS / Xcode | Локал macOS 15.5 дээр full Xcode байхгүй; GitHub macOS runner дээр Xcode 26.3 / iOS SDK 26.2-оор build PASS | Локал signing/device work хийх бол тохирох OS/Xcode; cloud CI compile энэ саадыг давсан |
| Flutter / native source | Flutter 3.44.0; iOS target 13.0; source preflight болон unsigned iPhone/simulator compile PASS | Эцсийн signed archive/device acceptance/privacy report |
| Bundle ID / version | `com.nightowl.ub.nightOwlUb`; `1.0.0+1`; signing Team сонгоогүй | Энэ ID эзэмшигчийнх эсэх, ашигласан build number-ийг Connect-д шалгах |
| Apple login | Public settings: Apple `false`, Google `true`, email `true` | Apple App ID, Services ID, provider, callback, бодит iPhone login |
| Account deletion | Durable job/lease, write freeze, fresh Apple revoke, secure recovery кодтой; бодит local Auth/Storage/Edge 10 бүлэг PASS; public function 2026-11-03-нд inactive байдлаар deploy болсон: flag=false, gateway JWT=true, 503 батлагдсан | Сэргээх DB/Storage backup, hosted staging cleanup/recovery, scoped gateway/enable, Apple credentials ба disposable account-ийн бүтэн устгал |
| Privacy / support URL | Хоёул 200, бодит static HTML, contact email байгаа; Flutter fallback биш | Consent/venue/inactive503 тайлбар `e0e1d45`-д нийтлэгдсэн; шинэ009 policy rollout болон хадгалсан 16 төрлийн App Privacy draft-ийн эцсийн хяналт/нийтлэх алхам үлдсэн |
| Backend / admin | Өмнөх rollout-оор storage/deletion boundaries, analytics consent, admin/interaction SQL суусан; 005–007 map шинэчлэлт суусан | 008/009 + compatible client rollout болон Edge enablement дутуу; бодит moderator workflow |
| Native QA / screenshots | Одоогийн `23a7258` unsigned iPhone/simulator compile болон iPhone/iPad startup PASS (CI41616509440 attempt2) | Signed төхөөрөмжийн 16 case, archive болон Store screenshot үлдсэн |
| UGC аюулгүй байдал | Server-enforced pending/approved/rejected, text/photo/video review queue; өргөтгөсөн report, block болон audit кодтой | 009 migration ба клиент хамт rollout; хариуцсан moderator, бодит report шийдвэрлэлт |

iOS source preflight **9/9 PASS**, deployment Python **43 тест PASS** (үүнд iOS preflight 29). GitHub-ийн [анхны native build](https://github.com/danzkaravjaa23-svg/night-owl/actions/runs/41594468073) нь `51e2144` commit дээр unsigned iPhone release `Runner.app` болон simulator build хоёрыг амжилттай гаргасан; Xcode 26.3 / iOS SDK 26.2 / Flutter 3.44.0. Энэ нь эхний суурийн нотолгоо: дараагийн backend/client засвар бүрийг шинэ candidate-аар дахин build/test хийнэ.

Өмнөх app source `7cbbeb3`-ийн [native CI](https://github.com/danzkaravjaa23-svg/night-owl/actions/runs/41599319526) unsigned iPhone/simulator build, iPhone 17/iPad Pro 13(M5) startup PASS. 12 privacy manifest inventory хийж, screenshot хоёрыг нягталсан. [Бодит component CI](https://github.com/danzkaravjaa23-svg/night-owl/actions/runs/41600759661) `d1d0f4e` эхээр Auth/Storage/Edge 9 бүлэг PASS; бүрэн production schema parity болон Apple live provider тест биш. Тэр үеийн Flutter 859, analyzer clean, 16 UI capture, web release PASS. Одоогийн `23a7258` client-ийн Flutter 886, analyzer болон web release PASS; `f3f3a98` backend-ийн [CI 41616849314](https://github.com/danzkaravjaa23-svg/night-owl/actions/runs/41616849314) бодит 10 бүлэг PASS. [Дэлгэрэнгүй нотолгоо](app-store/evidence), [эрх авсны дараах дараалал](app-store/OWNER_NEXT_STEPS.md).

Эхний public шалгалтын цаг `2026-11-03T06:51:19.982817Z`; receipt: `build/audit/2026-11-03/app-store-prep/public-preflight.json`. Тэр GET болон шинэ inactive Edge-ийн 10:03 UTC probe шалгалтаар хэрэглэгчийн устгал хийгээгүй. Өмнө суусан SQL-ийг хуучин checklist-ийн дагуу дахин суулгахгүй.

Apple-ийн [одоогийн upload шаардлага](https://developer.apple.com/news/upcoming-requirements/): Xcode 26+, iOS 26 SDK+, deployment target iOS 13+. [Нийцлийн хүснэгт](https://developer.apple.com/xcode/system-requirements)-ээр Xcode 26.3 нь macOS 15.6+ дээр ажиллана; одоогийн 15.5 хүрэхгүй. Xcode 27 нь macOS Tahoe 26.6+ шаардана. Ямар Xcode сонгохыг турших iPhone-ийн OS хувилбартай тулгана. OS шинэчлэлт/restart энэ бэлтгэлээр хийгдээгүй.

## Кодын бэлтгэл ба үлдсэн deployment/device шалгалт

Энэ candidate-ийн 008 account erasure, 009 manual UGC review болон түүнд нийцсэн client өөрчлөлт нь эх кодын бэлтгэл. Өмнөх production migration/deploy-ийг эдгээр шинэ өөрчлөлт суусан гэж тооцохгүй; staging/hosted acceptance болон эцсийн native QA-ийн үр дүнг [release тайлан](RELEASE_READINESS.md)-тай тулгана.

1. **Apple нэвтрэлт:** Google-оор account үүсгэх боломжтой учир Guideline 4.8-ийн equivalent login шаардлагыг хангана. Одоо байгаа Apple товчийг бодитоор ажиллуулж native cancel, Hide My Email, дахин login-ийг шалгана. [Тохиргооны заавар](APPLE_SIGN_IN_SETUP.md), [Login Services](https://developer.apple.com/app-store/review/guidelines/#login-services).
2. **Бүртгэл устгах:** 008 migration, Edge handler, iOS/web fresh Apple proof, receipt-only status, owner-bound secure recovery кодтой. Native Apple credential эсвэл web-ийн тусдаа товшилтын popup нь Supabase session-ийг солихгүй. Зөвхөн opaque receipt/owner/start time secure storage-д хадгалагдана; Apple code/token хадгалахгүй. Auth аль хэдийн устсан ч аппыг дахин нээхэд эхлэл дэх **Өмнөх устгалын төлөвийг шалгах** холбоосоор status-only шалгалт хийхээр бэлтгэсэн; өөр хаягаар нэвтэрсэн session-ийг гаргахгүй. Client receipt preparation-аас 30 хоног хүчинтэй; completed server journal completion-оос 30 хоног хадгалагдаж, operator pruning шаардана. 69 FK-ийн synthetic schema, isolated SDK/HTTP/crypto тест нь production account erasure биш. Staging service deploy/enable хийгдэж email synthetic аккаунтын устгал/receipt recovery PASS; Apple болон hosted failure/concurrency/legacy/shared-content acceptance үлдсэн. Production service идэвхгүй хэвээр; Android Apple deletion proof одоогоор fail-closed. [Backend гэрээ](../supabase/functions/delete-account/README.md), [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
3. **Контентын хамгаалалт:** 009 migration-ийн арга нь хүний **manual review**; AI шалгалт хийсэн гэж зарлахгүй. 009 дангаараа Post/Reel, story, comment, event, venue review, profile, note, public collection болон байгууллагын venue засварыг pending болгож, approve/reject болон version/audit-аар шийднэ. **2026-11-07-ны эзэмшигчийн шийдвэрээр** `202611070001_ugc_publish_immediately.sql` (бэлтгэсэн, staging/production-д хараахан суугаагүй) энгийн post/Reel, story, comment, note, review, нийтийн collection, profile-ийг шууд нийтэлнэ: хориотой үг, холбоос/утасны дугаартай текст, нийтлэгдсэн пост/story-д шинэ медиа нэмсэн засвар, татгалзсан зүйлийн засвар pending болно; пост/Reel, story, comment, note, review, collection-ийг мэдээлсэн хүнд refresh-ийн дараа харагдахгүй, 3 тогтсон хэрэглэгч (profile-д 5) мэдээлбэл бүгдээс нуугдана; event болон venue өмнөх шигээ батлагдсаны дараа гарна. Зохиогч pending/rejected төлөвөө харна; баталсан public profile-ийг шинэ candidate шалгагдах үед хэвээр хадгална. Батлагдаагүй content газрын хэмнэлд орохгүй. Post/Reel, user, venue, story, comment, DM/group message, event, review, note, collection-ийн report нь caller-д харагдах яг target-ийг серверт баталж авна. Зөвхөн мэдээлсэн мессежийн snapshot админд орно; хувийн inbox/thread бүхэлд нь нээх эрх үүсэхгүй. Хүн хариуцсан moderation/appeal ажиллагаа, rollout болон бодит target/private media тест үлдэнэ. [UGC шаардлага](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
4. **Бодит native тест:** [review/test plan](app-store/REVIEW_TEST_PLAN.md)-ийг iPhone, iPad, deny/limited permission, network failure, background/resume, account switch-ээр гүйцэтгэнэ. Reviewer-д өөрийн зөвшөөрөлтэй non-admin demo account ба ажилладаг backend хэрэгтэй; нууц үгийг repo/чатад бичихгүй.
5. **App Privacy, export compliance:** 16 төрлийн бүх detail хадгалагдсан unpublished draft-ийг бодит binary/SDK/сервертэй тулгаж эзэмшигч эцэслэн батална; export compliance үлдсэн. Насны асуулга хадгалагдсан; 18+ өөрийн мэдүүлэг нь нас баталгаажуулалт биш. `ITSAppUsesNonExemptEncryption=false`-г нотолгоогүйгээр нэмэхгүй.

Post болон **Богино видео / Reel** нийтлэх нь нэг captured-session/frozen-retry composer ашиглана. Reel нь нэг видео; canonical UUID эсвэл OSM ref бүхий газрыг сонгох/солих/хасах нь сонголтоор. Давхар дарах, алдагдсан insert хариу, picker/upload дундуур хаяг солигдох үед нэг ID болон эхний илгээсэн venue/caption/media хэвээр байх ёстой. Амжилт нь **Шалгалтад илгээлээ** гэсэн утгатай; approval public болгох боловч 168 цагийн анхны publication clock-ийг шинэчлэхгүй. Native picker/playback болон бодит retry-г төхөөрөмж дээр дахин шалгана.

## Хийж бэлдсэн listing багц

[metadata/en-US](app-store/metadata/en-US) дотор нэр, subtitle, promotional text, description, keywords болон reviewer notes-ийн тусдаа текстүүд бий. Connect app record **en-US** primary language-тай үүссэн. **1.0.0** хувилбарын promotional text, description, keywords нь эдгээр файлын эхлэл/төгсгөлийн whitespace-ийг хассан агуулгатай яг таарч хадгалагдсан. Subtitle **Places, moments and friends** (27 тэмдэгт) болон ангиллууд App Information-д тусдаа хадгалагдсан. Аппын үндсэн UI Монгол гэдгийг description-д тайлбарласан. Reviewer notes, бүх Store талбар болон submission бүрэн дууссан гэж үзэхгүй; native acceptance, privacy/export мэдүүлэг болон review материал үлдсэн; насны асуулга хадгалагдсан. [Хадгалсан талбаруудын нотолгоо](app-store/evidence/apple-store-setup.json).

- Name: **Night Owl UB**; хадгалсан primary category: **Social Networking**, secondary: **Lifestyle**.
- Price: **Free** — US/USD **0.00** schedule батлагдсан; хадгалсан Prices popover-ийн **175** дүн бүгд **0.00**. IAP/subscription/payments одоогоор байхгүй. Түгээлт зөвхөн Монголд **Available on App Release**; бусад 174 улс/бүс боломжгүй.
- Privacy Policy URL: `https://nightowl-ub.netlify.app/privacy.html` — Connect-д хадгалсан. 2026-11-05-нд App Privacy-ийн **16 төрөл** болон төрөл бүрийн purpose/linkage/tracking хариу хадгалагдсаныг баталсан; **Set Up** үлдээгүй. **Publish** боломжтой боловч дараагүй; эцсийн эзэмшигчийн хяналт ба нийтлэх алхам хүлээгдэнэ.
- Support URL: `https://nightowl-ub.netlify.app/support.html` — Connect-д хадгалсан; одоогийн support `osokhe@gmail.com`.
- Бодитоор үүссэн SKU: **`night-owl-ub-ios`**.
- Review contact: эзэмшигчийн нэр, international phone; test account credentials-ийг Connect-д шууд оруулна.
- Mac/Vision availability checkbox-ууд default checked харагдсан; өөрчлөөгүй, эдгээр платформын нийцлийг баталгаажуулаагүй.

Хадгалсан draft нь эх кодоор баталсан 12 төрөл болон production логийн **Search History, Coarse Location, Other Diagnostic Data, Performance Data** дөрвөн төрлийг хамарсан. Нэмсэн дөрвөн төрөл **App Functionality / Linked Yes / Tracking No**; production-ийн authenticated account linkage-ийг staging-ийн нотолгооноос таамагласан бөгөөд production дээр нэвтэрсэн хүсэлтээр шалгаагүй. Төрөл бүрийн үндэслэл, албан эх сурвалж, үлдсэн хязгаарлалтыг [worksheet](app-store/submission-disclosures-worksheet.json)-д хадгалсан. Privacy questionnaire-д contact/identifier, photo/video/text/DM, хэрэглэгчийн сонгосон venue, interaction/optional analytics, техникийн лог/SDK практикийг хамруулна. Account ID-тай холбогдох өгөгдлийг unlinked гэж, эсвэл аппыг No Data Collected гэж мэдүүлэхгүй. Map provider-ийн IP/tile request, EXIF/video metadata, retention-ийг тусад нь нягтална. IDFA/ATT advertising SDK одоогийн кодод харагдаагүй нь бүх provider tracking-гүй гэсэн баталгаа биш. [Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/).

Доорх нь код, өгөгдлийн бүтцээс бэлдсэн questionnaire-ийн ажлын хувилбар. Эцсийн archive/provider практиктай тулгаж эзэмшигч Connect-д батална; автоматаар илгээгээгүй.

| Өгөгдөл | App Privacy-д шалгах төрөл | Холболт / хэрэглээ |
|---|---|---|
| Имэйл, профайлын нэр, account UUID/username | Email Address, Name, User ID | Бүртгэлтэй холбоотой; App Functionality |
| Фото, story/reel/video, био, caption, comment, review, note, collection | Photos or Videos, Other User Content | Зохиогчийн бүртгэлтэй холбоотой; App Functionality |
| DM/group-ийн сонгосон харилцаа, тайлан | Emails or Text Messages; Other User Content | Илгээгч/хүлээн авагчтай холбоотой; App Functionality, хамгаалалт |
| Follow/follower болон group холбоос | Contacts (social graph) | Account-тай холбоотой; App Functionality. Утасны address book уншдаггүй |
| Хэрэглэгчийн өөрөө сонгосон газар, check-in | Location ангилал, нарийвчлал | Venue нь яг газрыг заадаг; төхөөрөмжийн GPS гэдгийг батлахгүй. Precise Location ангиллыг энэ холбоос болон media metadata-тай хамт нягтална |
| Хадгалалт, лайк, RSVP; зөвшөөрсөн pilot үйлдэл | Product Interaction | Бүртгэлтэй холбоотой; үндсэн ажиллагаа, тусдаа зөвшөөрсөн хэмжилтэд Analytics |
| Support/report хүсэлт, moderation audit | Customer Support / Other User Content / User ID | Бүртгэлтэй холбоотой; App Functionality, аюулгүй байдал |
| Provider IP/request/error лог | Diagnostics / Other Data Types, шаардлагатай location ангилал | Supabase/map provider-ийн бодит хадгалалт ба account холболтыг нягтална |

Зураг/видеоны бүх EXIF/GPS metadata-г арилгадаг гэж код батлахгүй; төхөөрөмжийн permission-ийг татгалзсан ч сонгосон файлын metadata-г тусад нь шалгана. Видеоны audio track, owner venue-ийн phone/address болон гуравдагч provider-ийн хадгалалтыг эцсийн data inventory-д оруулна. Optional analytics нь account-тай холбогддог учраас зөвхөн opt-in гэдэг шалтгаанаар disclosure-оос хасахгүй.

Age-rating questionnaire-ийн Step 2–7-г өмнө санал болгосон nightlife бүтээгдэхүүний чиглэлээр үргэлжлүүлэх эзэмшигчийн илэрхий зааврын дагуу бөглөж хадгалсан; хуудсыг бүтнээр дахин нээж баталгаажуулсан. Step 1-ийн UGC, social media, messaging **Yes**; parental controls, age assurance, unrestricted web access, Declared Age Range API-аар under-13 social media хязгаарлах болон paid advertising **No** хэвээр хадгалсан.

| Хадгалсан хэсэг | Хариулт |
|---|---|
| Step 2 — mature themes | Profanity **Infrequent**, horror **None**, alcohol/tobacco/drug references **Frequent** |
| Step 3 — medical/wellness | Medical **None**, wellness **No** |
| Step 4 — sexual/mature content | Mature/suggestive **Infrequent**, sexual content/nudity **None**, graphic sexual content **None** |
| Step 5 — violence | Дөрвөн хариулт бүгд **None** |
| Step 6 — gambling/contests | Simulated gambling **None**, contests **None**, gambling **No**, loot boxes **No** |
| Step 7 — calculated rating | **18+**; override хэрэггүй, харагдаагүй, хийгээгүй; optional suitability URL хоосон |

Хадгалсан ангилал **173 улс/бүсэд 18+**, **Бразил 16+**, **Солонгос 19+**; OS 26-аас өмнөх ерөнхий ангилал **17+**, бүсийн онцлог ангилалтай. Энэ нь аппын **18+ хамтын орчин** гэсэн бүтээгдэхүүний бодлого болон жинхэнэ age verification-оос тусдаа. **Declared Age Range API** хэрэгжээгүй тул **Social Media Age Restrictions = No** гэж хадгалсан; өөрийн мэдүүлгийн 18+ checkbox үүнийг орлохгүй. [Хадгалсан ангиллын нотолгоо](app-store/evidence/apple-store-setup.json), локал дэлгэрэнгүй screenshot: `build/audit/2026-11-04/app-store-age-rating-saved.png`.

Step 7-ийн category notice-ийн дагуу Lifestyle/Entertainment/Games ангилалтай энэ rating-ийн апп **Афганистан, Ирак, Ливи, Мальдив, Марокко, Саудын Араб, АНЭУ**-д түгээгдэхгүй. Одоогийн secondary **Lifestyle** учир энэ нөхцөл хамаарна; Brazil-ийн **Games** restriction хамаарахгүй. Availability-д зөвхөн Монголыг хадгалсан; бусад 174 улс/бүс боломжгүй. Content rights, App Privacy collection, export compliance болон review submission дуусаагүй.

Encryption: эх кодод HTTPS, Apple nonce-ийн SHA-256, платформын secure storage байна. Өөрийн шинэ encryption algorithm олдоогүй. Built bundle-ийн embedded SDK manifest inventory-г CI artifact-аас авч, Connect-ийн export-compliance асуулгыг эцсийн binary-гаар шийднэ. `ITSAppUsesNonExemptEncryption`-ийг эзэмшигчийн мэдүүлэггүйгээр автоматаар тохируулаагүй. [Apple export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/).

Screenshot storyboard: Explore map/газрын хэмнэл → газрын дэлгэрэнгүй → Feed/story → post location → profile/avatar/saved. Зөвшөөрөлтэй туршилтын контентоор бодит iOS build-ээс авна; одоогийн web/widget PNG-г native screenshot гэж нэрлэхгүй. Apple-ийн одоогийн хуудсаар iPhone Dynamic Island medium-ийн дор хаяж нэг зураг (жишээ нь **1206×2622** эсвэл **1179×2556**), iPad дэмждэг тул 13-inch зураг (жишээ нь **2064×2752** эсвэл **2048×2732**) хэрэгтэй. Upload хийх өдөр Connect-ийн шаардлагыг дахин тулгана. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Build → TestFlight → review дараалал

```sh
# Repo root, Flutter SDK PATH-д байх үед
python3 tools/deployment/ios_preflight.py --source-only
python3 tools/deployment/ios_preflight.py
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
sh tools/deployment/build_ios.sh --no-pub
```

`build_ios.sh` public backend config-ийг validator-аар үүсгэж, Device Preview-г хааж, unsigned compile хийнэ. Full Xcode байхгүй үед эхлээд зогсоно. `Runner.app` нь signed IPA эсвэл upload биш. Source preflight нь native dependency resolution/compile-ийг орлохгүй; SPM project-д Podfile байхгүйг дангаар нь алдаа гэж үзэхгүй.

[Signed build заавар](app-store/SIGNED_BUILD.md), `ios_signing.py` helper болон `ios-signed-candidate.yml` workflow бэлдсэн; шинэ signed CI run эхлээгүй, signed build гараагүй. Локал host дээр iPhoneOS SDK байхгүй, **0 valid signing identities**. Native Team **`DAVM2JZ4NN`** source-д оноосон нь signing identity/profile үүссэн гэсэн үг биш.

Дараа нь `ios/Runner.xcworkspace`-г Xcode-д нээж, эзэмшигчийн Team/App ID/provisioning-г сонгон төхөөрөмжийн тест хийнэ. Version/build number өмнө ашиглагдсан эсэхийг шалгаж, signed archive/IPA үүсгэж Validate App, privacy report, encryption мэдүүлгийг нягтална. Signing key, `.p8`, `.p12`, password, provisioning profile-ийг Git-д оруулахгүй.

Эхлээд **TestFlight internal** дээр төхөөрөмждөө суулгана. External tester-д анхны build-ийн Beta App Review шаардагдана. TestFlight approval нь public App Store approval биш. [TestFlight](https://developer.apple.com/testflight/).

Бүх blocker хаагдаж listing/contact/credentials/screenshots бэлэн болсон үед review submit хийнэ. Эзэмшигчийн сонгож хадгалсан **After Approval (`AFTER_APPROVAL`)** хэвээр: Apple зөвшөөрсний дараа автоматаар нийтэлнэ. Review submission, upload эсвэл нийтлэлт одоогоор хийгдээгүй.
