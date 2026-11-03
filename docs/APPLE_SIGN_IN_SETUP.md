# Night Owl — Apple нэвтрэлтийн тохиргоо

2026-11-03-нд App Store бэлтгэлээр шинэчилсэн. Код ба тохиргооны заавар бэлэн; Apple Developer гишүүнчлэл идэвхгүй, provider болон native signing/device login хүлээгдэж байна. Энэ бэлтгэл Apple/Supabase тохиргоог өөрчлөөгүй.

## Одоогийн төлөв

Эхлэл, нэвтрэх, бүртгүүлэх дэлгэцийн Apple товч веб, Android, iOS-д харагдана. iOS нь `sign_in_with_apple` 8.2.0-оор native credential авч, SHA-256 nonce болон identity token-ийг Supabase `signInWithIdToken` урсгалаар баталгаажуулна. Web/Android нь Supabase OAuth ашиглана. Provider идэвхтэй эсэхийг public settings-ээс эхлээд шалгаж, идэвхгүй эсвэл сүлжээний алдааг апп дотор харуулна. iOS-ийн Debug/Profile/Release тохиргоонд Sign in with Apple entitlement холбоотой.

2026-11-03T06:51:19Z-д `GET /auth/v1/settings`-ийг read-only шалгахад `apple=false`, `google=true`, `email=true` байсан. Иймээс Apple-ийн бодит нэвтрэлт одоогоор идэвхгүй. Товч болон урсгалын код байгаа нь серверийн тохиргоо бүрэн, нэвтрэлт амжилттай гэсэн баталгаа биш. Apple account ашигласан бүтэн нэвтрэлт болон бодит iPhone/device туршилт хийгдээгүй. Unsigned CI compile-ийн нотолгоо нь бодит login/revoke эсвэл эцсийн signed candidate-ийн QA биш; шинэ build-ийн төлөвийг [release тайлан](RELEASE_READINESS.md)-гаас авна.

## Identifier болон callback

| Зориулалт | Утга |
|---|---|
| Native iOS App ID / bundle ID | `com.nightowl.ub.nightOwlUb` |
| Apple Services ID | Apple Developer-д өөрийн Services ID үүсгэнэ; Supabase Client IDs-ийн эхний утга байна |
| Supabase project origin | `https://jbbdnpsvstwxtgtjoeru.supabase.co` |
| Apple Services ID → Website domain | `jbbdnpsvstwxtgtjoeru.supabase.co` |
| Apple → Supabase Return URL | `https://jbbdnpsvstwxtgtjoeru.supabase.co/auth/v1/callback` |
| Supabase → native app callback | `com.nightowl.ub://login-callback/` |
| Supabase → локал web callback | `http://127.0.0.1:8765/` |
| Supabase → production web callback | `https://nightowl-ub.netlify.app/` (allow-list-д бодитоор байгаа эсэхийг dashboard-аар нягтална) |

Apple-ийн Return URL болон Supabase-ийн апп руу буцах URL нь өөр зориулалттай. Apple-д Supabase HTTPS callback-ийг бүртгэнэ; локал web болон native deep link-ийг Supabase redirect allow-list-д нэмнэ.

## Сервер ба Apple Developer тохиргоо

