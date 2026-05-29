/* app.jsx — main shell, router, phone bezel, side controls, Tweaks panel */

const SCREENS = [
  // group, id, label, tabKey (which bottom-tab is active), showNav
  { g: 'Onboarding',   id: 'splash',            label: 'Splash',              tab: null },
  { g: 'Onboarding',   id: 'onboarding-1',      label: 'Onboarding · 1/3',    tab: null },
  { g: 'Onboarding',   id: 'onboarding-2',      label: 'Onboarding · 2/3',    tab: null },
  { g: 'Onboarding',   id: 'onboarding-3',      label: 'Onboarding · 3/3',    tab: null },
  { g: 'Onboarding',   id: 'perm-location',     label: 'Perm · Location',     tab: null },
  { g: 'Onboarding',   id: 'perm-notification', label: 'Perm · Notification', tab: null },
  { g: 'Auth',         id: 'auth-landing',      label: 'Auth Landing',        tab: null },
  { g: 'Auth',         id: 'login',             label: 'Login',               tab: null },
  { g: 'Auth',         id: 'register',          label: 'Register',            tab: null },
  { g: 'Auth',         id: 'setup',             label: 'Profile Setup',       tab: null },
  { g: 'Main',         id: 'feed',              label: 'Feed',                tab: 'feed'  },
  { g: 'Main',         id: 'post-detail',       label: 'Post Detail',         tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'creator',           label: 'Creator + Paid',      tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'qpay',              label: 'QPay Payment',        tab: 'feed',  hideNav: true },
  { g: 'Main',         id: 'map',               label: 'Map',                 tab: 'map'   },
  { g: 'Main',         id: 'bar',               label: 'Bar Profile',         tab: 'map',   hideNav: true },
  { g: 'Main',         id: 'post',              label: 'Create Post',         tab: 'post',  hideNav: true },
  { g: 'Main',         id: 'notifications',     label: 'Notifications',       tab: 'notif' },
  { g: 'Main',         id: 'dm-list',           label: 'Chat · List',           tab: null,    hideNav: true },
  { g: 'Main',         id: 'dm-thread',         label: 'Chat · Thread',         tab: null,    hideNav: true },
  { g: 'Main',         id: 'me',                label: 'Profile',             tab: 'me'    },
  { g: 'Main',         id: 'settings',          label: 'Settings',            tab: 'me',    hideNav: true },
  { g: 'Main',         id: 'business',          label: 'Business Dashboard',  tab: 'me',    hideNav: true },
];

const TAB_TO_SCREEN = { feed: 'feed', map: 'map', post: 'post', notif: 'notifications', me: 'me' };

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "screenId":       "feed",
  "screenState":    "default",
  "feedVariant":    "editorial",
  "theme":          "dark",
  "accent":         ["#FF4D8D", "#FF7B5C", "#FFB347"],
  "glow":           70,
  "radiusPreset":   "standard",
  "displayFont":    "Nunito",
  "showBezel":      true,
  "showMeta":       true
}/*EDITMODE-END*/;

const FONT_OPTIONS = ['Nunito', 'Magnolia Script', 'Playfair Display', 'Bricolage Grotesque', 'DM Serif Display', 'Space Grotesk'];
const ACCENT_OPTIONS = [
  ['#FF4D8D', '#FF7B5C', '#FFB347'],         // magenta → amber (default)
  ['#7B2FF7', '#B14CF7', '#FF4D8D'],         // electric purple → magenta
  ['#3DD68C', '#5C7BFF', '#7B2FF7'],         // mint → blue → purple
  ['#FFB347', '#FF7B5C', '#FF4D8D'],         // amber → coral → magenta
];
const RADIUS_PRESETS = {
  sharp:    { sm: 6,  md: 10, lg: 14, xl: 20 },
  standard: { sm: 12, md: 16, lg: 22, xl: 28 },
  round:    { sm: 16, md: 22, lg: 30, xl: 38 },
};

