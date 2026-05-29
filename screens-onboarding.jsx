/* screens-onboarding.jsx
   01 Splash · 02 Onboarding (3 slides) · 03 Permission Location · 04 Permission Notification
*/

// ────────────────────────────────────────────────────────────
// 01 — SPLASH
// ────────────────────────────────────────────────────────────
function ScreenSplash({ go, state, language }) {
  React.useEffect(() => {
    if (state !== 'default') return;
    const id = setTimeout(() => go('lang-select'), 2400);
    return () => clearTimeout(id);
  }, [state, go]);

  if (state === 'error') {
    return (
      <div className="ns-screen" style={{ background: 'var(--bg-base)' }}>
        <PhoneStatus/>
        <ErrorState
          title={tr('err.noConnection', language)}
          body={tr('err.checkInternet', language)}
          onRetry={() => go('splash')}
        />
      </div>
    );
  }

  const isEN = language === 'en';

  return (
    <div className="ns-screen" style={{ background: 'var(--bg-base)' }}>
      <div className="ns-starfield"/>
      <div className="ns-aurora" style={{ top: -120, left: -80, opacity: 0.7 }}/>
      <div className="ns-aurora" style={{ bottom: -120, right: -80, opacity: 0.5,
            background: 'radial-gradient(circle, rgba(255,179,71,0.22), transparent 70%)' }}/>

      <PhoneStatus/>

      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        position: 'relative', zIndex: 2, padding: '0 32px', gap: 32,
      }}>
        <OwlMark size={140} slotId="splash-owl"/>
        <div style={{ textAlign: 'center' }}>
          <h1 style={{
            margin: 0, fontFamily: 'var(--ff-display)',
            fontSize: 38, fontWeight: 500, letterSpacing: '-0.02em', lineHeight: 1,
          }}>
            {isEN
              ? <>Night<br/><span className="ns-grad-text" style={{ fontStyle: 'italic' }}>Owl</span></>
              : <>Шөнийн<br/><span className="ns-grad-text" style={{ fontStyle: 'italic' }}>шувуухай</span></>
            }
          </h1>
          <div style={{ marginTop: 14 }} className="ns-mono">Night Owl · UB</div>
        </div>
      </div>

      <div style={{ padding: '0 48px 60px', position: 'relative', zIndex: 2 }}>
        {state === 'loading' || state === 'default' ? (
          <div style={{
            height: 3, width: '100%', borderRadius: 2,
            background: 'rgba(255,255,255,0.06)', overflow: 'hidden',
          }}>
            <div style={{
              height: '100%', width: '40%', borderRadius: 2,
              background: 'var(--accent-grad)',
              animation: 'ns-loader 1.6s ease-in-out infinite',
            }}/>
          </div>
        ) : null}
      </div>

      <style>{`
        @keyframes ns-loader {
          0%   { transform: translateX(-100%); }
          100% { transform: translateX(350%); }
        }
      `}</style>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 02 — ONBOARDING (3 slides as one component, internal carousel)
