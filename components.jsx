/* components.jsx — Шөнийн шувуухай shared atoms & molecules */

// ─── Translation utility ───
// Screens receive a 'language' prop and can call t(key, language) to get translated text
// Example: <div>{t('auth.login', language)}</div>

// ─── Owl mascot (swappable image slot) ───
// User said: "later we'll swap the logo image". Render as an image-slot custom element
// so they can drop in a real owl image. Default shows a minimal placeholder glyph.
function OwlMark({ size = 84, glow = true, slotId = 'owl-default' }) {
  return (
    <div
      style={{
        width: size, height: size,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}
      className={glow ? 'ns-bloom' : ''}
    >
      <image-slot
        id={slotId}
        shape="circle"
        placeholder="LOGO"
        style={{
          width: size, height: size,
          display: 'block',
          background:
            'radial-gradient(circle at 50% 45%, rgba(255,77,141,0.35), rgba(123,47,247,0.18) 55%, transparent 80%)',
        }}
      ></image-slot>
      {/* fallback glyph layered behind — image-slot will cover when filled */}
      <svg
        viewBox="0 0 64 64"
        width={size * 0.46} height={size * 0.46}
        style={{ position: 'absolute', pointerEvents: 'none', mixBlendMode: 'screen', opacity: 0.85 }}
        aria-hidden
      >
        <defs>
          <linearGradient id={`owl-g-${slotId}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#FF4D8D" />
            <stop offset="0.5" stopColor="#FF7B5C" />
            <stop offset="1" stopColor="#FFB347" />
          </linearGradient>
        </defs>
        <circle cx="20" cy="26" r="9" fill={`url(#owl-g-${slotId})`} opacity="0.85" />
        <circle cx="44" cy="26" r="9" fill={`url(#owl-g-${slotId})`} opacity="0.85" />
        <circle cx="20" cy="26" r="3" fill="#0B0118" />
        <circle cx="44" cy="26" r="3" fill="#0B0118" />
        <path d="M28 38 L32 44 L36 38 Z" fill={`url(#owl-g-${slotId})`} />
      </svg>
    </div>
  );
}

// ─── Striped placeholder for venue/post imagery (in Mongolian) ───
function Placeholder({ label = 'зураг', tall = false, style, children }) {
  return (
    <div
      className="ns-placeholder"
      style={{
        width: '100%',
        aspectRatio: tall ? '3 / 4' : '4 / 3',
        ...style,
      }}
    >
      <span style={{ opacity: 0.6 }}>{label}</span>
      {children}
    </div>
  );
}

// ─── Logo slot (rectangle, used for bar/QPay logos) ───
function LogoSlot({ id, label = 'LOGO', width = 40, height = 40, radius = 10 }) {
  return (
    <image-slot
      id={id}
      shape="rounded"
      radius={radius}
      placeholder={label}
      style={{
        width, height,
        display: 'inline-block',
        background: 'rgba(255,255,255,0.06)',
        border: '1px solid var(--hairline)',
      }}
    ></image-slot>
  );
}

// ─── Avatar with optional gradient ring ───
function Avatar({ size = 40, ring = false, slotId, initial = '' }) {
  if (slotId) {
    const inner = (
      <image-slot
        id={slotId}
        shape="circle"
        placeholder=""
        style={{ width: '100%', height: '100%', display: 'block', background: 'transparent' }}
      ></image-slot>
    );
    if (ring) {
      return (
        <span
          className="ns-avatar has-ring"
          style={{ width: size, height: size }}
        >
          <span className="ns-avatar-inner" style={{ overflow: 'hidden' }}>
            {inner}
            {initial && (
              <span style={{
                position: 'absolute',
                fontSize: size * 0.36, color: 'var(--text-secondary)', fontWeight: 700,
                pointerEvents: 'none',
              }}>{initial}</span>
            )}
          </span>
        </span>
      );
    }
    return (
      <span className="ns-avatar" style={{ width: size, height: size, position: 'relative' }}>
        {inner}
        {initial && (
          <span style={{
            position: 'absolute', fontSize: size * 0.4, color: 'var(--text-secondary)',
            fontWeight: 700, pointerEvents: 'none',
          }}>{initial}</span>
        )}
      </span>
    );
  }

  // initials-only fallback (used in lists where we don't want N image slots)
  const palette = ['#FF4D8D', '#7B2FF7', '#FFB347', '#3DD68C', '#5C7BFF', '#FF7B5C'];
  const idx = (initial.charCodeAt(0) || 0) % palette.length;
  if (ring) {
    return (
      <span className="ns-avatar has-ring" style={{ width: size, height: size }}>
        <span className="ns-avatar-inner">
          <span style={{ fontSize: size * 0.38, color: palette[idx] }}>{initial}</span>
        </span>
      </span>
    );
  }
  return (
    <span className="ns-avatar" style={{
      width: size, height: size,
      background: `linear-gradient(135deg, ${palette[idx]}33, ${palette[(idx+2)%palette.length]}22)`,
    }}>
      <span style={{ fontSize: size * 0.4, color: palette[idx] }}>{initial}</span>
    </span>
  );
}

// ─── Icon: stroke-based, monochrome, scalable ───
function Icon({ name, size = 22, stroke = 'currentColor', strokeWidth = 1.6, filled = false }) {
  const s = size;
  const sw = strokeWidth;
  const common = {
    width: s, height: s, viewBox: '0 0 24 24', fill: 'none',
    stroke, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round',
  };
  switch (name) {
    case 'home':
      return <svg {...common}><path d="M3 11.5 12 4l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z" fill={filled ? stroke : 'none'}/></svg>;
    case 'feed':
      return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1.5" fill={filled?stroke:'none'}/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5" fill={filled?stroke:'none'}/></svg>;
    case 'map':
      return <svg {...common}><path d="M9 3 3 5.5v15.5l6-2.5 6 2.5 6-2.5V3l-6 2.5z"/><path d="M9 3v15.5M15 5.5V21"/></svg>;
    case 'plus':
      return <svg {...common}><path d="M12 5v14M5 12h14"/></svg>;
    case 'bell':
      return <svg {...common}><path d="M6 8a6 6 0 1 1 12 0c0 5 2 6 2 7H4c0-1 2-2 2-7z" fill={filled?stroke:'none'}/><path d="M10 21a2 2 0 0 0 4 0"/></svg>;
    case 'user':
      return <svg {...common}><circle cx="12" cy="8" r="4" fill={filled?stroke:'none'}/><path d="M4 21c1-4 4.5-6 8-6s7 2 8 6"/></svg>;
    case 'heart':
      return <svg {...common}><path d="M20.8 6.6a5 5 0 0 0-8.8-2 5 5 0 0 0-8.8 2c-1 4 3 8 8.8 13 5.8-5 9.8-9 8.8-13z" fill={filled?stroke:'none'}/></svg>;
    case 'comment':
      return <svg {...common}><path d="M21 12a8 8 0 1 1-3.4-6.5L21 4l-1.2 3.6A8 8 0 0 1 21 12z"/></svg>;
    case 'send':
      return <svg {...common}><path d="M4 12 21 4l-7 17-3-7z"/></svg>;
    case 'share':
      return <svg {...common}><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="m8 11 8-4M8 13l8 4"/></svg>;
    case 'bookmark':
      return <svg {...common}><path d="M6 3h12v18l-6-4-6 4z" fill={filled?stroke:'none'}/></svg>;
    case 'pin':
      return <svg {...common}><path d="M12 22s7-6.5 7-12a7 7 0 1 0-14 0c0 5.5 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/></svg>;
    case 'search':
      return <svg {...common}><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>;
    case 'star':
      return <svg {...common}><path d="m12 3 2.7 6 6.3.6-4.8 4.2 1.5 6.2L12 16.8 6.3 20l1.5-6.2L3 9.6l6.3-.6z" fill={filled?stroke:'none'}/></svg>;
    case 'lock':
      return <svg {...common}><rect x="4.5" y="11" width="15" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>;
    case 'chevron-right':
      return <svg {...common}><path d="m9 6 6 6-6 6"/></svg>;
    case 'chevron-down':
      return <svg {...common}><path d="m6 9 6 6 6-6"/></svg>;
    case 'arrow-right':
      return <svg {...common}><path d="M5 12h14M13 5l7 7-7 7"/></svg>;
    case 'arrow-left':
      return <svg {...common}><path d="M19 12H5M11 5l-7 7 7 7"/></svg>;
    case 'close':
      return <svg {...common}><path d="M6 6 18 18M18 6 6 18"/></svg>;
    case 'settings':
      return <svg {...common}><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h0a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v0a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>;
    case 'camera':
      return <svg {...common}><path d="M3 7h3l2-3h8l2 3h3v13H3z"/><circle cx="12" cy="13" r="4"/></svg>;
    case 'image':
      return <svg {...common}><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="m3 18 5-5 5 5 3-3 5 5"/></svg>;
    case 'film':
      return <svg {...common}><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18M17 3v18M3 8h4M17 8h4M3 16h4M17 16h4M3 12h18"/></svg>;
    case 'ticket':
      return <svg {...common}><path d="M3 8a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z"/></svg>;
    case 'play':
      return <svg {...common}><path d="M7 4v16l13-8z" fill={filled?stroke:'none'}/></svg>;
    case 'phone':
      return <svg {...common}><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.6A2 2 0 0 1 4 2h3a2 2 0 0 1 2 1.7c.1 1 .3 2 .6 3a2 2 0 0 1-.5 2L7.5 10a16 16 0 0 0 6 6l1.3-1.4a2 2 0 0 1 2-.5c1 .3 2 .5 3 .6a2 2 0 0 1 1.7 2z"/></svg>;
    case 'eye':
      return <svg {...common}><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>;
    case 'check':
      return <svg {...common}><path d="m4 12 5 5 11-11"/></svg>;
    case 'alert':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/></svg>;
    case 'refresh':
      return <svg {...common}><path d="M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5"/></svg>;
    case 'globe':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>;
    case 'logout':
      return <svg {...common}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/></svg>;
    case 'shield':
      return <svg {...common}><path d="M12 2 4 5v7c0 5 4 9 8 10 4-1 8-5 8-10V5z"/></svg>;
    case 'wallet':
      return <svg {...common}><path d="M3 7h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM3 7V5a2 2 0 0 1 2-2h11"/><circle cx="17" cy="13" r="1.4"/></svg>;
    case 'help':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 5 .5c0 1.5-2.5 2-2.5 4M12 17.5h.01"/></svg>;
    case 'qr':
      return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14h1v1h-1zM14 20h1v1h-1zM20 20h1v1h-1zM17 17h1v1h-1z"/></svg>;
    case 'edit':
      return <svg {...common}><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>;
    case 'more':
      return <svg {...common}><circle cx="5" cy="12" r="1" fill={stroke}/><circle cx="12" cy="12" r="1" fill={stroke}/><circle cx="19" cy="12" r="1" fill={stroke}/></svg>;
    case 'compass':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="m9 15 3-6 3 6-3-2z"/></svg>;
    case 'music':
      return <svg {...common}><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>;
    case 'sparkles':
      return <svg {...common}><path d="m12 3 1.6 5 5 1.6-5 1.6L12 17l-1.6-5-5-1.6 5-1.6zM5 4l.7 2L8 7l-2.3.7L5 10l-.7-2.3L2 7l2.3-1zM19 14l.7 2 2.3.7-2.3.7L19 20l-.7-2.3L16 17l2.3-1z" fill={filled?stroke:'none'}/></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="9"/></svg>;
  }
}

// ─── Star rating ───
function Stars({ value = 4.5, size = 14, showNumber = false }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
      <span style={{ display: 'inline-flex', gap: 1 }}>
        {[0, 1, 2, 3, 4].map(i => {
          const fill = i + 0.5 <= value;
          return (
            <span key={i} style={{
              color: fill ? '#FFB347' : 'rgba(255,255,255,0.2)',
              filter: fill ? 'drop-shadow(0 0 4px rgba(255,179,71,0.6))' : 'none',
            }}>
              <Icon name="star" size={size} stroke="currentColor" filled={fill} strokeWidth={1.2}/>
            </span>
          );
        })}
      </span>
      {showNumber && (
        <span style={{ fontSize: size - 1, fontWeight: 600, color: 'var(--text-secondary)' }}>
          {value.toFixed(1)}
        </span>
      )}
    </span>
  );
}

// ─── Status badge: Open / Closed ───
function StatusBadge({ open = true }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      padding: '4px 10px',
      borderRadius: 9999,
      background: open ? 'rgba(61,214,140,0.12)' : 'rgba(255,84,112,0.12)',
      color: open ? 'var(--success)' : 'var(--error)',
      fontSize: 11, fontWeight: 600, letterSpacing: '0.04em',
    }}>
      <span style={{
        width: 6, height: 6, borderRadius: 3,
        background: 'currentColor',
        boxShadow: open ? '0 0 8px currentColor' : 'none',
      }}/>
      {open ? tr('status.open') : tr('status.closed')}
    </span>
  );
}

