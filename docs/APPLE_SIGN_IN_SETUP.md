# Night Owl — Apple нэвтрэлтийн тохиргоо

2026-10-05. Одоогийн хүрээ нь код ба build бэлтгэх; Apple/Supabase тохиргоог өөрчлөөгүй, серверт deploy болон дэлгүүрт нийтлээгүй.

## Одоогийн төлөв

Эхлэл, нэвтрэх, бүртгүүлэх дэлгэцийн Apple товч веб, Android, iOS-д харагдана. iOS нь `sign_in_with_apple` 8.2.0-оор native credential авч, SHA-256 nonce болон identity token-ийг Supabase `signInWithIdToken` урсгалаар баталгаажуулна. Web/Android нь Supabase OAuth ашиглана. Provider идэвхтэй эсэхийг public settings-ээс эхлээд шалгаж, идэвхгүй эсвэл сүлжээний алдааг апп дотор харуулна. iOS-ийн Debug/Profile/Release тохиргоонд Sign in with Apple entitlement холбоотой.

2026-10-05-нд `GET /auth/v1/settings`-ийг read-only шалгахад `apple=false`, `google=true`, `email=true` байсан. Иймээс Apple-ийн бодит нэвтрэлт одоогоор идэвхгүй. Товч болон урсгалын код байгаа нь серверийн тохиргоо бүрэн, нэвтрэлт амжилттай гэсэн баталгаа биш. Apple account ашигласан бүтэн нэвтрэлт, iOS binary/device туршилт хийгдээгүй.

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
| Supabase → production web callback | Бодит HTTPS web origin-ийг release хийхдээ нэмнэ |

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