// ────────────────────────────────────────────────────────────
function ScreenOnboarding({ go, state, slide = 1, language }) {
  const slides = [
    { icon: 'compass', titleKey: 'onb.1.title', subKey: 'onb.1.sub' },
    { icon: 'film',    titleKey: 'onb.2.title', subKey: 'onb.2.sub' },
    { icon: 'pin',     titleKey: 'onb.3.title', subKey: 'onb.3.sub' },
  ];
  const s = slides[slide - 1];
  const isLast = slide === 3;

  const next = () => {
    if (isLast) go('perm-location');
    else go(`onboarding-${slide + 1}`);
  };

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{
        top: 40, right: -120, opacity: 0.6,
        background: `radial-gradient(circle, ${
          slide === 1 ? 'rgba(255,77,141,0.3)' :
          slide === 2 ? 'rgba(123,47,247,0.3)' :
                        'rgba(255,179,71,0.3)'
        }, transparent 70%)`,
      }}/>

      <PhoneStatus/>

      <div style={{
        display: 'flex', justifyContent: 'space-between',
        padding: '8px 28px 0', alignItems: 'center', zIndex: 2,
      }}>
        <ScreenMeta index={1 + slide} total={19} label={`Slide ${slide}/3`}/>
        <button className="ns-btn-ghost" onClick={() => go('auth-landing')}>
          {tr('btn.skip', language)}
        </button>
      </div>

      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        padding: '0 40px', gap: 28, position: 'relative', zIndex: 2,
      }}>
        <div style={{ position: 'relative' }}>
          <div style={{
            width: 200, height: 200, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(255,77,141,0.18), transparent 65%)',
            position: 'absolute', inset: 0,
          }}/>
          <div style={{
            position: 'absolute', inset: -20, borderRadius: '50%',
            border: '1px dashed rgba(255,255,255,0.08)',
            animation: 'ns-spin 32s linear infinite',
          }}/>
          <div style={{
            width: 200, height: 200, borderRadius: '50%',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            position: 'relative', color: '#fff',
            filter: 'drop-shadow(0 0 24px rgba(255,77,141,0.55)) drop-shadow(0 0 48px rgba(255,179,71,0.25))',
          }}>
            <Icon name={s.icon} size={72} strokeWidth={1.2} stroke="#fff"/>
          </div>
        </div>

        <div style={{ textAlign: 'center', maxWidth: 320 }}>
          <h1 style={{
            margin: 0, fontFamily: 'var(--ff-display)', fontSize: 32,
            fontWeight: 500, letterSpacing: '-0.02em', lineHeight: 1.05,
            textWrap: 'balance',
          }}>{tr(s.titleKey, language)}</h1>
          <p style={{
            margin: '14px 0 0', fontSize: 15, lineHeight: 1.5,
            color: 'var(--text-secondary)',
          }}>{tr(s.subKey, language)}</p>
        </div>
      </div>

      <div style={{
        padding: '0 32px 56px', display: 'flex',
        alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', gap: 8 }}>
          {[1, 2, 3].map(i => (
            <div key={i} style={{
              width: i === slide ? 28 : 8,
              height: 8, borderRadius: 4,
              background: i === slide ? 'var(--accent-grad)' : 'rgba(255,255,255,0.15)',
              transition: 'width .3s ease',
            }}/>
          ))}
        </div>
        <button className="ns-btn-primary"
          style={{ height: 56, width: isLast ? 'auto' : 56, padding: isLast ? '0 28px' : 0, borderRadius: 28 }}
          onClick={next}>
          {isLast ? tr('btn.start', language) : <Icon name="arrow-right" size={22} stroke="#1B0210" strokeWidth={2}/>}
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 03 — PERMISSION: LOCATION
// 04 — PERMISSION: NOTIFICATION
// ────────────────────────────────────────────────────────────
function ScreenPermission({ go, state, kind, language }) {
  const isLoc = kind === 'location';
  const next = isLoc ? 'perm-notification' : 'auth-landing';
  const meta = isLoc
    ? { idx: 5, label: 'Permission · Location',
        icon: 'pin',
        titleKey: 'perm.loc.title',
        bodyKey: 'perm.loc.body' }
    : { idx: 6, label: 'Permission · Notification',
        icon: 'bell',
        titleKey: 'perm.notif.title',
        bodyKey: 'perm.notif.body' };

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{
        bottom: -120, left: -100, opacity: 0.7,
      }}/>
      <PhoneStatus/>
      <div style={{ padding: '8px 28px 0' }}>
        <ScreenMeta index={meta.idx} total={19} label={meta.label}/>
      </div>

      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        padding: '0 36px', gap: 28, position: 'relative', zIndex: 2,
      }}>
        <div style={{
          width: 160, height: 160, borderRadius: '50%',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'radial-gradient(circle, rgba(255,77,141,0.2), transparent 65%)',
          color: '#fff',
          filter: 'drop-shadow(0 0 20px rgba(255,77,141,0.6))',
          position: 'relative',
        }}>
          <div style={{ position: 'absolute', inset: 0, borderRadius: '50%',
            border: '1px solid rgba(255,77,141,0.2)' }}/>
          <div style={{ position: 'absolute', inset: 18, borderRadius: '50%',
            border: '1px solid rgba(255,255,255,0.08)' }}/>
          <Icon name={meta.icon} size={64} strokeWidth={1.2}/>
        </div>

        <div style={{ textAlign: 'center', maxWidth: 320 }}>
          <h1 style={{
            margin: 0, fontFamily: 'var(--ff-display)', fontSize: 28,
            fontWeight: 500, letterSpacing: '-0.01em', lineHeight: 1.1,
            textWrap: 'balance',
          }}>{tr(meta.titleKey, language)}</h1>
          <p style={{
            margin: '16px 0 0', fontSize: 14, lineHeight: 1.55,
            color: 'var(--text-secondary)',
          }}>{tr(meta.bodyKey, language)}</p>
        </div>
      </div>

      <div style={{ padding: '0 28px 56px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go(next)}>
          {tr('btn.allow', language)}
        </button>
        <button className="ns-btn-ghost" style={{ height: 44, alignSelf: 'center' }} onClick={() => go(next)}>
          {tr('btn.later', language)}
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 01b — LANGUAGE SELECT
// ────────────────────────────────────────────────────────────
function ScreenLangSelect({ go, state, language }) {
  const [selected, setSelected] = React.useState(language || 'en');

  // Keep in sync if tweaks panel language changes while on this screen
  React.useEffect(() => { setSelected(language || 'en'); }, [language]);

  const proceed = () => {
    if (typeof window.__setLanguage === 'function') window.__setLanguage(selected);
    go('onboarding-1');
  };

  const opts = [
    { value: 'en', label: 'English' },
    { value: 'mn', label: 'Монгол' },
  ];

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ top: -100, right: -100, opacity: 0.55,
        background: 'radial-gradient(circle, rgba(255,77,141,0.32), transparent 70%)' }}/>
      <div className="ns-aurora" style={{ bottom: -120, left: -80, opacity: 0.4 }}/>

      <PhoneStatus/>

      {/* header */}
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        padding: '8px 28px 0', alignItems: 'center', zIndex: 2,
      }}>
        <ScreenMeta index={2} total={24} label="Language"/>
        <button className="ns-btn-ghost" onClick={() => go('auth-landing')}
          style={{ color: 'rgba(255,255,255,0.7)' }}>
          {tr('btn.skip', selected)}
        </button>
      </div>

      {/* option list */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        padding: '0 40px', gap: 16, position: 'relative', zIndex: 2,
      }}>
        {opts.map(opt => {
          const on = selected === opt.value;
          return (
            <button
              key={opt.value}
              onClick={() => setSelected(opt.value)}
              style={{
                width: '100%', height: 62, borderRadius: 31,
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                padding: '0 22px',
                background: on ? 'var(--accent-grad)' : 'rgba(255,255,255,0.04)',
                border: on ? 'none' : '1.5px solid rgba(255,255,255,0.18)',
                color: on ? '#1B0210' : 'var(--text-primary)',
                cursor: 'pointer',
                boxShadow: on ? '0 8px 28px rgba(255,77,141,0.38)' : 'none',
                transition: 'all .2s ease',
                fontFamily: 'var(--ff-body)', fontSize: 18, fontWeight: 700,
                letterSpacing: '0.01em',
              }}>
              <span>{opt.label}</span>
              <span style={{
                width: 28, height: 28, borderRadius: '50%', flexShrink: 0,
                background: on ? 'rgba(27,2,16,0.22)' : 'transparent',
                border: on ? 'none' : '1.5px solid rgba(255,255,255,0.3)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                transition: 'all .2s ease',
              }}>
                {on && <Icon name="check" size={16} stroke="#1B0210" strokeWidth={2.8}/>}
              </span>
            </button>
          );
        })}
      </div>

      {/* bottom: dots + arrow */}
      <div style={{
        padding: '0 32px 56px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        position: 'relative', zIndex: 2,
      }}>
        {/* page dots (3 = upcoming onboarding slides) */}
        <div style={{ display: 'flex', gap: 8 }}>
          {[0, 1, 2].map(i => (
            <div key={i} style={{
              width: 8, height: 8, borderRadius: 4,
              background: 'rgba(255,255,255,0.15)',
            }}/>
          ))}
        </div>

        {/* continue text button (centered) */}
        <button
          className="ns-btn-primary"
          style={{ height: 50, padding: '0 32px', borderRadius: 25, fontSize: 13,
            letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 700 }}
          onClick={proceed}>
          {tr('ui.continue', selected)}
        </button>

        {/* arrow circle button */}
        <button
          className="ns-btn-primary"
          style={{ width: 56, height: 56, borderRadius: 28, padding: 0 }}
          onClick={proceed}>
          <Icon name="arrow-right" size={22} stroke="#1B0210" strokeWidth={2}/>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenSplash, ScreenOnboarding, ScreenPermission, ScreenLangSelect });
