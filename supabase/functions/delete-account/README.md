# Бүртгэл устгах: локал бэлтгэл

2026-11-03. **Deploy/enable хийгдээгүй.** Production хэрэглэгчийг туршилтаар устгахгүй. Apple Developer-ийн төлбөр, App Store upload энэ ажлын хүрээнээс гадуур.

## Гэрээ

- `POST` + хүчинтэй caller Bearer JWT + `{"confirmation":"DELETE"}` шаардана. Body-ийн user ID, bucket болон path-ийг сонголт гэж ашиглахгүй.
- `ACCOUNT_DELETION_ENABLED` яг `true` биш бол `503 / deletion_unavailable`; admin client, cleanup үүсэхгүй. Анхдагч нь идэвхгүй.
- Caller-ийг `auth.getUser()`-ээр серверээс батална. Алдаатай хариунд user object байсан ч зөвшөөрөл гэж үзэхгүй.
- Apple-linked account: grant revoke бэлэн болоогүй тул `409 / apple_revocation_required`, cleanup эхлэхгүй. Apple provider-ийг идэвхжүүлэхээс өмнө token revoke хэрэгжүүлж тестлэнэ.
- Дөрвөн bucket-ийн **caller UUID prefix** дахь хавтас/файлыг бүгдийг нь жагсаасны дараа л устгал эхэлнэ. Жагсаалтын алдаа, null/эвдэрсэн response, давхардсан entry-г хоосон хавтас гэж үзэхгүй. Гүн 8, bucket тус бүр 20,000 file, хавтас+файл нийт 30,000 entry cap-тай.
- Storage cleanup-ийн response заавал array байна. Cleanup-ийн дараа дөрвөн UUID prefix-ийг дахин шалгаж, бүгд хоосон үед л hard Auth deletion хийнэ. Remove-ийн амжилттай боловч хоосон/no-op хариуг дангаар нь баталгаа гэж үзэхгүй. Auth deletion response-ийн user ID caller-тай яг таарах ёстой. Амжилт нь `200 / {"ok":true,"user_id":"<caller>"}`. Энэ нь legacy хувийн өгөгдлийн бүх байршлыг аудит хийсэн баталгаа биш.
- Cleanup/Auth хүсэлт эхэлсний дараах алдаа `500 / deletion_incomplete / cleanup_started=true`; rollback амлахгүй. Клиент амжилт харуулахгүй, автоматаар дахин илгээхгүй. Сүлжээ timeout болсон нь серверийн хүсэлтийг цуцлахгүй.
- Шууд дахин баталгаажуулж илгээхэд үлдсэн файлуудыг шинээр жагсаана. Эцсийн дахин жагсаалтад харагдсан шинэ upload байвал Auth устгахгүй; тэр шалгалтын дараах зэрэг upload-ийг lock хийхгүй. Энэ нь durable job, concurrency lock эсвэл exactly-once баталгаа биш.

## Локал шалгалт

SDK `@supabase/supabase-js@2.118.0`-ийг яг pin хийсэн. Deno 2.9.8 дээр typecheck ба жинхэнэ SDK-ийн localhost HTTP contract тест, Node VM дээр сүлжээгүй SDK doubles ашиглана:

```sh
deno check --no-lock supabase/functions/delete-account/index.ts
deno test --no-lock --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY,ACCOUNT_DELETION_ENABLED --allow-net=127.0.0.1 supabase/functions/delete-account/tests/handler_test.ts
node --experimental-vm-modules --test tools/deployment/tests/delete_account_handler.test.mjs
flutter test --no-pub test/account_deletion_test.dart
```

66 Node VM тест, Deno-ийн 13 HTTP алхам, Flutter-ийн 30 deletion тест PASS. Deno тест нь production entry point, жинхэнэ pinned SDK-ийг loopback Auth/Storage API doubles-той ажиллуулна; hosted Supabase/Auth/Storage/FK integration биш. Хувийн key, live өгөгдөл ашиглахгүй. Deno check дангаараа function ажиллуулахгүй. `--no-lock` учраас бүх transitive dependency lock хийгдсэн гэж үзэхгүй.