// ─── Bottom tab bar — renders nothing if hidden ───
function BottomNav({ tab, onTab, onCenterPress, language }) {
  const items = [
    { key: 'feed',  icon: 'feed',  label: tr('tab.feed', language) },
    { key: 'map',   icon: 'map',   label: tr('tab.map', language) },
    { key: 'post',  icon: 'plus',  label: '',       center: true },
    { key: 'notif', icon: 'bell',  label: tr('tab.notif', language) },
    { key: 'me',    icon: 'user',  label: tr('tab.me', language) },
  ];
  return (
    <div style={{
      position: 'relative', flexShrink: 0,
      paddingBottom: 28,
      paddingTop: 8,
      background: 'linear-gradient(180deg, rgba(11,1,24,0) 0%, rgba(11,1,24,0.95) 30%)',
      backdropFilter: 'blur(20px)',
      borderTop: '1px solid var(--hairline)',
    }}>
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(5, 1fr)',
        alignItems: 'end',
        padding: '0 8px',
      }}>
        {items.map(item => {
          const active = tab === item.key;
          if (item.center) {
            return (
              <button
                key={item.key}
                onClick={() => onCenterPress?.()}
                style={{
                  border: 0, background: 'transparent', cursor: 'pointer',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                  paddingTop: 4,
                }}
              >
                <span style={{
                  width: 52, height: 52, borderRadius: '50%',
                  background: 'var(--accent-grad)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 8px 24px rgba(255,77,141,0.4), 0 0 0 6px rgba(11,1,24,0.5)',
                  transform: 'translateY(-12px)',
                  color: '#1B0210',
                }}>
                  <Icon name="plus" size={24} stroke="#1B0210" strokeWidth={2.2}/>
                </span>
              </button>
            );
          }
          return (
            <button
              key={item.key}
              onClick={() => onTab(item.key)}
              style={{
                border: 0, background: 'transparent', cursor: 'pointer',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                paddingTop: 6,
                color: active ? 'var(--text-primary)' : 'var(--text-tertiary)',
              }}
            >
              <span style={{
                position: 'relative',
                filter: active ? 'drop-shadow(0 0 6px rgba(255,77,141,0.55))' : 'none',
              }}>
                <Icon name={item.icon} size={22} filled={active}
                      stroke={active ? '#FF7B5C' : 'currentColor'}/>
              </span>
              <span style={{ fontSize: 9.5, letterSpacing: '0.05em', fontWeight: 600 }}>
                {item.label}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Phone status bar (white, dark mode) — minimal, inline ───
function PhoneStatus() {
  return (
    <div style={{
      position: 'relative', zIndex: 10,
      height: 54,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '16px 28px 0',
      color: '#fff', fontFamily: '-apple-system, system-ui',
    }}>
      <span style={{ fontWeight: 600, fontSize: 15 }}>9:41</span>
      <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
        <svg width="17" height="11" viewBox="0 0 17 11"><rect x="0" y="6" width="3" height="5" rx="0.6" fill="#fff"/><rect x="4.5" y="4" width="3" height="7" rx="0.6" fill="#fff"/><rect x="9" y="2" width="3" height="9" rx="0.6" fill="#fff"/><rect x="13.5" y="0" width="3" height="11" rx="0.6" fill="#fff"/></svg>
        <svg width="24" height="11" viewBox="0 0 24 11"><rect x="0.5" y="0.5" width="20" height="10" rx="3" stroke="#fff" strokeOpacity=".4" fill="none"/><rect x="2" y="2" width="17" height="7" rx="2" fill="#fff"/><path d="M22 3.5v4c.7-.3 1-1 1-2s-.3-1.7-1-2z" fill="#fff" fillOpacity=".5"/></svg>
      </span>
    </div>
  );
}

// ─── Section / page header text ───
function PageTitle({ children, small = false, style }) {
  return (
    <h1 style={{
      margin: 0,
      fontFamily: 'var(--ff-display)',
      fontWeight: 800,
      fontSize: small ? 26 : 34,
      lineHeight: 1.05,
      letterSpacing: '-0.02em',
      color: 'var(--text-primary)',
      ...style,
    }}>{children}</h1>
  );
}

// ─── Top-of-screen meta strip ("01 / 19 · SPLASH") ───
function ScreenMeta({ index, total, label }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      fontFamily: 'var(--ff-mono)', fontSize: 10, letterSpacing: '0.18em',
      color: 'var(--text-tertiary)', textTransform: 'uppercase',
    }}>
      <span>{String(index).padStart(2, '0')}</span>
      <span style={{ opacity: 0.5 }}>/</span>
      <span style={{ opacity: 0.5 }}>{String(total).padStart(2, '0')}</span>
      <span style={{ opacity: 0.4, margin: '0 4px' }}>·</span>
      <span>{label}</span>
    </div>
  );
}

// ─── Empty / Loading / Error state primitives ───
function EmptyState({ title, body, action, icon = 'sparkles' }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '32px 28px', textAlign: 'center', gap: 16,
    }}>
      <div style={{
        width: 96, height: 96, borderRadius: '50%',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'radial-gradient(circle, rgba(255,77,141,0.16), transparent 70%)',
        color: 'var(--accent-start)',
      }}>
        <Icon name={icon} size={36} strokeWidth={1.4}/>
      </div>
      <h3 style={{
        margin: 0, fontFamily: 'var(--ff-display)', fontWeight: 500,
        fontSize: 22, letterSpacing: '-0.01em',
      }}>{title}</h3>
      {body && (
        <p style={{
          margin: 0, fontSize: 14, lineHeight: 1.5,
          color: 'var(--text-secondary)', maxWidth: 280,
        }}>{body}</p>
      )}
      {action && <div style={{ marginTop: 8 }}>{action}</div>}
    </div>
  );
}

