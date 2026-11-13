# Night Owl UB — Дизайн систем

2026-11-13 · Үе шат 1 (DS-01…DS-09) хэрэгжсэний дараах байдал. Шинэ дэлгэц хийх, хуучныг засахын өмнө үүнийг унш. Эх сурвалж нь код өөрөө: token нь `lib/core/theme/`-д, бүрэлдэхүүн нь `lib/core/widgets/`-д байгаа бөгөөд нарийн тайлбар нь тэдгээрийн doc comment-д бий. Энэ баримт зөвхөн дүрмүүдийг нэг дор цуглуулсан.

Ерөнхий дүрэм:

- Өнгө, зай, радиус, үсгийн хэмжээг literal-аар бичихгүй. `AppColors`, `AppSpacing`, `AppRadii`, `AppTextStyles` token хэрэглэнэ. `test/design_token_ratchet_test.dart` үүнийг хамгаална (§9).
- UI-ийн текст, tooltip, Semantics label монголоор байна.
- Өөрчлөлтөө Day ба Night горимд, 390 px ба 320 px + том фонттой шалга.

## 1. Өнгө — `AppColors` (`lib/core/theme/app_colors.dart`)

Адаптив getter (`accentText`, `danger`, `warning`, `rating`, `like`, `textPrimary`, `bgSurface`…) апп-ийн горимыг (`AppColors.isDarkMode`) дагадаг тул `const` дотор орохгүй. Getter хэрэглэсэн widget-ээс `const`-ийг ав. Горимоо өөрөө мэддэг газар (AppTheme, үргэлж харанхуй дэлгэц) `*Dark` / `*Light` const-уудыг хэрэглэнэ.

| Token | Night | Day | Хэзээ |
|---|---|---|---|
| `accentText` | #B6A4FF | #6550AD | Accent өнгөтэй ТЕКСТ ба ICON: холбоос, сонгосон төлөв, "Бүгдийг харах". |
| `accentStart` | #7654D6 | #7654D6 | Зөвхөн FILL: цагаан текст/icon-той дэвсгэр, gradient stop, чатын бөмбөлөг. Текст, icon-ий өнгө болгохгүй (харанхуй дэвсгэр дээр бүдэг). |
| `danger` | #FF4566 | #C81E3A | Алдаа, устгах үйлдлийн текст, icon, хүрээ. |
| `dangerFill` | #D7263D | #D7263D | Цагаан текстийн ард: badge, устгах товч, алдааны SnackBar. |
| `warning` | #FFB020 | #8A5A00 | Анхааруулгын текст, icon. |
| `rating` | #FFB020 | #B7791F | Үнэлгээний од. |
| `like` / `saved` | #B6A4FF | #6745C1 / #7654D6 | Апп-ийн гадаргуу дээрх дарсан зүрх, хадгалсан тэмдэг. |
| `likeOnMedia` | #B6A4FF | #B6A4FF | Үргэлж харанхуй медиа (reels, story viewer, live) дээрх дарсан зүрх. |
| `savedOnMedia` | #B6A4FF | #B6A4FF | Үргэлж харанхуй медиа (reels) дээрх хадгалсан тэмдэг. |
| `AppGradients.primary` | #8661DC → #7654D6 → #5D3AAB | ижил | Primary товчны fill. `AppColors.accentGradient` нь түүний alias. |

- `AppColors.error` бол хуучин нэр. Текст, icon, хүрээнд `danger`, цагаан текстийн ард `dangerFill` хэрэглэнэ.
- Material-ын `colorScheme.primary` одоо текстийн accent (`accentText`-тэй ижил). Брэндийн fill хэрэгтэй бол `colorScheme.primaryContainer` эсвэл `AppColors.accentStart`.
- Үргэлж харанхуй дэлгэц (reels, story, live, медиа дээрх overlay): `*Dark` const, `AppColors.toDark(color)`, `AppTextStyles.bodyMd.onDark`.
- Contrast-ийг `test/accent_contrast_test.dart` шалгана (текст ≥ 4.5:1, график ≥ 3:1).

## 2. Үсгийн хэв — `AppTextStyles` (`lib/core/theme/app_text_styles.dart`)

