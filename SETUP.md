# 🦉 Night Owl UB — Flutter Setup Guide

## Хурдан эхлэх (Quick Start)

### 1. Flutter татаж дуусмагц шалгах
```bash
flutter doctor
```
Бүх ✅ болтол алдааг засна.

---

### 2. Project үүсгэх

Terminal-д:
```bash
cd ~/Desktop/Vip\ automation/ffvip_project/project/night-owl
flutter create . --org com.nightowl.ub --project-name night_owl_ub
flutter pub get
```

---

### 3. Supabase тохируулах

1. supabase.com → New Project → "nightowl-ub"
2. Settings → API → URL + anon key авна
3. lib/core/constants/app_constants.dart дотор тохируулна

#### SQL Tables (Supabase SQL Editor):
```sql
create table profiles (
  id uuid references auth.users primary key,
  username text unique, name text, bio text,
  avatar_url text, interests text[],
  is_business boolean default false,
  created_at timestamptz default now()
);

create table venues (
  id uuid primary key default gen_random_uuid(),
  name text not null, type text,
  address text, district text,
  lat double precision, lng double precision,
  photos text[], phone text,
  verified boolean default false,
  owner_id uuid references profiles(id),
  created_at timestamptz default now()
);

create table posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) not null,
  venue_id uuid references venues(id),
  caption text, media_url text,
  likes_count int default 0,
  is_paid boolean default false, price int,
  created_at timestamptz default now()
);

create table checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id),
  venue_id uuid references venues(id),
  created_at timestamptz default now(),
  expires_at timestamptz default now() + interval '4 hours'
);

create table follows (
  follower_id uuid references profiles(id),
  following_id uuid references profiles(id),
  primary key (follower_id, following_id)
);

create table messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references profiles(id),
  receiver_id uuid references profiles(id),
  content text, read_at timestamptz,
  created_at timestamptz default now()
);

create table events (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references venues(id),
  title text, description text,
  date timestamptz, ticket_price int,
  status text default 'draft'
);
```

#### Storage buckets: avatars · posts · stories · venues (all public)

---

### 4. Google Maps API key

android/app/src/main/AndroidManifest.xml дотор:
```xml
<meta-data android:name="com.google.android.geo.API_KEY" android:value="AIza..."/>
```

---

### 5. Ажиллуулах
```bash
flutter run
```

---

## 📁 Бүтэц (37 Dart файл)

```
lib/
├── main.dart
├── core/
│   ├── theme/           app_colors · app_text_styles · app_theme
│   ├── l10n/            app_strings (EN + MN)
│   ├── router/          app_router (GoRouter, 27 route)
│   ├── constants/       app_constants
│   ├── services/        supabase_service
│   └── widgets/         avatar · gradient_button · gradient_text · scaffold
└── features/
    ├── onboarding/      splash · lang_select · onboarding · permission
    ├── auth/            landing · login · register · setup · forgot_password
    ├── feed/            feed · post_detail · creator · qpay
    ├── map/             map · bar
    ├── post/            create_post
    ├── notifications/   notifications
    ├── dm/              dm_list · dm_thread
    ├── profile/         profile · settings · change_password · business · affiliate
    └── shell/           main_shell (bottom nav)
```

## 💰 Зардал (сард)
- Supabase Pro: $25
- Firebase FCM: $0
- Google Maps: $0 (хязгаарт)
- **Нийт: ~$25/сар** (500k хэрэглэгч хүртэл)