function LoadingState({ label }) {
  if (!label) label = tr('state.loading');
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 16,
    }}>
      <div className="ns-spin"/>
      <span className="ns-mono">{label}</span>
    </div>
  );
}

function ErrorState({ title, body, onRetry }) {
  if (!title) title = tr('state.error');
  if (!body)  body  = tr('state.errorBody');
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '32px 28px', textAlign: 'center', gap: 16,
    }}>
      <div style={{
        width: 80, height: 80, borderRadius: '50%',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'rgba(255,84,112,0.1)', color: 'var(--error)',
      }}>
        <Icon name="alert" size={32} strokeWidth={1.4}/>
      </div>
      <h3 style={{
        margin: 0, fontFamily: 'var(--ff-display)', fontWeight: 500, fontSize: 22,
      }}>{title}</h3>
      <p style={{
        margin: 0, fontSize: 14, color: 'var(--text-secondary)', maxWidth: 280,
      }}>{body}</p>
      {onRetry && (
        <button className="ns-btn-secondary" onClick={onRetry}>
          <Icon name="refresh" size={16}/> {tr('state.retry')}
        </button>
      )}
    </div>
  );
}

// ─── Skeleton helpers ───
function Skel({ w = '100%', h = 14, r = 8, style }) {
  return <span className="ns-skel" style={{ display: 'block', width: w, height: h, borderRadius: r, ...style }}/>;
}

