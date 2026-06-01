# Night Owl Admin — Chrome Extension суулгах заавар

## 1. Icon үүсгэх
`icons/generate-icons.html` файлыг browser-т нээгээд `icon16.png`, `icon48.png`, `icon128.png` гурвыг татаж `icons/` хавтсанд хадгала.

## 2. Chrome-д суулгах
1. Chrome хөтөч нээ
2. `chrome://extensions/` хаяг руу оч
3. Баруун дээрх **Developer mode** -г асаа
4. **Load unpacked** дарж `chrome-extension/` фолдерыг сонго
5. Extension жагсаалтад **Night Owl UB — Admin** гарч ирнэ

## 3. Нэвтрэх
Extension icon дарахад popup нээгдэнэ. Supabase-д бүртгэлтэй **admin** и-мэйл/нууц үгээрээ нэвтэр.

> ⚠️ Анхаарах: Supabase Dashboard → Authentication → Users → Нэвтрэх хэрэглэгч `profiles` хүснэгтэд байх ёстой.

## 4. Бүрэн dashboard
Popup доторх **"Бүрэн Dashboard нээх"** товч → `dashboard.html` шинэ tab-д нээгдэнэ.  
Эсвэл `chrome://extensions/` → Night Owl Admin → **Options** дарна.

## Файлын бүтэц
```
chrome-extension/
├── manifest.json          ← MV3 config
├── background/
│   └── service_worker.js  ← Session refresh + badge
├── popup/
│   ├── popup.html         ← 380px quick stats popup
│   └── popup.js
├── dashboard/
│   ├── dashboard.html     ← Бүрэн admin dashboard
│   └── dashboard.js
├── lib/
│   └── supabase-client.js ← Lightweight Supabase REST client
└── icons/
    ├── generate-icons.html
    ├── icon16.png
    ├── icon48.png
    └── icon128.png
```

## Dashboard функцуудын жагсаалт

| Таб | Функц |
|-----|-------|
| 📊 Тойм | KPI cards (users/posts/likes/venues/msgs/notifs) + сүүлийн постууд |
| 👤 Хэрэглэгчид | Хайлт, verify/unverify, ban, pagination |
| 📸 Постууд | Жагсаалт, устгах, сүүлийн 24 цагийн шүүлтүүр |
| 📍 Venues | CRUD: нэмэх, засах, устгах + координат |
| 🔔 Мэдэгдлүүд | Уншаагүй/бүгд шүүлтүүр |
| 📣 Broadcast | Бүх хэрэглэгчид нэгэн зэрэг мэдэгдэл |