// ─── Phone bezel ───
function PhoneBezel({ children, show = true }) {
  const W = 393, H = 852, bezel = 11;
  if (!show) {
    return (
      <div data-phone-bezel style={{
        width: W, height: H, borderRadius: 38, overflow: 'hidden',
        background: '#0B0118',
        boxShadow: '0 30px 80px rgba(0,0,0,0.5)',
        position: 'relative',
      }}>{children}</div>
    );
  }
  return (
    <div data-phone-bezel style={{
      width: W + bezel * 2, height: H + bezel * 2,
      borderRadius: 56,
      background: 'linear-gradient(135deg, #1a1a1a 0%, #050505 100%)',
      padding: bezel,
      boxShadow: `
        0 0 0 1px rgba(255,255,255,0.04),
        0 60px 120px rgba(0,0,0,0.7),
        0 30px 60px rgba(255,77,141,0.06),
        inset 0 0 0 1.5px rgba(255,255,255,0.05)
      `,
      position: 'relative',
    }}>
      <div style={{
        width: W, height: H,
        borderRadius: 44, overflow: 'hidden',
        background: '#0B0118',
        position: 'relative',
      }}>
        {children}
      </div>
    </div>
  );
}

// ─── Screen registry / renderer ───
function renderScreen({ id, go, state, feedVariant }) {
  const props = { go, state };
  switch (id) {
    case 'splash':            return <ScreenSplash {...props}/>;
    case 'onboarding-1':      return <ScreenOnboarding {...props} slide={1}/>;
    case 'onboarding-2':      return <ScreenOnboarding {...props} slide={2}/>;
    case 'onboarding-3':      return <ScreenOnboarding {...props} slide={3}/>;
    case 'perm-location':     return <ScreenPermission {...props} kind="location"/>;
    case 'perm-notification': return <ScreenPermission {...props} kind="notification"/>;
    case 'auth-landing':      return <ScreenAuthLanding {...props}/>;
    case 'login':             return <ScreenLogin {...props}/>;
    case 'register':          return <ScreenRegister {...props}/>;
    case 'setup':             return <ScreenSetup {...props}/>;
    case 'feed':              return <ScreenFeed {...props} variant={feedVariant}/>;
    case 'post-detail':       return <ScreenPostDetail {...props}/>;
    case 'creator':           return <ScreenCreator {...props}/>;
    case 'qpay':              return <ScreenQPay {...props}/>;
    case 'map':               return <ScreenMap {...props}/>;
    case 'bar':               return <ScreenBar {...props}/>;
    case 'post':              return <ScreenCreate {...props}/>;
    case 'notifications':     return <ScreenNotifications {...props}/>;
    case 'dm-list':           return <ScreenDMList {...props}/>;
    case 'dm-thread':         return <ScreenDMThread {...props}/>;
    case 'me':                return <ScreenProfile {...props}/>;
    case 'settings':          return <ScreenSettings {...props}/>;
    case 'business':          return <ScreenBusiness {...props}/>;
    default: return <div style={{ padding: 40, color: '#fff' }}>?</div>;
  }
}

