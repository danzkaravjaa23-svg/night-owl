# Night Owl — Apple нэвтрэлтийн тохиргоо

2026-11-04-нд шинэчилсэн. Apple Developer membership **Active**, Team ID **`DAVM2JZ4NN`** батлагдсан. **Night Owl UB** description-тай explicit App ID **`com.nightowl.ub.nightOwlUb`** бүртгэгдэж, Sign in with Apple capability **primary App ID** байдлаар идэвхжсэн. [App Store Connect app record](https://appstoreconnect.apple.com/apps/6830714135/distribution) үүссэн: Apple ID **`6830714135`**, iOS, **Night Owl UB**, primary language **en-US**, SKU **`night-owl-ub-ios`**, төлөв **Prepare for Submission**. Энэ нь provider тохиргоо эсвэл signed build биш.

Эзэмшигч Agree дарсан гэж мэдээлсэн ч шинэчилсэн license banner дараа нь харагдсан хэвээр тул асуудал шийдэгдсэн гэж тэмдэглэхгүй; агент гэрээ зөвшөөрөөгүй.

Connect-ийн **1.0.0** хувилбарт promotional text, description, keywords болон support URL хадгалагдсан; App Information-д subtitle, **Social Networking / Lifestyle** ангилал хадгалагдсан. Эзэмшигчийн сонгосон **After Approval** автомат нийтлэх тохиргоог хадгалсан.

Privacy Policy URL **https://nightowl-ub.netlify.app/privacy.html** хадгалсан. US/USD **0.00** суурь үнийн schedule батлагдсан; хадгалсан Prices popover-ийг дахин нээж бүх **175** дүн **0.00** байгааг шалгасан. Түгээх улс/бүс сонгоогүй; App Privacy collection questionnaire эхлээгүй/нийтлээгүй. Насны асуулга **Step 2** дээр контентийн давтамжийн хариулт хүлээж байгаа; эцсийн rating хадгалагдаагүй. [Бүртгэл ба metadata нотолгоо](app-store/evidence/apple-store-setup.json).

Түлхүүр/signing asset, шинэ signed build, upload, review submission үүсээгүй; Supabase provider ба production өгөгдөл энэ Apple бүртгэлээр өөрчлөгдөөгүй. [Эзэмшигчийн дараагийн алхам](app-store/OWNER_NEXT_STEPS.md).

**Насны боломжийн хүрээ:** Connect-ийн Social Media Age Restrictions асуулт Declared Age Range API шаардаж байна. Энэ API одоогийн аппад хэрэгжээгүй; 18+ checkbox зөвхөн өөрийн мэдүүлэг тул **No** draft сонголттой. Насны асуулга эцэслэн хадгалагдаагүй, Apple-ийн эцсийн насны ангилал батлагдаагүй.

## Одоогийн төлөв

Эхлэл, нэвтрэх, бүртгүүлэх дэлгэцийн Apple товч веб, Android, iOS-д харагдана. iOS нь `sign_in_with_apple` 8.2.0-оор native credential авч, SHA-256 nonce болон identity token-ийг Supabase `signInWithIdToken` урсгалаар баталгаажуулна. Web/Android нь Supabase OAuth ашиглана. Provider идэвхтэй эсэхийг public settings-ээс эхлээд шалгаж, идэвхгүй эсвэл сүлжээний алдааг апп дотор харуулна. iOS-ийн Debug/Profile/Release тохиргоонд Sign in with Apple entitlement холбоотой.

2026-11-03T06:51:19Z-д production `GET /auth/v1/settings`-ийг read-only шалгахад `apple=false`, `google=true`, `email=true` байсан. Энэ нь тухайн үеийн production нотолгоо; staging provider эсвэл өнөөдрийн dashboard тохиргоог батлахгүй. Apple account ашигласан бүтэн нэвтрэлт болон бодит iPhone/device туршилт хийгдээгүй. Unsigned CI compile-ийн нотолгоо нь бодит login/revoke эсвэл эцсийн signed candidate-ийн QA биш; шинэ build-ийн төлөвийг [release тайлан](RELEASE_READINESS.md)-гаас авна.

## Identifier болон callback

Native iOS App ID / bundle ID нь **`com.nightowl.ub.nightOwlUb`**, native OAuth callback нь **`com.nightowl.ub://login-callback/`**. Эхнийхийг [Xcode project](../ios/Runner.xcodeproj/project.pbxproj), хоёр дахь утгыг [callback helper](../lib/core/utils/auth_callback.dart) ба [Info.plist](../ios/Runner/Info.plist) батална. Team ID **`DAVM2JZ4NN`** dashboard-аас батлагдсан; Xcode source-д `DEVELOPMENT_TEAM` хараахан оноогоогүй. Бүртгэгдсэн Services ID болон staging-д зориулсан тусдаа native bundle ID одоогоор батлагдаагүй; таамгаар нөхөхгүй.

| Зориулалт | Staging — эхлээд энд шалгана | Одоогийн production |
|---|---|---|
| Supabase project | `sreojqqqhdzkfsrbvlpl` | `jbbdnpsvstwxtgtjoeru` |
| Backend origin | `https://sreojqqqhdzkfsrbvlpl.supabase.co` | `https://jbbdnpsvstwxtgtjoeru.supabase.co` |
| Apple Services ID → Website domain | `sreojqqqhdzkfsrbvlpl.supabase.co` | `jbbdnpsvstwxtgtjoeru.supabase.co` |
| Apple → Supabase Return URL | `https://sreojqqqhdzkfsrbvlpl.supabase.co/auth/v1/callback` | `https://jbbdnpsvstwxtgtjoeru.supabase.co/auth/v1/callback` |
| Supabase → web redirect allow-list | `http://127.0.0.1:8776/` — одоогийн локал preview | `https://nightowl-ub.netlify.app/` |
| Supabase → native OAuth redirect allow-list | `com.nightowl.ub://login-callback/` | `com.nightowl.ub://login-callback/` |
| Web deletion popup redirect | Тусдаа бодит HTTPS staging page сонгож, бүртгэх шаардлагатай | Бодит HTTPS app page сонгож, бүртгэх шаардлагатай |

Энэ хүснэгт нь тохируулах утгууд; allow-list/provider дээр хадгалагдсан гэсэн нотолгоо биш. Staging project-ийг [acceptance runner](../tools/deployment/tests/hosted_staging_acceptance.py), production default-ийг [AppConstants](../lib/core/constants/app_constants.dart) батална. `8776` preview нь тусдаа staging өгөгдөлтэй; production-ийн хуучин аккаунт автоматаар энд үүсэхгүй.

Apple-д **Supabase-ийн HTTPS callback** бүртгэнэ. Supabase-д **апп руу буцах redirect** бүртгэнэ. Web callback helper нь query/hash-ийг хасаж, origin/path/port-ийг хадгалдаг тул `#/auth` оруулахгүй; `localhost`, `127.0.0.1`, `8765`, `8776` нь ижил URL биш. `8765` preview-г дахин хэрэглэх бол холбох төслийн allow-list-д яг тэр URL-ийг тусад нь нягтална. Production-д exact URL хэрэглэнэ. Site URL нь `redirectTo` байхгүй үеийн default тул staging-ийг production web рүү буцаадаг байдлаар тохируулахгүй. [Supabase redirect заавар](https://supabase.com/docs/guides/auth/redirect-urls).

Build-ийн `BACKEND_URL` болон `BACKEND_PUBLIC_KEY` нэг төслийнх байх ёстой. Staging preview-ийн тохиргоог release build-д санамсаргүй ашиглахгүй; signed candidate бүрийн endpoint, source commit, version/build number-ийг тайланд тэмдэглэнэ. Одоогийн native App ID ижил тул staging database тусдаа байгаа нь Apple authorization тусдаа гэсэн баталгаа биш; login/revoke туршилтад production-д ашиглаагүй disposable Apple account хэрэглэнэ.

## Сервер ба Apple Developer тохиргоо

1. Membership **Active**, Team **`DAVM2JZ4NN`**, native App ID **`com.nightowl.ub.nightOwlUb`** болон Sign in with Apple primary capability бүртгэгдсэн. Дараагийн Xcode team/provisioning profile энэ capability-г дэмжих ёстой; repository дахь entitlement болон App ID бүртгэл ганцаараа signed build эсвэл provider login-ийг батлахгүй. [Apple-ийн capability ба web association заавар](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web/).
2. Бүртгэгдсэн Services ID-г primary App ID-тай холбож, сонгосон орчны Website domain/Return URL-ийг тохируулна. Staging/production Services ID тусад нь ашиглахыг бэлтгэлийн сонголт болгон санал болгож байна; энэ нь аль нэг ID үүссэн гэсэн үг биш. Сонгосон Supabase төслийн Auth → Providers → Apple-д тухайн Services ID-г Client IDs-ийн **эхний** утга, `com.nightowl.ub.nightOwlUb`-г нэмэлт native audience болгон оруулна. Web OAuth эхний audience-ийг ашигладаг. Staging тохиргоог шалгасны дараа production-ийн өөрийн утгуудаар тусад нь тохируулна. [Supabase Apple тохиргоо](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple#configuration).
3. Apple Team ID, Key ID, `.p8` signing key-ээр үүсгэсэн signed client secret-ийг зөвхөн Supabase/server тохиргоонд хадгална. Flutter client, Dart define, repo, чатад signing key/secret хийхгүй. OAuth secret-ийг зургаан сарын хугацаа дуусахаас өмнө шинэчилнэ. Native-only урсгалд энэ rotation шаардлагагүй боловч энэ апп web/Android OAuth мөн ашиглаж байгаа. [Supabase-ийн secret rotation заавар](https://supabase.com/docs/guides/auth/social-login/auth-apple).
4. Supabase Auth → URL Configuration-д дээрх хүснэгтийн **тухайн орчны** web/native redirect-ийг нэмнэ. Dashboard дээр төслийн ref-ийг дахин тулгаж, Site URL болон бодит login return хоёрыг шалгана.
5. Hide My Email ашиглах хэрэглэгчид имэйл хүргэх шаардлагатай бол өөрийн илгээгч domain-ийг Apple private relay-д бүртгэнэ. [Supabase Apple заавар](https://supabase.com/docs/guides/auth/social-login/auth-apple#configuration).

## Тохиргооны дараах баталгаажуулалт

- Public settings-ийн `external.apple` үнэхээр `true` болсон эсэхийг шалгана. Энэ нь зөвхөн provider-ийн flag; credential, callback болон session-ийг тусад нь шалгах шаардлагатай.
- Web дээр Apple зөвшөөрлийн хуудас нээгдэж, апп руу буцан Supabase session үүсэхийг шинэ болон өмнөх хаягаар туршина. Android дээр external browser → native deep link буцах урсгалыг шалгана.
- Signing/provisioning тохируулсан бодит iOS төхөөрөмж дээр native credential → Supabase session-ийг туршина. [Supabase Dart identity-token урсгал](https://supabase.com/docs/reference/dart/auth-signinwithidtoken).
- Цуцлах, хугацаа дууссан/буруу secret, буруу audience, сүлжээ тасрах, дахин нэвтрэх болон гараад өөр хаягаар орох үед алдаа ба session зөв ажиллахыг шалгана.
- Apple нэрийг зөвхөн эхний зөвшөөрөлд өгөх боломжтой. Код ирсэн нэрийг хоосон `full_name` metadata-д хадгалж, хэрэглэгчийн өмнө оруулсан нэрийг солихгүй; нэр ирээгүй үед профайл setup-ээр нөхнө. [Supabase-ийн name metadata тайлбар](https://supabase.com/docs/guides/auth/social-login/auth-apple).

Туршилтын тайланд session/token/identity token-ийг бүү хадгал. Provider тохиргоо ба бодит төхөөрөмжийн шалгалт дуусах хүртэл Apple нэвтрэлтийг production-д баталгаажсан, эсвэл аппыг store submission-д бэлэн гэж үзэхгүй. Бусад release prerequisite нь [release тайланд](RELEASE_READINESS.md) хэвээр.

## Signed build болон TestFlight-д хэрэгтэй зүйл

Sign in with Apple-ийн `.p8` нь OAuth exchange/revoke-д зориулсан серверийн түлхүүр. IPA-д гарын үсэг зурах distribution certificate/private key, provisioning profile болон App Store Connect upload access нь тусдаа зориулалттай.

| Алхам | Бодитоор батлах зүйл |
|---|---|
| Membership / team | Apple Developer membership **Active**, Team **`DAVM2JZ4NN`** батлагдсан; source-д одоогоор `DEVELOPMENT_TEAM` байхгүй. |
| App record | [Apple ID `6830714135`](https://appstoreconnect.apple.com/apps/6830714135/distribution) үүссэн: iOS, **Night Owl UB**, `com.nightowl.ub.nightOwlUb`, **en-US**, SKU **`night-owl-ub-ios`**; **Prepare for Submission**. License banner хэвээр ажиглагдсан тул Account Holder-ийн гэрээний төлөвийг нягтална. [Apple app record заавар](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/). |
| Native signing | Xcode-д `ios/Runner.xcworkspace` нээж Runner-ийн зөв Team, bundle ID, Sign in with Apple capability-г шалгана. Automatic signing хэрэглэвэл Xcode distribution profile-ийг удирдана; manual signing сонговол тохирох explicit App ID, distribution certificate/private key, App Store Connect profile хэрэгтэй. [Apple provisioning заавар](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/). |
| Candidate build | Upload-д нийцэх Xcode/SDK, яг сонгосон backend, `DEVICE_PREVIEW=false`, давтагдаагүй build number, commit. `tools/deployment/build_ios.sh` нь зөвхөн unsigned `Runner.app` гаргадаг; signed archive/IPA болон upload хийхгүй. |
| Archive / upload | Signed Release archive-ийг Validate App хийгээд App Store Connect руу upload хийнэ. Bundle/version/build-ийг app record-той тулгана; Apple processing дууссаны дараа TestFlight-д харагдсаныг шалгана. [Apple upload заавар](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/). |
| Device acceptance | Эхлээд internal TestFlight: iPhone/iPad дээр login, revoke/delete, media, permission, moderation ба recovery-г [review test plan](app-store/REVIEW_TEST_PLAN.md)-аар шалгана. Production rollout болон App Review нь эдгээр gate дууссаны дараах алхам. |

Нууц түлхүүр, certificate export/password, session, provisioning profile-ийг Git/тайлан/чатад хийхгүй. Apple login `.p8`, distribution key болон App Store Connect API key-г нэг түлхүүр мэт орлуулж ашиглахгүй. App Store record үүссэн; signing asset, signed archive/IPA болон TestFlight upload хараахан үүсээгүй.

## Account deletion-тай хамт дуусгах зүйл

Шинэ `delete-account` handler нь owner-bound nonce → fresh Apple identity/code → серверийн JWKS/issuer/audience/subject/nonce баталгаажуулалт → code exchange → refresh token revoke гэсэн урсгалтай. Устгалын journal Apple revoke checkpoint-ийг хадгалж, raw Apple token/code/key-г хадгалахгүй. iOS client нь Supabase session-ийг солихгүйгээр дахин Apple credential авна. Web нь official Apple JS SDK-г lazy load хийгээд шинэ товшилтоор popup нээнэ. Android дээр шинэ deletion proof одоогоор fail-closed; iPhone эсвэл web гэсэн заавартай.

Устгалын серверт `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`; web урсгалд нэмэлт `APPLE_WEB_CLIENT_ID`, `APPLE_WEB_REDIRECT_URI` хэрэгтэй. Эдгээрийг тухайн орчны Edge function-ийн server configuration-д тохируулна; client нь зөвшөөрөгдсөн ID/redirect-ийг server challenge-аас авдаг. Private key болон generated client secret-ийг Git/Dart define/чатад хийхгүй. Web deletion popup-ийн HTTPS redirect-ийг Apple Services ID-д **Supabase login callback-оос тусад нь** бүртгэнэ. Fresh code-ийг backend exchange хийх redirect URI нь яг ижил байна. [Apple JS-ийн Website URL тохиргоо](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple#using-sign-in-with-apple-js).

Одоогийн `http://127.0.0.1:8776/` дээр local OAuth login-ийг Supabase HTTPS callback-аар шалгаж болно. Харин Night Owl-ийн deletion challenge validator нь HTTPS redirect шаарддаг тул local preview дангаараа бодит web deletion acceptance-ийг хангахгүй. Түүнд тусдаа HTTPS staging app page-ийг сонгож бүртгэх, эсвэл signing-тай iPhone дээр native урсгал шалгах хэрэгтэй. Сонгоогүй staging domain, Services ID эсвэл callback route-ийг энэ заавар бэлэн гэж тэмдэглэхгүй.

`008` migration болон Edge function-ийн staging/enable заавар [backend README](../supabase/functions/delete-account/README.md)-д бий. Receipt-only status нь Auth устсаны дараах үр дүнг шалгахын тулд зөвхөн энэ function-д gateway `verify_jwt=false` хэрэглэнэ; prepare/delete бүрийг handler `auth.getUser()`-ээр баталгаажуулдаг. Энэ нь бүх endpoint-ийн auth-ийг унтраах тохиргоо биш.

Криптографийн synthetic тест болон unsigned native build PASS нь Apple service-тэй жинхэнэ revoke/login хийсэн баталгаа биш. Membership/keys/provider тохируулсны дараа disposable Apple account дээр cancel, Hide My Email, nonce expiry, revoke failure, retry болон completion recovery-г шалгана. [Apple deletion шаардлага](https://developer.apple.com/support/offering-account-deletion-in-your-app/).


### Deletion integration ба төхөөрөмжийн acceptance

Login callback болон deletion reauthorization нь тусдаа урсгал. `prepare` нь caller-ийг баталж, owner-bound 256-bit receipt болон шаардлагатай үед таван минутын raw nonce өгнө. Client nonce-г SHA-256-аар нэг удаа hash хийж Apple-д явуулна; raw nonce, code болон identity token нь лог, URL, persistent receipt-д орохгүй. Backend зөвшөөрсөн native bundle audience эсвэл web Services ID-г сонгоно; client-ийн arbitrary audience/redirect-ийг ашиглахгүй.

Web дээр official SDK-ийг анхнаас нь бүх page-д ачаалахгүй. Server challenge болон SDK ачаалсны дараах **Apple-ээр баталгаажуулах** гэсэн шинэ товшилтоор popup нээнэ. Production HTTPS origin, Services ID, яг ижил return URL, popup/browser policy болон хэрэв байгаа бол CSP-ийг бодитоор туршина. SDK load, popup cancel, хугацаа дуусах эсвэл өөр Apple account сонгоход delete phase амжилттай гэж үзэхгүй, Supabase session-ийг өөр account болгохгүй.

Устгал нь secure storage-д owner UUID, opaque status receipt, эхэлсэн UTC цаг гэсэн гурван утга л хадгална. Restart эсвэл Auth устсаны дараа хүчинтэй receipt байвал signed-out эхлэл дээр **Өмнөх устгалын төлөвийг шалгах** холбоос гарна. Энэ нь `/settings/delete-account` руу capability-г URL-д хийхгүйгээр нээнэ. Receipt-only status нь шинэ устгал эхлүүлэх эрхгүй; deliberate retry нь эхлээд төлөв шалгана. Өөр хаяг эсвэл шинэ session-д хуучин completion хариу sign-out хийх ёсгүй.

Client receipt preparation-аас 30 хоног; completed server journal completion-оос 30 хоног хадгалагдана. Completed journal-ийн pruning-ийг operator тохируулна. Partial failed job-ийг хугацаа өнгөрлөө гээд автоматаар устгаж/unfreeze хийхгүй. Apple revoke checkpoint амжилттай боловч дараагийн Storage/Auth cleanup тасарсан бол verified checkpoint-оос сэргээнэ; дахин login/Apple identity өөрчлөгдвөл өмнөх checkpoint хүчингүй болно. Эдгээр нь глобал atomic transaction гэсэн баталгаа биш.

Бодит disposable Apple account-аар native болон web урсгал, cancellation/wrong identity, Hide My Email, five-minute expiry, SDK/popup failure, linked identity change, network/Storage/Auth partial failure, app restart, receipt-only completion болон өөр session хамгаалалтыг [N04/N13 test plan](app-store/REVIEW_TEST_PLAN.md)-аар шалгана. 008/009/Edge/client хамт staging acceptance хийж, дараа enable хийнэ. Server key/provider configuration, signed archive, owner review contact/data forms болон App Store submission энэ кодоор хийгдээгүй.