// ─── Animated heart-burst on tap ───
function HeartBurst({ visible }) {
  if (!visible) return null;
  return (
    <span style={{
      position: 'absolute', inset: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      pointerEvents: 'none',
    }}>
      <span style={{
        color: '#FF4D8D',
        filter: 'drop-shadow(0 0 20px rgba(255,77,141,0.9))',
        animation: 'ns-heart 0.7s ease-out forwards',
      }}>
        <Icon name="heart" size={120} filled strokeWidth={0.5} stroke="#FF4D8D"/>
      </span>
    </span>
  );
}

// inject keyframes for heart burst
if (typeof document !== 'undefined' && !document.getElementById('ns-extra-keyframes')) {
  const s = document.createElement('style');
  s.id = 'ns-extra-keyframes';
  s.textContent = `
    @keyframes ns-heart {
      0%   { transform: scale(0.4); opacity: 0; }
      30%  { transform: scale(1.15); opacity: 1; }
      70%  { transform: scale(0.95); opacity: 1; }
      100% { transform: scale(1.4); opacity: 0; }
    }
    @keyframes ns-slide-in-up {
      from { transform: translateY(12px); opacity: 0; }
      to   { transform: translateY(0); opacity: 1; }
    }
    @keyframes ns-fade-in {
      from { opacity: 0; }
      to   { opacity: 1; }
    }
  `;
  document.head.appendChild(s);
}

