# Night Owl — approved брэндийн эх сурвалж

2026-10-05. Хэрэглэгч [энэ reference самбар](visuals/approved-reference.png)-ыг, тэр дундаа зүүн дээд дугуй purple owl-ыг сонгосон. Самбар нь хэрэглэгчийн хавсаргасан зургийн workspace хуулбар. Самбар дахь бодит мэт хүмүүс, зураг, газар, тоо нь бүтээгдэхүүний хэрэглэгчийн өгөгдөл биш.

## Одоогийн assets

| Asset | Эх сурвалж ба хэрэглээ |
|---|---|
| [`assets/icons/night_owl_mark.png`](../assets/icons/night_owl_mark.png) | Approved reference-ийн зүүн дээд owl-ыг built-in image generation-ээр тусгаарлан сэргээн бүтээсэн transparent mark. Энэ нь самбараас пикселээр яг тайрсан зураг биш. Runtime `NightOwlMark` болон `NightOwlBrand` ашиглана. |
| [`assets/icons/night_owl_icon.png`](../assets/icons/night_owl_icon.png) | Тэр сэргээн бүтээсэн owl-ыг opaque Midnight Navy квадрат дээр төвд байрлуулсан store/platform source icon. Corner rounding, гадна shadow, wordmark оруулаагүй. |
| [`assets/images/tonight_city.png`](../assets/images/tonight_city.png) | Өмнөх Higgsfield хотын brand illustration. Хэрэглэгч cover оруулаагүй үед профайлын fallback; бодит venue зураг эсвэл хэрэглэгчийн өөрийн cover гэж зарлахгүй. |

Одоо runtime дээрх owl болон platform icon нэг сонгосон owl дүрслэлийг ашиглана. Хэрэглэгчийн avatar-ыг энэ owl-оор сольдоггүй; тухайн хүний бодит зураг, эсвэл зураггүй үед initial-ийг харуулна.

## Өнгө ба дэлгэцийн чиглэл

| Өнгө | Утга | Хэрэглээ |
|---|---|---|
| Midnight Navy | `#0B0D17` | Гол dark гадаргуу, icon-ын opaque background |
| Muted Lavender | `#B6A4FF` | Owl-ийн нүд, хоёрдогч accent, ring/detail |
| Deep Violet | `#7654D6` | Үндсэн үйлдэл, сонгосон tab/navigation |

- Explore: газрын зураг гол талбайг эзэлнэ; хайлт/төрөл дээд хэсэгт, сонгосон газрын цайвар карт доор. Бодит OSM болон бодит газрын өгөгдөл ашиглана.
- Social: owl wordmark, story, бодит медиа пост, цэвэр action мөр. Reference-ийн sample хүмүүс, тоонуудыг хуулж зохиомол feed нэмэхгүй.
- Profile: skyline/cover, голд давхарласан avatar ба нарийн violet ring, username/нэр/био, жижиг edit pill, гурван тэнцүү stat, underline tabs, дөрвөлжин гурван баганатай grid. Нийтлэл/Хадгалсан/Бичлэг нь бодит функц; sample “Tagged” контент эсвэл зохиомол verification badge байхгүй.
- Footer: бүтэн өргөний хавтгай таван үйлдэл, төвийн violet нийтлэх товч; 72px үндсэн өндөр дээр системийн safe area нэмэгдэнэ. Үйлдлийн нэр харагдана.

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

Энэ брэндийн шинэчлэл нь үнэгүй release-ийн хамрах хүрээг өөрчлөхгүй: billing/subscription/premium/IAP идэвхгүй; газрын/эвентийн admission үнэ бол мэдээлэл, RSVP нь тасалбар/төлбөр биш. Apple provider-ийн бодит тохиргоо, native build/signing, шаардлагатай серверийн deployment, төхөөрөмжийн QA болон хэрэгжээгүй Live/calls/push/private боломжийн хязгаар [release тайланд](RELEASE_READINESS.md) хэвээр байна. Бодит газрын координатын эх сурвалж [дизайны тайланд](DESIGN_REVIEW.md#байршлын-шалгалт) бий.
