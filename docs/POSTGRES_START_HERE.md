# PostgreSQL сервер болон API бэлдэх

2026-10-20-ны шинэ шийдвэр: Supabase болон одоогийн database-аа хэвээр үлдээнэ. Доорх сервер авах, шилжүүлэх заавар нь зөвхөн ирээдүйн лавлагаа; одоогийн ажлын төлөвлөгөө биш. Төлбөртэй сервер, өгөгдөл шилжүүлэлт, live endpoint солих ажил хийхгүй.

2026-10-20. Target сервер, домэйн, source database-ийн хувийн холболт байхгүй. Энэ заавар төлбөртэй үйлчилгээ үүсгэх, production өгөгдөл шилжүүлэх, live endpoint солих зөвшөөрөл биш.

## Юуг шилжүүлэх вэ?

Supabase-ийн өгөгдлийн сан өөрөө PostgreSQL. Night Owl-ийг тусдаа удирддаг PostgreSQL руу шилжүүлэхдээ хүснэгтээс гадна нэвтрэлт, зураг/видео, websocket, RPC болон эрхийн дүрмийг хадгална. Зөвхөн шинэ database URL авч Flutter-т оруулахад эдгээр ажиллахгүй.

Апп HTTP API-тай холбогдоно; PostgreSQL-ийн connection string зөвхөн серверт байна. Database password, service-role/signing key-г Flutter, GitHub эсвэл чатад оруулахгүй.

Эхний санал: Netlify дээрх frontend-ээ хадгалаад, өөрийн сервер дээр PostgreSQL, PostgREST болон одоогийн API протоколтой нийцэх Auth/Storage/Realtime ажиллуулах. Нээлттэй клиент SDK/компонентыг хадгалж болно; энэ нь managed Supabase Cloud дээр өгөгдөл хадгална гэсэн үг биш. Тэдгээрийг хүртэл бүрэн солих нь тусдаа backend/client дахин хэрэгжүүлэлт шаарддаг. Одоогийн `backend/compose.yaml` нь бүх үйлчилгээг ажиллуулдаг бэлэн stack биш.

## 1. Сервер авах

Нэг тодорхой сонголт болгон DigitalOcean Droplet ашиглаж болно. Сонголт эцэслээгүй; хэрэглэгч үнэ, нөхцөлийг зөвшөөрсний дараа л төлбөртэй resource үүсгэнэ.