// ─── Block / Report bottom sheet ───
function MoreActionsSheet({ show, onClose, username, language }) {
  const [view,     setView]     = React.useState('main');
  const [reason,   setReason]   = React.useState(null);
  const [done,     setDone]     = React.useState(null);

  // Reset when closed
  React.useEffect(() => {
    if (!show) { setTimeout(() => { setView('main'); setReason(null); setDone(null); }, 300); }
  }, [show]);

  if (!show) return null;

  const reportReasons = [
    { k: 'spam',       l: language === 'mn' ? 'Спам'               : 'Spam' },
    { k: 'nsfw',       l: language === 'mn' ? 'Зохисгүй агуулга'  : 'Inappropriate content' },
    { k: 'harass',     l: language === 'mn' ? 'Дарамт, зүй бус'   : 'Harassment or bullying' },
    { k: 'false',      l: language === 'mn' ? 'Худал мэдээлэл'    : 'False information' },
    { k: 'other',      l: language === 'mn' ? 'Бусад'              : 'Other' },
  ];

  const doBlock = () => {
    setDone('blocked');
    window.__showNotification?.(
      language === 'mn' ? `${username} хэрэглэгч хаагдлаа` : `${username} has been blocked`,
      'check', 2500
    );
    setTimeout(onClose, 1600);
  };

  const doReport = () => {
    if (!reason) return;
    setDone('reported');
    window.__showNotification?.(
      language === 'mn' ? 'Мэдээлэл хүлээн авлаа. Баярлалаа.' : 'Report submitted. Thank you.',
      'check', 2500
    );
    setTimeout(onClose, 1600);
  };

  return (
    <div
      style={{
        position: 'absolute', inset: 0, zIndex: 120,
        background: 'rgba(0,0,0,0.58)',
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
        animation: 'ns-fade-in .2s ease',
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: 'var(--bg-elevated)',
          borderRadius: '24px 24px 0 0',
          padding: '10px 20px 44px',
          border: '1px solid var(--hairline)', borderBottom: 0,
          boxShadow: '0 -20px 48px rgba(0,0,0,0.55)',
          animation: 'ns-slide-in-up .25s ease-out',
        }}
        onClick={e => e.stopPropagation()}
      >
        {/* drag handle */}
        <div style={{ width: 36, height: 4, borderRadius: 4,
          background: 'rgba(255,255,255,0.18)', margin: '0 auto 18px' }}/>

        {view === 'main' ? (
          done === 'blocked' ? (
            /* blocked success */
            <div style={{ textAlign: 'center', padding: '16px 0 8px' }}>
              <span style={{ width: 56, height: 56, borderRadius: '50%',
                background: 'rgba(255,84,112,0.12)', color: 'var(--error)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="shield" size={24} strokeWidth={1.8}/>
              </span>
              <div style={{ marginTop: 12, fontSize: 15, fontWeight: 700 }}>
                {language === 'mn' ? `${username} хаагдлаа` : `${username} blocked`}
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6, lineHeight: 1.5 }}>
                {language === 'mn'
                  ? 'Тэр хэрэглэгч таны профайл харж, мессеж илгээж чадахгүй.'
                  : 'They can no longer view your profile or send you messages.'}
              </div>
            </div>
          ) : (
            /* main options */
            <>
              <div className="ns-mono" style={{ marginBottom: 14, fontSize: 10 }}>{username}</div>

              {/* Block */}
              <button onClick={doBlock} style={{
                width: '100%', display: 'flex', alignItems: 'center', gap: 14,
                padding: '14px 2px',
                background: 'transparent', border: 0, borderBottom: '1px solid var(--hairline)',
                cursor: 'pointer', color: 'var(--error)', textAlign: 'left',
              }}>
                <span style={{ width: 40, height: 40, borderRadius: 12, flexShrink: 0,
                  background: 'rgba(255,84,112,0.10)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Icon name="shield" size={19} stroke="var(--error)" strokeWidth={1.7}/>
                </span>
                <div>
                  <div style={{ fontWeight: 700, fontSize: 15 }}>
                    {language === 'mn' ? 'Хэрэглэгч хаах (Block)' : 'Block User'}
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2, lineHeight: 1.4 }}>
                    {language === 'mn'
                      ? 'Профайл харж, мессеж илгээж болохгүй болно'
                      : "They won't be able to view your profile or message you"}
                  </div>
                </div>
              </button>

              {/* Report */}
              <button onClick={() => setView('report')} style={{
                width: '100%', display: 'flex', alignItems: 'center', gap: 14,
                padding: '14px 2px',
                background: 'transparent', border: 0, borderBottom: '1px solid var(--hairline)',
                cursor: 'pointer', color: 'var(--text-primary)', textAlign: 'left',
              }}>
                <span style={{ width: 40, height: 40, borderRadius: 12, flexShrink: 0,
                  background: 'rgba(255,179,71,0.10)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Icon name="alert" size={19} stroke="var(--warning)" strokeWidth={1.7}/>
                </span>
                <div>
                  <div style={{ fontWeight: 700, fontSize: 15 }}>
                    {language === 'mn' ? 'Мэдээлэх (Report)' : 'Report'}
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2, lineHeight: 1.4 }}>
                    {language === 'mn'
                      ? 'Зохисгүй агуулга, дарамт, спамыг мэдэгдэх'
                      : 'Report inappropriate content or behavior'}
                  </div>
                </div>
              </button>

              <button onClick={onClose} style={{
                width: '100%', marginTop: 14, height: 48, borderRadius: 14,
                background: 'rgba(255,255,255,0.05)', border: '1px solid var(--hairline)',
                color: 'var(--text-secondary)', cursor: 'pointer',
                fontFamily: 'var(--ff-body)', fontWeight: 600, fontSize: 14,
              }}>
                {language === 'mn' ? 'Болих' : 'Cancel'}
              </button>
            </>
          )
        ) : (
          /* report sub-view */
          done === 'reported' ? (
            <div style={{ textAlign: 'center', padding: '16px 0 8px' }}>
              <span style={{ width: 56, height: 56, borderRadius: '50%',
                background: 'rgba(61,214,140,0.12)', color: 'var(--success)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="check" size={26} strokeWidth={2.2}/>
              </span>
              <div style={{ marginTop: 12, fontSize: 15, fontWeight: 700 }}>
                {language === 'mn' ? 'Мэдээлэл хүлээн авлаа' : 'Report submitted'}
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6 }}>
                {language === 'mn' ? 'Баярлалаа. Удахгүй шалгана.' : "Thank you. We'll review this soon."}
              </div>
            </div>
          ) : (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16 }}>
                <button onClick={() => setView('main')} style={{
                  background: 'transparent', border: 0, cursor: 'pointer',
                  color: 'var(--text-secondary)', padding: 4, marginLeft: -4,
                }}>
                  <Icon name="arrow-left" size={20}/>
                </button>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 17, fontWeight: 600 }}>
                  {language === 'mn' ? 'Мэдээлэх шалтгаан' : 'Reason for Report'}
                </div>
              </div>

              {reportReasons.map((r, i) => (
                <button key={r.k} onClick={() => setReason(r.k)} style={{
                  width: '100%', display: 'flex', alignItems: 'center', gap: 12,
                  padding: '13px 2px',
                  background: 'transparent', border: 0, cursor: 'pointer',
                  borderBottom: i < reportReasons.length - 1 ? '1px solid var(--hairline)' : 'none',
                  color: 'var(--text-primary)', textAlign: 'left',
                }}>
                  <span style={{
                    width: 22, height: 22, borderRadius: '50%', flexShrink: 0,
                    border: `2px solid ${reason === r.k ? 'var(--accent-start)' : 'rgba(255,255,255,0.2)'}`,
                    background: reason === r.k ? 'var(--accent-start)' : 'transparent',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    transition: 'all .15s',
                  }}>
                    {reason === r.k && <Icon name="check" size={11} stroke="#fff" strokeWidth={3}/>}
                  </span>
                  <span style={{ fontSize: 14, fontWeight: reason === r.k ? 600 : 400 }}>{r.l}</span>
                </button>
              ))}

              <button onClick={doReport} disabled={!reason} style={{
                width: '100%', marginTop: 18, height: 48, borderRadius: 14,
                background: reason ? 'var(--accent-grad)' : 'rgba(255,255,255,0.06)',
                border: 0, cursor: reason ? 'pointer' : 'default',
                color: reason ? '#1B0210' : 'var(--text-tertiary)',
                fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 14,
                letterSpacing: '0.03em', transition: 'all .2s',
              }}>
                {language === 'mn' ? 'Илгээх' : 'Submit Report'}
              </button>
              <button onClick={onClose} style={{
                width: '100%', marginTop: 8, height: 38, borderRadius: 14,
                background: 'transparent', border: 0,
                color: 'var(--text-secondary)', cursor: 'pointer',
                fontFamily: 'var(--ff-body)', fontSize: 13,
              }}>
                {language === 'mn' ? 'Болих' : 'Cancel'}
              </button>
            </>
          )
        )}
      </div>
    </div>
  );
}

