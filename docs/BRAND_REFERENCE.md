# Night Owl — approved брэндийн эх сурвалж

2026-10-05. Хэрэглэгч [энэ reference самбар](visuals/approved-reference.png)-ыг, тэр дундаа зүүн дээд дугуй purple owl-ыг сонгосон. Самбар нь хэрэглэгчийн хавсаргасан зургийн workspace хуулбар. Самбар дахь бодит мэт хүмүүс, зураг, газар, тоо нь бүтээгдэхүүний хэрэглэгчийн өгөгдөл биш.

## Одоогийн assets

| Asset | Эх сурвалж ба хэрэглээ |
|---|---|
| [`assets/icons/night_owl_mark.png`](../assets/icons/night_owl_mark.png) | Approved reference-ийн зүүн дээд owl-ыг built-in image generation-ээр тусгаарлан сэргээн бүтээсэн transparent mark. Энэ нь самбараас пикселээр яг тайрсан зураг биш. Runtime `NightOwlMark` болон `NightOwlBrand` ашиглана. |
| [`assets/icons/night_owl_icon.png`](../assets/icons/night_owl_icon.png) | Тэр сэргээн бүтээсэн owl-ыг opaque Midnight Navy квадрат дээр төвд байрлуулсан store/platform source icon. Corner rounding, гадна shadow, wordmark оруулаагүй. |
| [`assets/images/tonight_city.png`](../assets/images/tonight_city.png) | Өмнөх Higgsfield хотын brand illustration. Хэрэглэгч cover оруулаагүй үед профайлын fallback; бодит venue зураг эсвэл хэрэглэгчийн өөрийн cover гэж зарлахгүй. |
| [`assets/images/owl_emotions.png`](../assets/images/owl_emotions.png) | 2026-10-05-нд Higgsfield-ээр approved owl-д тулгуурлан үүсгэсэн transparent 2×2 expression atlas: curious, wink, happy, patient. Loading ба бодит success/error төлөвт runtime quadrant сонгож ашиглана; master logo болон хүний avatar-ыг солихгүй. |

Одоо runtime дээрх owl болон platform icon нэг сонгосон owl дүрслэлийг ашиглана. Хэрэглэгчийн avatar-ыг энэ owl-оор сольдоггүй; тухайн хүний бодит зураг, эсвэл зураггүй үед initial-ийг харуулна.

## Өнгө ба дэлгэцийн чиглэл

| Өнгө | Утга | Хэрэглээ |
|---|---|---|
| Midnight Navy | `#0B0D17` | Гол dark гадаргуу, icon-ын opaque background |
| Muted Lavender | `#B6A4FF` | Owl-ийн нүд, хоёрдогч accent, ring/detail |
| Deep Violet | `#7654D6` | Үндсэн үйлдэл, сонгосон tab/navigation |

- Explore: газрын зураг гол талбайг эзэлнэ; хайлт/төрөл дээд хэсэгт, сонгосон газрын цайвар карт доор. Бодит OSM болон бодит газрын өгөгдөл ашиглана.
- Social: owl wordmark, story, бодит медиа пост, цэвэр action мөр. Reference-ийн sample хүмүүс, тоонуудыг хуулж зохиомол feed нэмэхгүй.
- Profile: skyline/cover, circular avatar ба бодит гурван stat зэрэгцсэн Instagram-аас санаа авсан бүтэц, username/нэр/био, засах/хуваалцах үйлдэл, underline tabs, дөрвөлжин гурван баганатай grid. Том үсэгтэй жижиг дэлгэц дээр avatar/stat болон товчийг давхарлан байрлуулна. Нийтлэл/Хадгалсан/Бичлэг нь бодит функц; sample “Tagged”, story highlight, хэрэглэгч эсвэл зохиомол verification badge нэмээгүй.
- Footer: бүтэн өргөний хавтгай таван үйлдэл, төвийн violet нийтлэх товч; 72px үндсэн өндөр дээр системийн safe area нэмэгдэнэ. Үйлдлийн нэр харагдана.