- Inter бол `pubspec.yaml`-ийн font family (`flutter > fonts`; 400, 500, 600, 700, 800, жин бүр өөрийн файлтай). `ThemeData(fontFamily: 'Inter')` ба `AppTextStyles.fontFamily` (const `'Inter'`) үүнийг хэрэглэнэ, тиймээс w700/w800 жинхэнэ Bold/ExtraBold файлаар зурагдана.
- Feature кодод `GoogleFonts.*` бичихгүй (ratchet hard zero). Үл хамаарах нь `lib/core/theme/` (`mono`, `monoSm` нь JetBrains Mono) ба story-ийн фонт сонгогч (`create_story_screen.dart`).
- `FontWeight.w900` хэрэглэхгүй: Inter-ийн хамгийн хүнд файл нь 800.
- Гарчиг, нэр, тоонд token хэрэглэж, өнгийг нь `copyWith(color: …)`-оор солино. Шинэ `fontSize:` literal бичихгүй.

| Token | Хэмжээ / жин | Хэрэглээ |
|---|---|---|
| `pageTitle` | 24 / w800 | Дэлгэцийн гарчиг (`AppHeader.title`) |
| `title` | 17 / w700 | Sheet, dialog, картын гарчиг; AppBar |
| `caption` | 12 / w500, textSecondary | Мета мөр, дэд гарчиг |
| `h1` · `h2` · `h3` | 24 / w700 · 19 / w700 · 15 / w600 | Хэсэг, мөрийн гарчиг |
| `bodyLg` · `bodyMd` · `bodySm` · `bodyXs` | 16 · 14 · 13 · 11 / w400 | Үндсэн текст |
| `labelLg` · `labelMd` · `labelSm` | 14 · 12 · 11 / w600 | Шошго, чип |
| `sectionLabel` | 11 / w700 | Хэсгийн жижиг нэр |
| `btn` · `btnSm` | 15 / w700 · 13 / w600 | Товчны бичиг |
| `displayLg` · `displayMd` · `displaySm` | 36 · 28 · 22 / w800 | Hero текст |
| `mono` · `monoSm` | 11 · 10, JetBrains Mono | Хувилбарын дугаар, код |

Widget test-үүд жинхэнэ Inter-ээр хэмждэг: `test/flutter_test_config.dart` бүх тестийн өмнө Inter family-г ачаална. Фонтын тест нь `test/bundled_fonts_test.dart`, файлуудын эх сурвалж нь `assets/fonts/README.md`.

## 3. Товч (`lib/core/widgets/gradient_button.dart`)

Бүх товч pill хэлбэртэй.

| Түвшин | Widget | Хэзээ |
|---|---|---|
| Primary | `GradientButton` | Нэг бүсийн (хуудасны доод хэсэг, sheet, хоосон төлөв, мөр) НЭГ гол үйлдэл. `busy: true` үед owl гарч, "түр хүлээнэ үү" гэж уншигдана; `onPressed: null` бол идэвхгүй. |
| Secondary | `OutlineButton` | Primary-ийн хажууд: "Болих" гэх мэт. |
| Tertiary | theme-тэй `TextButton` | "Бүгдийг харах", "Дахин оролдох" зэрэг бага ач холбогдолтой үйлдэл. |
| Устгах баталгаажуулалт | `FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.dangerFill, foregroundColor: Colors.white))` | Dialog-ийн "Устгах". |

- Хэмжээ (`size:`): `GradientButtonSize.lg` 52 px (анхдагч; хуудас, sheet-ийн CTA), `md` 44 px (touch төхөөрөмж дээр 48; хоосон төлөв, inline), `sm` 36 px pill + 44 px хүрэх талбар (жагсаалтын мөр, reels-ийн "Дагах"). `OutlineButton` ижил `size`-тай.
- `fullWidth: false` бол товч бичгийнхээ өргөнтэй. Нэг Row-д хоёр товч зэрэгцүүлэхдээ `Expanded`/`Flexible`-д ороо.
- Идэвхгүй (`onPressed: null`) үед: `GradientButton`-ийн icon шошготойгоо хамт бүдгэрнэ (Day-ийн идэвхгүй дэвсгэр дээр цагаан icon алга болохгүй); `OutlineButton`-ийн шошго ба icon tertiary өнгөтэй, хүрээ нь илүү бүдэг болно.
- Material `FilledButton`, `ElevatedButton`, `OutlinedButton` AppTheme-ээр pill болсон. Хэлбэр, радиус, брэндийн өнгийг давтсан `styleFrom` override бүү бич. `GradientButton`-д `borderRadius` параметр байхгүй.
- Gradient `Container` + `GestureDetector`/`InkWell`-ээр primary товч гараар бүү хий: busy/disabled төлөв, keyboard focus, semantics, 44 px талбар алдагдана.

## 4. Sheet (`lib/core/widgets/app_sheet.dart`)