// ─── Notification Toast ───
function NotificationToast({ message, icon = 'check', onDismiss, duration = 3000 }) {
  React.useEffect(() => {
    if (duration) {
      const timer = setTimeout(onDismiss, duration);
      return () => clearTimeout(timer);
    }
  }, [duration, onDismiss]);

  return (
    <div style={{
      position: 'fixed', bottom: 24, left: 20, right: 20, zIndex: 9999,
      padding: '14px 16px', borderRadius: 12,
      background: 'rgba(11, 1, 24, 0.95)', backdropFilter: 'blur(12px)',
      border: '1px solid var(--hairline)',
      display: 'flex', alignItems: 'center', gap: 12,
      animation: 'ns-toast-slide-up 0.3s ease-out',
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 18,
        background: 'var(--accent-grad)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <Icon name={icon} size={18} stroke="#1B0210" strokeWidth={2.4}/>
      </div>
      <span style={{ fontSize: 13, lineHeight: 1.4, color: 'var(--text-primary)' }}>
        {message}
      </span>
      <style>{`
        @keyframes ns-toast-slide-up {
          from { transform: translateY(100px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
      `}</style>
    </div>
  );
}

// ─── Notification List (persistent) ───
function NotificationList({ items = [] }) {
  return (
    <div style={{
      position: 'fixed', bottom: 24, left: 20, right: 20, zIndex: 9998,
      maxHeight: '35vh', overflowY: 'auto',
      display: 'flex', flexDirection: 'column', gap: 8,
    }}>
      {items.map(item => (
        <div key={item.id} style={{
          padding: '12px 16px', borderRadius: 12,
          background: 'rgba(11, 1, 24, 0.92)', backdropFilter: 'blur(12px)',
          border: '1px solid var(--hairline)',
          display: 'flex', alignItems: 'center', gap: 10,
          animation: 'ns-toast-slide-up 0.3s ease-out',
        }}>
          <div style={{
            width: 32, height: 32, borderRadius: 16,
            background: 'var(--accent-grad)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <Icon name={item.icon} size={16} stroke="#1B0210" strokeWidth={2.4}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12, lineHeight: 1.3, color: 'var(--text-primary)' }}>
              {item.message}
            </div>
          </div>
          <div style={{ fontSize: 10, color: 'var(--text-tertiary)', flexShrink: 0 }}>
            {item.timestamp}
          </div>
        </div>
      ))}
      <style>{`
        @keyframes ns-toast-slide-up {
          from { transform: translateY(100px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
      `}</style>
    </div>
  );
}

// shared style: round 40px icon button (transparent)
const iconBtn = {
  width: 40, height: 40, borderRadius: 20,
  background: 'transparent', border: 0, cursor: 'pointer',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  color: 'var(--text-primary)',
};

Object.assign(window, {
  OwlMark, Placeholder, LogoSlot, Avatar, Icon, Stars, StatusBadge,
  BottomNav, PhoneStatus, PageTitle, ScreenMeta,
  EmptyState, LoadingState, ErrorState, Skel, HeartBurst, NotificationToast, NotificationList,
  MoreActionsSheet,
  iconBtn,
});
