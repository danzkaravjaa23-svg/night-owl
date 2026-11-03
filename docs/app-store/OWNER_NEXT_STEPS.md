# Apple эрхээс өмнөх ба дараах үлдсэн алхам

Night Owl UB · 2026-11-03

Бэлтгэлийн код `codex/app-store-preparation` салбарт байна. Нийтийн ажиллаж буй аппын салбар `night-owl-features` хэвээр. Шинэ backend/client-ийг хамтад нь шалгаж гаргана. Утасны web cache засвар `7cc568e` live болсон; одоогийн public release `e0e1d45` нь зөвхөн нууцлалын тайлбар зассан, аппын runtime byte ижил; энэ нь бэлтгэлийн backend/client rollout биш. Client `23a7258`-ийн 886 Flutter тест, analyzer, release web build, unsigned iPhone/simulator build болон iPhone/iPad startup PASS. Backend `f3f3a98`-ийн бодит local Auth/Storage/Edge 10 бүлэг PASS. Одоогийн нотолгоо [release тайлангийн эхэнд](../RELEASE_READINESS.md).

**Apple төлбөрөөс үл хамаарах үлдсэн ажил:** сэргээх database + Storage backup батлах, тусдаа hosted copy дээр турших, 008/009 + шинэ client-ийг хамтад нь гаргах, retention/операторын ажиллагааг батлах. Supabase Free-д automatic database backup байхгүй; metadata export нь backup биш. Төлбөртэй upgrade хийгээгүй. `delete-account` эх deploy хийгдсэн ч `ACCOUNT_DELETION_ENABLED=false`, JWT gateway ON; бодит устгал хийгдээгүй. [Яг дараалал ба батлах хүрээ](../../tools/deployment/STORE_BACKEND_ROLLOUT.md).

**2026-11-03 нөөцлөлтийн ахиц:** эзэмшигчийн оруулсан DB нууц үгээр шифрлэгдсэн, зөвхөн унших холболт амжилттай болсон. 87 хүснэгт/partition-ийн хувийн архив авч, бүрэн хамралт болон долоон файлын checksum шалгалтыг баталсан. [Нууц өгөгдөлгүй receipt](evidence/database-export.json). 97 зураг/видеоны шинэ нөөц болон тусгаарласан орчинд сэргээх туршилт үлдсэн тул backup gate хаагдаагүй. Нууц үг, өгөгдөл GitHub-д ороогүй.

1. **Apple эрх.** Developer membership Active болсны дараа Team ID болон App Store Connect хандалтыг батална. Нууц үг, `.p8`/`.p12`, recovery code-ийг чат эсвэл GitHub-д оруулахгүй.
2. **Apple тохиргоо.** `com.nightowl.ub.nightOwlUb` App ID-ийн эзэмшил, Sign in with Apple capability, web Service ID/callback болон backend-ийн Apple keys тохируулна. [Дэлгэрэнгүй заавар](../APPLE_SIGN_IN_SETUP.md).
3. **Backend.** Сэргээж болох DB болон Storage нөөцийг эхэлж батлаад, exact 008/009 atomic bundle-ийг disposable hosted copy дээр pre/postflight-тай шалгана. Edge-ийн эх production-д идэвхгүйгээр байрласан; staging дээр тусад нь бодит ажиллагааг шалгана. Бодит Auth/Storage шалгалт, өмнөх өгөгдөл/эрхийн нийцэл, админы сонгосон report context-ийг баталгаажуулж, дараа нь client-тэй зохицуулан идэвхжүүлнэ. Туршилтад зөвхөн тусдаа disposable аккаунт хэрэглэнэ.
4. **Гарын үсэг ба төхөөрөмж.** Xcode Team/provisioning сонгон signed archive гаргаж, өөрийн iPhone/iPad дээр [16 acceptance case](REVIEW_TEST_PLAN.md)-ийг шалгана. Үүнд Apple нэвтрэлт/устгал, зураг/видео, permission, мессеж, pending review, тасалдсан устгал сэргээх багтана.
5. **Store материал.** Бодит build-ээс screenshot авна. Listing текст [metadata/en-US](metadata/en-US)-д бэлэн. Seller/contact, хариуцсан moderator, review account, media rights, нас, privacy болон encryption хариуг эзэмшигч батална.
6. **TestFlight → App Review.** Эхлээд internal TestFlight-д суулгаж шалгана. Бүх gate хаагдсаны дараа App Review-д илгээнэ. Эхний хувилбарт manual release саналтай; submission буюу нийтлэлт одоогоор хийгдээгүй.

Нийтлэгдсэний дараа код, дизайн, боломжоо шинэ version/build гаргаж өөрчилж болно. Metadata талбар бүрийн засах нөхцөл ялгаатай. Одоогийн шалгалтын үр дүн ба эх сурвалж: [App Store бэлтгэл](../APP_STORE_SUBMISSION.md).