1. [DigitalOcean](https://cloud.digitalocean.com/) дээр өөрийн аккаунтаар нэвтэрнэ.
2. **Create → Droplets** нээнэ. Эхний туршилтын нэрийг `nightowl-staging` гэж өгч болно.
3. **Ubuntu LTS**, хэрэглэгчдэдээ ойр боломжтой region, **Basic / Regular / Bundled** сонгоно. Боломжтой region, хэмжээг тухайн дэлгэц дээр шалгана.
4. Бүх backend үйлчилгээг нэг VM дээр туршихад 4 GB RAM / 2 vCPU / 80 GB SSD нь доод эхлэл; 8 GB / 4 vCPU / 160 GB SSD нь илүү зайтай эхлэл. Энэ нь ачааллын benchmark эсвэл өндөр найдвартай production архитектурын баталгаа биш.
5. SSH key-аар нэвтрэх сонголт ашиглана. Зөвхөн public `.pub` key-г provider-т нэмнэ; private key-г илгээхгүй. Одоо байгаа түлхүүрийг дарж бичихгүй.
6. Үүсгэхийн өмнө нийт үнийг нягтална. 2026-10-20-нд Regular bundled жагсаалтад дээрх хэмжээнүүд $24/сар, $48/сар байна. Backup, домэйн, нэмэлт диск, SMTP, траффик, татвар тусдаа байж болно. Эцсийн үнийг provider-ийн дэлгэцээр батална.
7. Зөвшөөрсөн тохиолдолд **Create Droplet** дарж, үүссэн public IPv4-ийг тэмдэглэнэ. IP гарсан нь API суулгагдаж ажиллаж байна гэсэн үг биш.

Албан эх сурвалж: [сервер үүсгэх](https://docs.digitalocean.com/products/droplets/how-to/create/), [үнийн жагсаалт](https://www.digitalocean.com/pricing/droplets), [нийцтэй бүтэн үйлчилгээний resource чиглэл](https://supabase.com/docs/guides/self-hosting/docker#system-requirements). Өөр stack-ийн бага нөөцтэй хувилбарыг тусад нь хэмжинэ.

## 2. Домэйн ба DNS

Өөрийн эзэмшдэг домэйн хэрэгтэй. Доорх нь зөвхөн жишээ, худалдаж авсан эсвэл ажиллаж буй домэйн биш:

```text
stage-api.example.com  ->  staging серверийн IPv4
api.example.com        ->  зөвхөн баталгаажсан production target
```

DNS provider дээр `stage-api` нэртэй **A record** үүсгээд staging IPv4 рүү чиглүүлнэ. Production `api` record-ийг cutover-оос өмнө live болгож солихгүй. Netlify-гийн `nightowl-ub.netlify.app` нэр дор өөрийн дурын API subdomain үүсгэх эрх байхгүй; frontend URL-ийг хэвээр үлдээнэ. [A record-ийн албан заавар](https://docs.digitalocean.com/products/networking/dns/how-to/manage-records/#a-records).

## 3. Серверийн хил

Cloud болон host firewall-ийг хамтад нь шалгана. SSH `22/tcp` зөвхөн админы зөвшөөрсөн IP-ээс; HTTPS `443/tcp`, сертификатын HTTP challenge ашиглавал `80/tcp` нийтэд нээлттэй байна. IPv6 асаасан бол ижил хил хэрэгжүүлнэ. Console/recovery нэвтрэлтийг баталж байж SSH дүрмийг хязгаарлана.

PostgreSQL `5432`, PostgREST, Auth, Storage, Realtime-ийн дотоод listener, tenant admin, dashboard болон readiness listener-ийг нийтэд шууд нээхгүй. Гадагш зөвхөн HTTPS ingress гаргана. [Firewall-ийн албан заавар](https://docs.digitalocean.com/products/networking/firewalls/how-to/create/).

## 4. API URL хэзээ бий болох вэ?

IP ба DNS нь зөвхөн суурь. Дараа нь service composition, хувийн secret files, database/bootstrap/extension, gateway adapter, TLS, health check, SMTP/OAuth-ийг хэрэгжүүлж туршина. Үүний дараа л `https://stage-api.example.com` нь бодит HTTP API болно.

Одоогийн Caddy scaffold бэлэн бус backend рүү хүсэлт дамжуулахгүй. Auth/Storage/Realtime нийцэл батлагдаагүй үед `UPSTREAM_PROTOCOL_VERIFIED=false`, `CUTOVER_APPROVED=false` хэвээр байна. Client build нь target-аас гаргасан **public anonymous JWT** хүлээдэг; provider-ийн personal access token эсвэл PostgreSQL password API key биш. Opaque publishable key-д тусдаа gateway/client нийцлийн ажил шаардлагатай.

Эцсийн client тохиргооны хэлбэр:

```text
BACKEND_MODE=postgres
BACKEND_URL=https://api.example.com
BACKEND_PUBLIC_KEY=<target-ийн public anonymous credential>
```

Эдгээрийг одоо production build-д бүү өг. Host/keys тодорхой болсны дараа staging-д эхэлж ашиглана. Bare PostgreSQL үйлчилгээ дангаар захиалах нь Auth/Storage/Realtime болон HTTP API-г автоматаар өгөхгүй.

## 5. Албан шилжүүлэлтийн дараалал

| Шат | Дараагийн шат руу орох нөхцөл |
| --- | --- |
| Host, домэйн, эрх | Эзэмшигч, төсөв, SSH key, backup хариуцагч, staging/production тусгаарлалт батлагдсан |
| Source backup | Бүрэн database/roles болон Storage файлууд Git-ээс гадуур хувийн архивт хадгалагдаж manifest/checksum шалгагдсан |
| Staging restore | Өөр, хоосон target дээр restore хийж UUID, мөр, FK, sequence, медиа byte/checksum-ийг тулгасан |
| Шинэ кодын SQL | Restored schema/owner/RLS-ийг шалгаад target-only RPC, featured-events, social-discovery, OSM migration-уудын нийцэл, дарааллыг staging дээр туршсан |
| Үйлчилгээний нийцэл | Login/refresh/recovery, upload/signed media, DM/group realtime, private/follow/block/ban/admin эрхийг хоёр бодит staging аккаунтаар баталсан |
| Client preview | Web, native, admin, extension бүгд шинэ origin/public credential-тай staging дээр шалгагдсан |
| Эцсийн export | Source-ийн app/API/background/Storage бичилтийг зөвшөөрсөн maintenance window-д зогсоож export/import/verify-г давтсан |
| Cutover | Backout төлөвлөгөө батлагдсан, release gate тэнцсэн үед л live backend-ийг сольж smoke/monitoring хийсэн |
| Rollback/хадгалалт | Target-ийн шинэ бичилтийг алдалгүй хадгалах/нийлүүлэх ажиллагааг туршсан; source-ийг шууд устгахгүй |

Database backup нь Storage-ийн зураг/видео файлуудыг агуулдаггүй тул хоёр тусдаа архив шаардлагатай. [Backup-ийн албан тайлбар](https://supabase.com/docs/guides/platform/backups), [platform restore-ийн нийцлийн заавар](https://supabase.com/docs/guides/self-hosting/restore-from-platform). Шинэ сервер авах нь одоогийн live Feed-ийн дутуу migration-ийг өөрөө засахгүй.

Target-only RPC patch нь функц аль хэдийн байвал зогсоно. Social migration өөрийн `dm_conversations()`-тай тул файлуудыг таамгаар давхардуулж ажиллуулахгүй. Source inventory, ownership болон хамаарлыг staging дээр шалгаж дарааллыг батална. Хуучин 60-table snapshot нь өнөөдрийн бүрэн backup биш.

## Одоо хэрэгтэй мэдээлэл

- Сонгосон үйлчилгээ, plan, public IP, SSH хэрэглэгчийн нэр; private key/нууц үг биш.
- Эзэмшдэг домэйн болон DNS provider; API token биш.
- Source database-ийн хувийн холболтыг энэ Mac дээр Git-ээс гадуурх хамгаалсан файлд тохируулах боломж. Нууц үгийг чатад бичихгүй.
- Төсөв, maintenance window, cutover зөвшөөрөх болон backup/rollback хариуцах хүн.

Мэдээлэл тодорхой болтол live endpoint болон source өгөгдөл өөрчлөгдөхгүй. Дэлгэрэнгүй: [export/restore](POSTGRES_MIGRATION.md), [үйлчилгээний дизайн](../backend/OWN_HOST_SERVICES.md), [release readiness](../backend/README.md).