- `showModalBottomSheet`-ийг шууд дуудахгүй (ratchet hard zero). `showAppSheet(context: context, builder: (sheetContext) => …)` хэрэглэнэ.
- Анхдагч нь: root navigator (sheet dock-ийг бүрхэж бүдгэрүүлнэ), `isScrollControlled`, `useSafeArea`, AppMotion-ы 280/200 ms хөдөлгөөн (систем хөдөлгөөн багасгавал хөдөлгөөнгүй). Дэвсгэр, дээд радиус, НЭГ drag handle-ийг theme өгнө. Тиймээс `useRootNavigator`, `isScrollControlled`, `useSafeArea`, `backgroundColor`, `shape`, `showDragHandle`-ийг дамжуулахгүй, контент дотор handle зурахгүй.
- Доод inset-ийг контент өөрөө авна: `SafeArea(top: false, …)`, text field-тэй бол `MediaQuery.viewInsetsOf(context).bottom`.
- Гарчгийн мөр: `AppSheetHeader(title: …, subtitle: …, trailing: …, showClose: true)`. Хаах товч нь sheet-ийн context-оор pop хийнэ.
- `dark: true` нь Day горимд ч харанхуй байх ёстой sheet-д л (харанхуй дэвсгэрийг `*Dark` const эсвэл хараар зурдаг байсан). Reels-ийн sheet-үүд апп-ийн theme-ийг зориуд дагана. Dark sheet доторх өнгийг `Theme.of(context)`, `*Dark` const эсвэл `.onDark`-аас ав, учир нь адаптив getter апп-ийн горимыг дагадаг.
- **Хаахдаа sheet-ийн ӨӨРИЙН context-ийг хэрэглэ:** `Navigator.of(sheetContext).pop(value)`. Sheet root navigator дээр байгаа тул page-ийн context-оор `Navigator.pop(context)` эсвэл go_router-ийн `context.pop()` дуудвал sheet биш, доорх ХУУДАС хаагдана. Builder-ийн параметр page-ийн `context`-ийг дарж нэрлэсэн бол `sheetContext` гэх мэтээр нэрийг нь сольж ялга.
- **Алдаа:** sheet нээлттэй үед SnackBar sheet-ийн ДООР зурагдаж харагдахгүй. Sheet нээлттэй үлдэх алдааг sheet дотор, үйлдлийн ойролцоо `AppColors.danger` өнгийн `Text`-ээр харуулж, дахин оролдоход арилга. Амжилттай бол эхлээд sheet-ээ хаагаад, дараа нь page-ийн context-оор SnackBar харуул.
- Sheet дотроос `Scaffold.of` shell-ийн Scaffold-ийг олохгүй. Riverpod, `ScaffoldMessenger`, GoRouter, MediaQuery хэвийн ажиллана.
- Тест: `test/app_sheet_test.dart`, `test/sheet_single_handle_test.dart`.

## 5. Толгой (`lib/core/widgets/app_header.dart`)

| Хувилбар | Хаана | Агуулга |
|---|---|---|
| `AppHeader.brand(actions: …)` | Tab-ын нүүр (Feed, Explore) | `NightOwlBrand` (28), atmosphere гэрэл, баруун талд үйлдлүүд |
| `AppHeader.title(title: …)` | Дэд хуудас | Буцах товч + `pageTitle` (`compact: true` бол `title`) + `subtitle` (`caption`) + үйлдлүүд; `bottom:`-д TabBar. `title: ''` бол зөвхөн буцах товч. |
| `AppHeader.media(…)` | Зураг, видео дээр | Тунгалаг дэвсгэр, `onMedia` товч, цагаан гарчиг; `scrim: true` бол дээрээс бараан gradient |