1. Apple Developer-д дээрх native App ID-г бүртгэж, Sign in with Apple capability-г идэвхжүүлнэ. Xcode team/provisioning profile энэ capability-г дэмжих ёстой; repository дахь entitlement ганцаараа хангалтгүй. [Package-ийн платформын заавар](https://pub.dev/packages/sign_in_with_apple).
2. Services ID-г native App ID-тай холбож, дээрх Website domain болон Return URL-ийг тохируулна. Supabase Auth → Providers → Apple-д Services ID-г Client IDs-ийн **эхний** утга, `com.nightowl.ub.nightOwlUb`-г нэмэлт native audience болгон оруулж provider-ийг enable хийнэ. [Supabase Apple тохиргоо](https://supabase.com/docs/guides/auth/social-login/auth-apple#configuration).
3. Apple Team ID, Key ID, `.p8` signing key-ээр үүсгэсэн signed client secret-ийг зөвхөн Supabase/server тохиргоонд хадгална. Flutter client, Dart define, repo, чатад signing key/secret хийхгүй. OAuth secret-ийг зургаан сарын хугацаа дуусахаас өмнө шинэчилнэ. Native-only урсгалд энэ rotation шаардлагагүй боловч энэ апп web/Android OAuth мөн ашиглаж байгаа. [Supabase-ийн secret rotation заавар](https://supabase.com/docs/guides/auth/social-login/auth-apple).
4. Supabase Auth → URL Configuration-д локал web, native callback болон бодит production origin-ийг allow-list-д нэмнэ. Production Site URL-ийг бодит HTTPS origin-оор тохируулна.
5. Hide My Email ашиглах хэрэглэгчид имэйл хүргэх шаардлагатай бол өөрийн илгээгч domain-ийг Apple private relay-д бүртгэнэ. [Supabase Apple заавар](https://supabase.com/docs/guides/auth/social-login/auth-apple#configuration).

## Тохиргооны дараах баталгаажуулалт

- Public settings-ийн `external.apple` үнэхээр `true` болсон эсэхийг шалгана. Энэ нь зөвхөн provider-ийн flag; credential, callback болон session-ийг тусад нь шалгах шаардлагатай.
- Web дээр Apple зөвшөөрлийн хуудас нээгдэж, апп руу буцан Supabase session үүсэхийг шинэ болон өмнөх хаягаар туршина. Android дээр external browser → native deep link буцах урсгалыг шалгана.
- Signing/provisioning тохируулсан бодит iOS төхөөрөмж дээр native credential → Supabase session-ийг туршина. [Supabase Dart identity-token урсгал](https://supabase.com/docs/reference/dart/auth-signinwithidtoken).
- Цуцлах, хугацаа дууссан/буруу secret, буруу audience, сүлжээ тасрах, дахин нэвтрэх болон гараад өөр хаягаар орох үед алдаа ба session зөв ажиллахыг шалгана.
- Apple нэрийг зөвхөн эхний зөвшөөрөлд өгөх боломжтой. Код ирсэн нэрийг хоосон `full_name` metadata-д хадгалж, хэрэглэгчийн өмнө оруулсан нэрийг солихгүй; нэр ирээгүй үед профайл setup-ээр нөхнө. [Supabase-ийн name metadata тайлбар](https://supabase.com/docs/guides/auth/social-login/auth-apple).

Туршилтын тайланд session/token/identity token-ийг бүү хадгал. Provider тохиргоо ба бодит төхөөрөмжийн шалгалт дуусах хүртэл Apple нэвтрэлтийг production-д баталгаажсан, эсвэл аппыг store submission-д бэлэн гэж үзэхгүй. Бусад release prerequisite нь [release тайланд](RELEASE_READINESS.md) хэвээр.

## Account deletion-тай хамт дуусгах зүйл

Шинэ `delete-account` handler нь owner-bound nonce → fresh Apple identity/code → серверийн JWKS/issuer/audience/subject/nonce баталгаажуулалт → code exchange → refresh token revoke гэсэн урсгалтай. Устгалын journal Apple revoke checkpoint-ийг хадгалж, raw Apple token/code/key-г хадгалахгүй. iOS client нь Supabase session-ийг солихгүйгээр дахин Apple credential авна. Web нь official Apple JS SDK-г lazy load хийгээд шинэ товшилтоор popup нээнэ. Android дээр шинэ deletion proof одоогоор fail-closed; iPhone эсвэл web гэсэн заавартай.

Серверт `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`; web-д `APPLE_WEB_CLIENT_ID`, `APPLE_WEB_REDIRECT_URI` хэрэгтэй. Эдгээрийг Git/Dart define/чатад хийхгүй. Web deletion popup-ийн HTTPS redirect-ийг Apple Services ID-д **Supabase login callback-оос тусад нь** бүртгэнэ. Fresh code-ийг backend exchange хийх redirect URI нь яг ижил байна. App origin/domain болон redirect-ийг сонгохдоо popup буцах бодит HTTPS URL-ийг ашиглана.

`008` migration болон Edge function-ийн staging/enable заавар [backend README](../supabase/functions/delete-account/README.md)-д бий. Receipt-only status нь Auth устсаны дараах үр дүнг шалгахын тулд зөвхөн энэ function-д gateway `verify_jwt=false` хэрэглэнэ; prepare/delete бүрийг handler `auth.getUser()`-ээр баталгаажуулдаг. Энэ нь бүх endpoint-ийн auth-ийг унтраах тохиргоо биш.

Криптографийн synthetic тест болон unsigned native build PASS нь Apple service-тэй жинхэнэ revoke/login хийсэн баталгаа биш. Membership/keys/provider тохируулсны дараа disposable Apple account дээр cancel, Hide My Email, nonce expiry, revoke failure, retry болон completion recovery-г шалгана. [Apple deletion шаардлага](https://developer.apple.com/support/offering-account-deletion-in-your-app/).


### Deletion integration ба төхөөрөмжийн acceptance

Login callback болон deletion reauthorization нь тусдаа урсгал. `prepare` нь caller-ийг баталж, owner-bound 256-bit receipt болон шаардлагатай үед таван минутын raw nonce өгнө. Client nonce-г SHA-256-аар нэг удаа hash хийж Apple-д явуулна; raw nonce, code болон identity token нь лог, URL, persistent receipt-д орохгүй. Backend зөвшөөрсөн native bundle audience эсвэл web Services ID-г сонгоно; client-ийн arbitrary audience/redirect-ийг ашиглахгүй.

Web дээр official SDK-ийг анхнаас нь бүх page-д ачаалахгүй. Server challenge болон SDK ачаалсны дараах **Apple-ээр баталгаажуулах** гэсэн шинэ товшилтоор popup нээнэ. Production HTTPS origin, Services ID, яг ижил return URL, popup/browser policy болон хэрэв байгаа бол CSP-ийг бодитоор туршина. SDK load, popup cancel, хугацаа дуусах эсвэл өөр Apple account сонгоход delete phase амжилттай гэж үзэхгүй, Supabase session-ийг өөр account болгохгүй.

Устгал нь secure storage-д owner UUID, opaque status receipt, эхэлсэн UTC цаг гэсэн гурван утга л хадгална. Restart эсвэл Auth устсаны дараа хүчинтэй receipt байвал signed-out эхлэл дээр **Өмнөх устгалын төлөвийг шалгах** холбоос гарна. Энэ нь `/settings/delete-account` руу capability-г URL-д хийхгүйгээр нээнэ. Receipt-only status нь шинэ устгал эхлүүлэх эрхгүй; deliberate retry нь эхлээд төлөв шалгана. Өөр хаяг эсвэл шинэ session-д хуучин completion хариу sign-out хийх ёсгүй.

Client receipt preparation-аас 30 хоног; completed server journal completion-оос 30 хоног хадгалагдана. Completed journal-ийн pruning-ийг operator тохируулна. Partial failed job-ийг хугацаа өнгөрлөө гээд автоматаар устгаж/unfreeze хийхгүй. Apple revoke checkpoint амжилттай боловч дараагийн Storage/Auth cleanup тасарсан бол verified checkpoint-оос сэргээнэ; дахин login/Apple identity өөрчлөгдвөл өмнөх checkpoint хүчингүй болно. Эдгээр нь глобал atomic transaction гэсэн баталгаа биш.

Бодит disposable Apple account-аар native болон web урсгал, cancellation/wrong identity, Hide My Email, five-minute expiry, SDK/popup failure, linked identity change, network/Storage/Auth partial failure, app restart, receipt-only completion болон өөр session хамгаалалтыг [N04/N13 test plan](app-store/REVIEW_TEST_PLAN.md)-аар шалгана. 008/009/Edge/client хамт staging acceptance хийж, дараа enable хийнэ. Server key/provider configuration, signed archive, owner review contact/data forms болон App Store submission энэ кодоор хийгдээгүй.