`run_account_deletion_boundaries_fixture.mjs` нь тусгаарласан PostgreSQL дээр хуучин profile DELETE болон бусдын Storage metadata устгах trigger-ийн асуудлыг эхлээд давтаж, шинэ migration-аар хаагдсаныг шалгана. Энгийн хэрэглэгч, browser admin, anon-ийн DELETE/TRUNCATE хориглогдож, trusted Auth FK cascade ажилласаар байгааг баталсан. Энэ нь live FK schema эсвэл бодит binary cleanup-ийн баталгаа биш.

## Enable-ээс Өмнө

1. Disposable staging account дээр шинэ/legacy бүх медиа байрлал, Storage owner, Auth, FK cascade/SET NULL ба JSON доторх хувийн мэдээллийг шалгана. Auth/Storage нөөцийн одоогийн хязгаарыг эзэмшигч мэдсэн байх ёстой.
2. Partial remove, хожуу bucket failure, Auth failure, timeout дараах retry, хоёр зэрэг хүсэлт, өөр төхөөрөмжийн зэрэг upload-ийг жинхэнэ SDK/runtime дээр туршина. Зэрэг хүсэлт/шинэ upload-ийн хамгаалалт шаардлагатай эсэхийг шийднэ; атомик cross-service transaction гэж зарлахгүй.
3. Хуучин хүчинтэй JWT-тай device-ийн access, media signed URL/cache-ийн хугацаа болон бусдад хуулсан файлын хязгаарыг шалгана. Auth deletion нь JWT-г хугацаанаас нь өмнө хүчингүй болгодог гэж үзэхгүй. `202610220001_storage_account_guards.sql`-ийг эхлээд staging-д шалгана: дөрвөн bucket-ийн write-д active profile + caller UUID prefix шаардаж, хоосон/dot path segment болон backslash-ийг хориглоно, broad permissive legacy policy-г restrictive guard-аар хязгаарлана. Isolated fixture болон social migration-тай давтан суулгалт PASS; production-д суулгаагүй. Өөр RPC/RLS замуудыг мөн бодитоор аудитлана; энэ guard нь зэрэг upload-ийг lock хийхгүй.
   Мөн `202611030001_account_deletion_boundaries.sql` нь profiles мөрийг шууд DELETE/TRUNCATE хийх хуучин bypass-ийг хааж, user-controlled media URL-аар `storage.objects` устгадаг trigger-ийг саармагжуулна. [Supabase-ийн заавар](https://supabase.com/docs/guides/storage/schema/design)-аар Storage metadata устгах нь binary файлыг устгахгүй; API ашиглах ёстой. Тусдаа пост устгахад physical файл цэвэрлэх worker одоогоор байхгүй; account handler caller prefix-ийг бие даан жагсаана. Энэ migration мөн production-д суулгаагүй.
4. Apple grant revoke болон completion/recovery-г гүйцээж байж Apple-linked account gate-ийг өөрчилнө. Signing key/client secret repo, Dart define, чатад оруулахгүй.
5. Устгалын бодит retention/fulfillment журмыг privacy/terms-тэй тулгаж эзэмшигч батална. Web resource + Settings + профайлаа дуусгаагүй account-ийн entry, confirm/cancel, failure болон локал logout-ийг шалгана.
6. Production deploy болон environment enable тус бүрт тодорхой зөвшөөрөл авна. Secret enable flag-ийг өөрчлөх эсвэл endpoint deploy хийхийг энэ README өөрөө зөвшөөрөхгүй.

Аппын “устгасан” төлөв зөвхөн зөв owner-той strict success response-ийн дараа гарна. Өөр account руу шилжсэн/буцсан эсвэл дэлгэц хаагдсан үед хуучин хариу шинэ account-ыг logout хийхгүй. Service 404/unavailable байхад хүсэлт бүртгэгдсэн эсвэл устсан гэж үзэхгүй.
Local session цэвэрлэсний дараа remote logout удах үед UI таван секундээс илүү хүлээхгүй; late response нь шинэ account-ийн session-ийг цэвэрлэхгүйг тестлэсэн.
