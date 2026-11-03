# Эрх идэвхжсэний дараах дараалал

Night Owl UB · 2026-11-03

Бэлтгэлийн код `codex/app-store-preparation` салбарт байна. Нийтийн ажиллаж буй аппын салбар `night-owl-features` хэвээр. Шинэ backend/client-ийг хамтад нь шалгаж гаргана.

1. **Apple эрх.** Developer membership Active болсны дараа Team ID болон App Store Connect хандалтыг батална. Нууц үг, `.p8`/`.p12`, recovery code-ийг чат эсвэл GitHub-д оруулахгүй.
2. **Apple тохиргоо.** `com.nightowl.ub.nightOwlUb` App ID-ийн эзэмшил, Sign in with Apple capability, web Service ID/callback болон backend-ийн Apple keys тохируулна. [Дэлгэрэнгүй заавар](../APPLE_SIGN_IN_SETUP.md).
3. **Backend.** 008/009 migration, delete-account function-ийг staging дээр суулгаж pre/postflight хийнэ. Бодит Auth/Storage шалгалт, өмнөх өгөгдөл/эрхийн нийцэл, админы сонгосон report context-ийг баталгаажуулж, дараа нь client-тэй зохицуулан идэвхжүүлнэ. Туршилтад зөвхөн тусдаа disposable аккаунт хэрэглэнэ.
4. **Гарын үсэг ба төхөөрөмж.** Xcode Team/provisioning сонгон signed archive гаргаж, өөрийн iPhone/iPad дээр [16 acceptance case](REVIEW_TEST_PLAN.md)-ийг шалгана. Үүнд Apple нэвтрэлт/устгал, зураг/видео, permission, мессеж, pending review, тасалдсан устгал сэргээх багтана.
5. **Store материал.** Бодит build-ээс screenshot авна. Listing текст [metadata/en-US](metadata/en-US)-д бэлэн. Seller/contact, хариуцсан moderator, review account, media rights, нас, privacy болон encryption хариуг эзэмшигч батална.
6. **TestFlight → App Review.** Эхлээд internal TestFlight-д суулгаж шалгана. Бүх gate хаагдсаны дараа App Review-д илгээнэ. Эхний хувилбарт manual release саналтай; submission буюу нийтлэлт одоогоор хийгдээгүй.

Нийтлэгдсэний дараа код, дизайн, боломжоо шинэ version/build гаргаж өөрчилж болно. Metadata талбар бүрийн засах нөхцөл ялгаатай. Одоогийн шалгалтын үр дүн ба эх сурвалж: [App Store бэлтгэл](../APP_STORE_SUBMISSION.md).