- Өндөр нь 64 px, gutter нь 20 px (`AppSpacing.page`). `primary: true` (анхдагч) үед толгой status bar-ын зайг өөрөө авна: `Scaffold.appBar`-д эсвэл body-ийн оройд тавь. Sheet, карт дотор `primary: false`.
- Буцах товч нь `GlassIconButton(AppIcons.back)`, tooltip "Буцах". Анхдагч үйлдэл нь `AppHeader.goBack(context, fallbackLocation: …)`: pop хийж чадвал `maybePop`, чадахгүй бол (deep link, refresh) `GoRouter.go(fallbackLocation ?? AppRoutes.feed)`. Хуучин `canPop ? pop : go(X)` загварыг `fallbackLocation: X` болгоно. `onBack`-ийг зөвхөн guard-д хэрэглэнэ (ж: хадгалж байх үед буцахыг хориглох).
- Tab ч, push хийсэн хуудас ч болдог дэлгэцэд `showBack: ModalRoute.canPopOf(context) ?? false` гэж бич. `Navigator.of(context).canPop()` бүү хэрэглэ: sheet, dialog нээлттэй үед true болдог.
- `actions`-д хооронд нь зай нэмэлгүй `GlassIconButton`-ууд өг; зайг толгой өөрөө тавина. Үйлдэл бүр монгол `tooltip`-тэй байна: энэ нь дэлгэц уншигчийн нэр болох ба тестүүд tooltip-оор дардаг. Theme toggle (`ThemeToggleButton`, `EclipseThemeToggle`) одоогийн байрандаа үлдэнэ.
- Badge: `GlassIconButton(badgeCount: n)` нь `dangerFill` дээр тоо харуулна (99-өөс дээш бол "99+"), `showBadgeDot: true` нь тоогүй цэг. Дэлгэц уншигч "<tooltip>, N шинэ" гэж уншина.
- `_TopIconBtn`, `_GlassCircleButton`, `_GlassIconButton`, `_GlassBackBtn` зэрэг private толгойн товч класс шинээр бүү үүсгэ (ratchet hard zero).

## 6. Icon (`lib/core/theme/app_icons.dart`)

- Нэг ойлголтод нэг glyph, Material Rounded гэр бүл. Идэвхгүй нь outline, идэвхтэй нь filled: `like`/`likeActive`, `save`/`saveActive`, `comment`/`commentActive`, `shortVideo`/`shortVideoActive`, `message`/`messageActive`, `notifications`/`notificationsActive`, `venue`/`venueActive`, `feed`/`feedActive`, `profile`/`profileActive`.
- Бусад: `back`, `forward`, `close`, `search`, `more`, `add`, `send` (мессеж илгээх товч), `imageBroken` (ачаалж чадаагүй зураг), `share`.
- `AppIcons.share` нь getter (iOS/macOS дээр `ios_share_rounded`, бусад газар `share_rounded`), тиймээс `const Icon(AppIcons.share)` бичиж болохгүй.
- Буцах glyph зөвхөн `AppIcons.back`. `Icons.arrow_back*`, `Icons.chevron_left*`, `Icons.keyboard_arrow_left*` хориотой (ratchet hard zero).
- Газрын төрөл: `Icon(AppIcons.venueType(venue.type))`. Шинэ төрлийн түлхүүр нэмбэл `venueType`-д glyph нэм. `test/app_icons_test.dart` нь `Venue.typeLabel`, газрын зургийн шүүлтүүр, газар засварлагчийн бүх түлхүүрийг шалгадаг.
- Emoji зөвхөн хэрэглэгчийн контентод: sticker, DM-ийн emoji сонгогч, story reaction, хурдан reaction, хэрэглэгч засаж болох анхдагч текст ("Live 🎤"), бусад апп руу хуваалцах текст. UI chrome-д emoji хэрэглэхгүй:
  - ачаалж чадаагүй зураг → `Icon(AppIcons.imageBroken)` (`textTertiary`);
  - хоосон сэтгэгдэл → `Icon(AppIcons.comment)`;
  - 🦉 → `NightOwlMark` (`lib/core/widgets/night_owl_brand.dart`);
  - 📍 → `Icon(AppIcons.venue)`;
  - 🔴 live → `dangerFill` өнгийн жижиг цэг + текст;
  - SnackBar-ын төгсгөлд emoji тавихгүй.

## 7. Settings мөрийн kit (`lib/core/widgets/settings_rows.dart`)

Settings, privacy, account, admin дэлгэцүүд нэг хэлбэрийн жагсаалт хэрэглэнэ:

```dart
const SizedBox(height: 28), // хэсэг хооронд
const SettingsSectionLabel('Таны бүртгэл'),
const SizedBox(height: 12), // шошгоноос карт хүртэл
SettingsCard(children: [
  SettingsRow(
      icon: AppIcons.profile,
      title: 'Профайл засах',
      subtitle: 'Нэр, зураг, танилцуулга',
      onTap: openEditProfile),
  const SettingsDivider(),
  SettingsRow(
      icon: AppIcons.notifications,
      title: 'Апп доторх мэдэгдэл',
      onTap: () => setNotifications(!on),
      trailing: SettingsSwitch(value: on, onChanged: setNotifications)),
]),
```