## Хэмжээст glyph, товч ба өнгөний горим

Хэрэглэгчийн дараагийн хүсэлтээр action дүрс, glass болон үндсэн товчид хэмжээст мэдрэмж нэмсэн. `SculptedIcon` нь Flutter-ийн vector icon давхарга, gradient shader, гэрэлтэй нүүр ба сүүдэртэй ирмэгээр дүрслэгдэнэ; товч нь gradient, сүүдэр болон дарах хөдөлгөөнтэй. Энэ нь runtime UI rendering бөгөөд 3D model эсвэл шинэ AI artwork биш. Дээрх approved flat owl mark болон icon master-ийг өөрчлөх generation хийгээгүй; хоёр prompt, asset-ийн эх сурвалж хэвээр.

Settings-ийн “Харагдах байдал” хэсэгт Өдөр / Шөнө / Систем сонголт байна. Feed болон Messages дээрх нар/сар товч хурдан солино. Шөнийн navy, өдрийн цайвар гадаргуу нь ижил violet/lavender брэндийг хадгалж, текст ба controls-ийг нийцүүлнэ; профайлын cover болон медиа үйлдлийн дүрс цагаан хэвээр. Map tile-ийн өнгө өдөр/шөнөд нийцэж өөрчлөгдөхөд camera-ийн төв, zoom болон газрын сонголт хадгалагдана. Cover, төв avatar, бодит saved tab, feed болон хавтгай таван үйлдэлтэй footer-ийн өмнөх сонголтыг хадгалсан.

Шөнийн горим анхны сонголт; Систем төхөөрөмжийн brightness-ийг дагана. Төхөөрөмжийн preference хадгалалт дарааллаар хийгдэж, startup-ийн хуучин өгөгдөл болон өмнөх хүсэлтийн алдаа шинэ сонголтыг дарахгүй. Хадгалалт бүтэлгүйтэхэд хамгийн сүүлийн сонголтыг өмнөх хадгалсан утгад буцааж, storage/cache сэргээхийг оролдон тайлбар харуулна; dispose болсон notifier-ийн хожуу үр дүн өнгийг өөрчлөхгүй.

## Дахин үүсгэх prompts

Доорх хоёр prompt нь тухайн generation хүсэлтийн утгыг үнэнчээр сэргээн бичсэн хувилбар. Tool call-ын literal payload-ын хуулбар гэж үзэхгүй. Эхний prompt-д approved reference, хоёр дахь prompt-д үүссэн isolated owl mark-ыг reference image болгон өгнө.

### 1. Transparent runtime owl mark

```text
Using the attached approved Night Owl brand reference, isolate and faithfully reconstruct only the flat, round purple owl logo shown in the upper-left corner of the board. Preserve its friendly symmetrical silhouette: a round midnight-navy head and body, two upward purple ear tufts, large muted-lavender circular eyes with dark navy pupils and small white highlights, a small pale-lavender beak, and a split navy/purple body with curved purple side panels. Keep the proportions and recognizable round owl character of this exact reference. Produce a clean, centered, high-resolution brand mark on a fully transparent background with clear edges and no surrounding content. No text, wordmark, phone screens, glow, shadow, border, heart-shaped angular owl logo, or realistic owl/avatar. Output only the isolated flat owl mark.
```

Generation тохиргоо: transparent background. Үр дүн: `assets/icons/night_owl_mark.png`.

### 2. Opaque square app icon

```text
Use the supplied transparent Night Owl mark as the exact visual reference. Preserve the same round purple owl, eye shapes, dark pupils, white highlights, small beak, purple ears, split body, colors, proportions, and friendly expression. Center this owl on a fully opaque square background of solid Midnight Navy #0B0D17. The owl should occupy approximately 68 percent of the canvas, with balanced clear space around it. Make a clean high-resolution app icon master. No text or wordmark, no rounded canvas corners, no border, no glow, no shadow, no additional objects, and no redesign into an angular or realistic owl.
```

Generation тохиргоо: opaque background. Үр дүн: `assets/icons/night_owl_icon.png`; platform хэмжээний экспортод энэ master-ийг ашиглана.