// ─── Main App ───
function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  // Expose theme setter for Settings screen + side effects bridge
  React.useEffect(() => {
    window.__setTheme = (v) => setTweak('theme', v);
    window.__goScreen = (id) => setTweak('screenId', id);
    return () => { delete window.__setTheme; delete window.__goScreen; };
  }, [setTweak]);

  // Apply accent palette + glow + radii + display font + theme as CSS variables
  React.useEffect(() => {
    const root = document.documentElement;
    root.setAttribute('data-theme', t.theme || 'dark');
    const [s, m, e] = t.accent;
    root.style.setProperty('--accent-start', s);
    root.style.setProperty('--accent-mid',   m);
    root.style.setProperty('--accent-end',   e);
    root.style.setProperty('--accent-grad',
      `linear-gradient(135deg, ${s} 0%, ${m} 50%, ${e} 100%)`);
    root.style.setProperty('--accent-grad-soft',
      `linear-gradient(135deg, ${s}33 0%, ${e}1f 100%)`);
    root.style.setProperty('--shadow-glow',
      `0 0 ${0.32 * t.glow}px ${s}, 0 0 ${0.8 * t.glow}px ${e}26`);

    const r = RADIUS_PRESETS[t.radiusPreset] || RADIUS_PRESETS.standard;
    root.style.setProperty('--r-sm', `${r.sm}px`);
    root.style.setProperty('--r-md', `${r.md}px`);
    root.style.setProperty('--r-lg', `${r.lg}px`);
    root.style.setProperty('--r-xl', `${r.xl}px`);

    root.style.setProperty('--ff-display', `'${t.displayFont}', system-ui, sans-serif`);

    // glow opacity on .ns-bloom (animation already uses currentColor proxies — control via CSS var)
    root.style.setProperty('--bloom-opacity', String(t.glow / 100));
  }, [t.accent, t.glow, t.radiusPreset, t.displayFont, t.theme]);

  // Load extra fonts on demand
  React.useEffect(() => {
    const extras = FONT_OPTIONS.filter(f => f !== 'Bricolage Grotesque');
    extras.forEach(f => {
      const id = 'font-' + f.replace(/\s+/g, '-');
      if (document.getElementById(id)) return;
      const link = document.createElement('link');
      link.id = id;
      link.rel = 'stylesheet';
      link.href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(f)}:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500&display=swap`;
      document.head.appendChild(link);
    });
  }, []);

  const go = (id) => {
    // Tab key → main screen
    if (TAB_TO_SCREEN[id]) id = TAB_TO_SCREEN[id];
    setTweak('screenId', id);
  };

  const current = SCREENS.find(s => s.id === t.screenId) || SCREENS[0];
  const i = SCREENS.findIndex(s => s.id === current.id);

  const showNav = current.tab !== null && !current.hideNav;

  return (
    <>
      <div style={{
        position: 'fixed', inset: 0,
        background: `
          radial-gradient(circle at 20% 20%, rgba(123,47,247,0.12), transparent 30%),
          radial-gradient(circle at 80% 80%, rgba(255,77,141,0.10), transparent 32%),
          #050010
        `,
      }}/>

      <main style={{
        position: 'relative',
        minHeight: '100vh',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: '40px 20px',
        gap: 40,
      }}>
        {/* Side: prev */}
        <SideArrow dir="left" disabled={i === 0}
          onClick={() => go(SCREENS[Math.max(0, i - 1)].id)}/>

        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20 }}>
          {t.showMeta && <ScreenLabel index={i + 1} total={SCREENS.length} screen={current}/>}

          <PhoneBezel show={t.showBezel}>
            {renderScreen({
              id: current.id,
              go,
              state: t.screenState,
              feedVariant: t.feedVariant,
            })}

            {showNav && (
              <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}>
                <BottomNav
                  tab={current.tab}
                  onTab={(k) => go(k)}
                  onCenterPress={() => go('post')}
                />
              </div>
            )}
          </PhoneBezel>

          {t.showMeta && (
            <div style={{
              fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
              letterSpacing: '0.16em', textTransform: 'uppercase',
              color: 'rgba(185,169,212,0.4)',
            }}>
              ← → дарж дэлгэц солих
            </div>
          )}
        </div>

        <SideArrow dir="right" disabled={i === SCREENS.length - 1}
          onClick={() => go(SCREENS[Math.min(SCREENS.length - 1, i + 1)].id)}/>
      </main>

      {/* keyboard nav */}
      <KeyNav onPrev={() => { if (i > 0) go(SCREENS[i - 1].id); }}
              onNext={() => { if (i < SCREENS.length - 1) go(SCREENS[i + 1].id); }}/>

      {/* Tweaks panel */}
      <TweaksPanel>
        <TweakSection label="Дэлгэц"/>
        <ScreenJumper screens={SCREENS} value={t.screenId} onChange={(v) => setTweak('screenId', v)}/>
        <TweakRadio label="Төлөв"
          value={t.screenState}
          options={['default', 'empty', 'loading', 'error']}
          onChange={(v) => setTweak('screenState', v)}/>

        <TweakSection label="Тэжээлийн стиль"/>
        <TweakRadio label="Variant"
          value={t.feedVariant}
          options={['editorial', 'magazine', 'minimal']}
          onChange={(v) => setTweak('feedVariant', v)}/>

        <TweakSection label="Brand"/>
        <TweakRadio label="Theme"
          value={t.theme}
          options={['dark', 'light']}
          onChange={(v) => setTweak('theme', v)}/>
        <TweakColor label="Accent palette"
          value={t.accent}
          options={ACCENT_OPTIONS}
          onChange={(v) => setTweak('accent', v)}/>
        <TweakSlider label="Glow"
          value={t.glow} min={0} max={120} unit=""
          onChange={(v) => setTweak('glow', v)}/>
        <TweakRadio label="Corner radius"
          value={t.radiusPreset}
          options={['sharp', 'standard', 'round']}
          onChange={(v) => setTweak('radiusPreset', v)}/>
        <TweakSelect label="Display font"
          value={t.displayFont}
          options={FONT_OPTIONS}
          onChange={(v) => setTweak('displayFont', v)}/>

        <TweakSection label="Frame"/>
        <TweakToggle label="iPhone bezel"
          value={t.showBezel} onChange={(v) => setTweak('showBezel', v)}/>
        <TweakToggle label="Screen meta"
          value={t.showMeta} onChange={(v) => setTweak('showMeta', v)}/>
      </TweaksPanel>
    </>
  );
}

// ─── Screen meta label above phone ───
function ScreenLabel({ index, total, screen }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
      letterSpacing: '0.18em', textTransform: 'uppercase',
      color: 'rgba(185,169,212,0.65)',
    }}>
      <span>{String(index).padStart(2, '0')} / {String(total).padStart(2, '0')}</span>
      <span style={{ opacity: 0.3 }}>·</span>
      <span style={{ color: '#FFB347', fontWeight: 600 }}>{screen.g}</span>
      <span style={{ opacity: 0.3 }}>·</span>
      <span style={{ color: '#fff' }}>{screen.label}</span>
    </div>
  );
}

// ─── Side arrow ───
function SideArrow({ dir, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled} style={{
      width: 52, height: 52, borderRadius: 26,
      background: 'rgba(26,11,46,0.6)',
      border: '1px solid rgba(255,255,255,0.08)',
      backdropFilter: 'blur(20px)',
      color: disabled ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.85)',
      cursor: disabled ? 'default' : 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      opacity: disabled ? 0.5 : 1,
      flexShrink: 0,
    }}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor"
           strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        {dir === 'left'
          ? <path d="M15 6l-6 6 6 6"/>
          : <path d="M9 6l6 6-6 6"/>}
      </svg>
    </button>
  );
}

// ─── Screen jumper ───
function ScreenJumper({ screens, value, onChange }) {
  const groups = ['Onboarding', 'Auth', 'Main'];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: '8px 0' }}>
      {groups.map(g => (
        <div key={g}>
          <div style={{
            fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
            letterSpacing: '0.14em', textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.4)', marginBottom: 6,
          }}>{g}</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {screens.filter(s => s.g === g).map(s => {
              const on = s.id === value;
              return (
                <button key={s.id} onClick={() => onChange(s.id)}
                  style={{
                    textAlign: 'left',
                    padding: '6px 10px',
                    borderRadius: 8,
                    background: on ? 'rgba(255,77,141,0.18)' : 'transparent',
                    border: on ? '1px solid rgba(255,77,141,0.3)' : '1px solid transparent',
                    color: on ? '#fff' : 'rgba(255,255,255,0.7)',
                    fontSize: 12, fontWeight: on ? 600 : 400,
                    cursor: 'pointer',
                  }}>
                  {s.label}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── Keyboard navigation ───
function KeyNav({ onPrev, onNext }) {
  React.useEffect(() => {
    const handler = (e) => {
      // ignore if focused in input
      const tag = (e.target?.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'textarea') return;
      if (e.key === 'ArrowLeft')  onPrev();
      if (e.key === 'ArrowRight') onNext();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onPrev, onNext]);
  return null;
}

// mount
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