- `SettingsDivider`-ийг мөр хооронд өөрөө тавина.
- `SettingsCard` нь `Material` тул доторх мөрийн (custom `ListTile`/`InkWell` мөрийн ч) ripple карт дээр харагдана.
- Switch-тэй мөр ижил toggle-ийг `onTap` ба `onChanged`-д өгнө, тэгвэл текст дээр дарахад ч солигдоно. Дэлгэц уншигч ийм мөрийг switch-тэй нь НЭГ node болгон уншина (`MergeSemantics`, `SwitchListTile`-тэй адил): гарчиг, асаалттай/унтраалттай төлөв, нэг tap үйлдэл.
- `trailing` нь гарчгийн хажууд байгалийн өргөнөөрөө байрлаж, хэзээ ч мөр шилжихгүй. Тиймээс тэнд зөвхөн жижиг widget (`SettingsSwitch`, icon) тавина; текст товчийг мөрийн доор тусдаа мөрөнд тавь.
- `enabled: false` мөрийг бүдгэрүүлж, chevron ба `onTap`-ийг унтраана. Switch-ийг `onChanged: null`-ээр өөрөө унтраа.
- 380 px-ээс нарийн дэлгэц + том фонттой үед icon tile нуугдана.
- Тест: `test/settings_rows_test.dart`.

## 8. Зай, радиус, нийтлэг төлөв

- `AppSpacing`: `x1` 4, `x2` 8, `x3` 12, `x4` 16, `x5` 20, `x6` 24, `x8` 32, `page` 20, `pageH`.
- `AppRadii`: `sm` 8, `md` 14, `lg` 20, `xl` 28, `pill` 999; бэлэн `smR`, `mdR`, `lgR`, `xlR`, `pillR`.
- Ачаалах төлөв `OwlLoading`, хоосон төлөв `EmptyState`, карт нь Card theme эсвэл `PremiumSurface.card()`.

## 9. Token ratchet test (`test/design_token_ratchet_test.dart`)

`lib/**/*.dart`-ийн текстийг уншина; `//`-ээр эхэлсэн мөрийг алгасна.

- **Hard zero (бүх lib):** `showModalBottomSheet(` (`app_sheet.dart`-аас бусад), `GoogleFonts.` (`lib/core/theme/` ба `create_story_screen.dart`-аас бусад), `FontWeight.w900`, `Icons.arrow_back*` / `chevron_left*` / `keyboard_arrow_left*` (`app_icons.dart`-аас бусад), `class _…(TopIconBtn|GlassCircleButton|GlassIconButton|GlassBackBtn)`. Олдвол файл:мөр ба засах аргыг хэлнэ.
- **Ceiling (зөвхөн `lib/features`):** 2026-11-13-нд хэмжсэн тоо.

| Тоолуур | Ceiling |
|---|---|
| `Color(0x…)` literal | 134 |
| `BorderRadius.circular(<тоо>)` + `Radius.circular(<тоо>)` | 196 |
| `SizedBox(height: <тоо>)` / `SizedBox(width: <тоо>)` зай | 642 |
| `fontSize: <тоо>` | 101 |
| Ялгаатай радиусын утга | 18 |
| Ялгаатай SizedBox зайн утга | 28 |

- Тоо өсвөл тест унаж, аль тоолуур хэдээр өссөн, аль файлд хамгийн их байгааг хэлнэ (ялгаатай утгын тоолуурт шинэ утга хаана байгааг). Literal-ын оронд token хэрэглэ.
- Literal хассан бол ceiling-ийг шинэ тоо руу БУУЛГА; ratchet зөвхөн доошилно, хэзээ ч өсгөхгүй. Тест давахдаа одоогийн тоог хэвлэж, ceiling-ээс доош орсон тоолуурыг тусад нь заана.

## 10. Шалгах

- `flutter analyze --no-pub`
- Холбогдох тестүүд: `test/design_token_ratchet_test.dart`, `test/app_icons_test.dart`, `test/settings_rows_test.dart`, `test/app_header_test.dart`, `test/app_sheet_test.dart`, `test/gradient_button_test.dart`, `test/accent_contrast_test.dart`, `test/bundled_fonts_test.dart`.
- Visual capture: `tools/visual_review/<name>.dart.txt`-ийг `test/_<name>_test.dart` болгон хуулж, `flutter test --no-pub --concurrency=1 test/_<name>_test.dart`-ээр ажиллуулаад хуулбарыг устга. `profile_settings_capture` нь `--dart-define=CAPTURE_PROFILE_SETTINGS=true`, `admin_console_capture` нь `--dart-define=CAPTURE_ADMIN=true` шаардана. PNG нь `build/audit/2026-11-03/`-д гарна.