## Түүхэн Higgsfield эх сурвалжууд

| Higgsfield job | Өмнөх ажил |
|---|---|
| `76e2947d-f5e7-40ec-9cf4-2c6846cb225d` | Хотын illustration → `assets/images/tonight_city.png` |
| `5a438d94-276a-4bc5-b2cb-d2a2f8163698` | Өмнөх design board → `docs/visuals/higgsfield-reference.png` |
| `9b802457-987a-4781-bde4-370cc898d95d` | Өмнөх owl app icon туршилт; approved reference-ийн дугуй owl-оор солигдсон |

Одоогийн runtime mark болон icon-ыг built-in image generation-ээр сэргээн бүтээсэн. Өмнөх Higgsfield icon job-ыг одоогийн icon-ын generation job гэж тэмдэглэхгүй.

## Owl loading ба богино хөдөлгөөн

Higgsfield job `6136c2aa-129b-425c-8b6e-f8c75e961117` нь зөвшөөрсөн reference-ийг image input болгон, `gpt_image_2_5`, 1:1, high, 1k, transparent тохиргоотой нэг atlas үүсгэсэн. Урьдчилсан credit estimate 1.5 байсан; төлбөрийн бодит ledger-ийг тусад нь шалгаагүй. Зураг нь шинэ туслах illustration бөгөөд approved flat mark-ийн пикселээр яг хуулбар биш.

```text
Create a production-ready 2 by 2 emotion sprite atlas for the Night Owl mobile app. Use ONLY the round purple owl mark in the upper-left corner of the supplied reference board as the exact character identity: round symmetrical silhouette, two purple ear tufts, large lavender circular eye rings, midnight navy pupils with white highlights, tiny pale lavender beak, split midnight navy and violet body with curved purple side panels. Preserve those proportions and the #0B0D17 #B6A4FF #7654D6 palette. Beautiful clean soft dimensional vector-like finish, gentle highlights, crisp friendly shapes. Transparent background, no text, no phone screens, no logos other than these four owls, no external decorations, no borders, no shadows outside the owl. Four equal 512x512 virtual cells on a square canvas, all owls same size and centered in their cell with generous empty padding and no touching between cells. Each owl occupies at most 70 percent of its cell. Top-left: curious loading owl, both eyes open looking slightly up. Top-right: friendly one-eye wink, otherwise identical. Bottom-left: happy successful owl with crescent smiling eyes and small joyful ear tilt. Bottom-right: tender patient owl, slight concerned eyelids, comforting and cute, never crying. Maintain a consistent identical character and lighting in all four cells. This is an isolated sprite atlas for real runtime UI states, not a mood board or app redesign.
```

Товч дарах, route солих, result/empty entrance-ийн хөдөлгөөн Flutter-д богино, хугацаатай animation-ээр хэрэгжсэн; Higgsfield видео тоглуулдаггүй. Loading зөвхөн бодит хүсэлт явж байх үед зөөлөн хөвж/анивчина. Reduced motion, offstage, success/error төлөвт animation зогсоно. Атласын decode хэмжээг 512 хүртэл хязгаарласан; blur/shader animation нэмээгүй. Хүний бодит төхөөрөмж дээр FPS хэмжээгүй.

Энэ брэндийн шинэчлэл нь үнэгүй release-ийн хамрах хүрээг өөрчлөхгүй: billing/subscription/premium/IAP идэвхгүй; газрын/эвентийн admission үнэ бол мэдээлэл, RSVP нь тасалбар/төлбөр биш. Apple provider-ийн бодит тохиргоо, native build/signing, шаардлагатай серверийн deployment, төхөөрөмжийн QA болон хэрэгжээгүй Live/calls/push/private боломжийн хязгаар [release тайланд](RELEASE_READINESS.md) хэвээр байна. Энэ шинэчлэлийн GitHub push болон deployment баталгаажаагүй. Бодит газрын координатын эх сурвалж [дизайны тайланд](DESIGN_REVIEW.md#байршлын-шалгалт) бий.
