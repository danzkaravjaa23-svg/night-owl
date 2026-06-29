# NightOwl UB — Standalone Web Admin Panel

A single-file, zero-build admin dashboard for the NightOwl backend. It talks
directly to the same Supabase project as the Flutter app and is fully gated by
the existing `public.is_admin()` RLS policies.

## Ажиллуулах (Run)

It's just static HTML — any of these work:

```bash
# Option 1 — open directly
open admin-web/index.html

# Option 2 — local static server (recommended; avoids file:// quirks)
cd admin-web && python3 -m http.server 8080
# → http://localhost:8080
```

Then log in with an **admin** account (a `profiles` row with `is_admin = true`).
Non-admins are signed out immediately with "Танд админ эрх алга."

## Pages

| Page | Юу хийдэг |
|------|-----------|
| **Хяналтын самбар** | Хэрэглэгч / пост / газар / эвент / pending report / banned / verified / comment тоо |
| **Мэдээллүүд** | Pending reports — target-ийн дэлгэрэнгүй харах, пост устгах, хэрэглэгч хориглох, шийдсэн тэмдэглэх |
| **Хэрэглэгчид** | Хайх, хориглох/сэргээх, баталгаажуулах/цуцлах |
| **Постууд** | Сүүлийн постууд (grid), устгах |
| **Газрууд** | Жагсаалт, нэмэх / засах / устгах |
| **Эвентүүд** | Жагсаалт, устгах |

## Security

- Uses the **anon key** (public by design) + admin email/password login.
- Every privileged write (ban, delete, venue CRUD, resolve report) is enforced
  server-side by `is_admin()` RLS — the panel cannot do anything the logged-in
  user isn't already authorized for.
- No service-role key is embedded. Safe to host on any static host.

## Deploy

Drop `index.html` on Netlify / Vercel / GitHub Pages / Supabase Storage / any
static host. No build step, no env vars.

## Хэрэв нэг хэсэг "Алдаа" гаргавал

Тухайн хүснэгтэд админд зориулсан RLS policy дутуу байж болзошгүй (ж: events
delete). Алдааны мессеж policy дутууг шууд хэлнэ — холбогдох `supabase_*.sql`
policy-г нэмнэ.
