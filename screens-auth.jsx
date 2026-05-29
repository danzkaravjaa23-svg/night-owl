/* screens-auth.jsx
   05 Auth Landing · 06 Login · 07 Register · 08 Profile Setup
*/

// ────────────────────────────────────────────────────────────
// 05 — AUTH LANDING
// ────────────────────────────────────────────────────────────
function ScreenAuthLanding({ go, state, language }) {
  return (
    <div className="ns-screen">
      <div style={{
        position: 'absolute', inset: 0,
        background: `
          radial-gradient(circle at 20% 30%, rgba(255,77,141,0.35), transparent 30%),
          radial-gradient(circle at 80% 25%, rgba(255,179,71,0.30), transparent 32%),
          radial-gradient(circle at 50% 70%, rgba(123,47,247,0.35), transparent 35%),
          radial-gradient(circle at 15% 80%, rgba(255,77,141,0.20), transparent 28%),
          var(--bg-base)
        `,
        filter: 'blur(40px)',
      }}/>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(11,1,24,0.4)' }}/>
      <div className="ns-starfield"/>

      <PhoneStatus/>

      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        position: 'relative', zIndex: 2, padding: '0 32px',
      }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'flex-end', paddingBottom: 24, gap: 20 }}>
          <OwlMark size={110} slotId="auth-owl"/>
          <div style={{ textAlign: 'center' }}>
            <h1 style={{
              margin: 0, fontFamily: 'var(--ff-display)', fontSize: 36,
              fontWeight: 800, letterSpacing: '-0.02em', lineHeight: 1,
            }}>
              {language === 'mn'
                ? <>Шөнө<span className="ns-grad-text" style={{ fontWeight: 800 }}> эхэлж</span> байна</>
                : <>The<span className="ns-grad-text" style={{ fontWeight: 800 }}> Night</span> Begins</>
              }
            </h1>
            <p style={{ margin: '12px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
              {tr('auth.sub', language)}
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingBottom: 56 }}>
          <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('login')}>
            {tr('auth.signIn', language)}
          </button>
          <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('register')}>
            {tr('auth.register', language)}
          </button>

          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, margin: '12px 0 4px',
            color: 'var(--text-tertiary)', fontSize: 11, letterSpacing: '0.14em',
          }}>
            <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
            {tr('auth.or', language)}
            <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
          </div>

          <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('setup')}>
            <span style={{
              width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'serif', fontWeight: 700, fontSize: 13,
            }}>G</span>
            {tr('auth.withGoogle', language)}
          </button>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 06 — LOGIN
// ────────────────────────────────────────────────────────────
function ScreenLogin({ go, state, language }) {
  const [showPw, setShowPw] = React.useState(false);
  const isError = state === 'error';

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ top: -120, right: -100, opacity: 0.5 }}/>
      <PhoneStatus/>

      <div style={{ padding: '8px 28px 0', display: 'flex', justifyContent: 'space-between' }}>
        <button onClick={() => go('auth-landing')} style={{
          background: 'transparent', border: 0, color: 'var(--text-secondary)',
          cursor: 'pointer', padding: 8, marginLeft: -8,
        }}><Icon name="arrow-left" size={22}/></button>
        <ScreenMeta index={7} total={19} label="Login"/>
      </div>

      <div style={{ padding: '32px 28px 0' }}>
        <PageTitle>{tr('auth.signIn', language)}</PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
          {tr('login.welcome', language)}
        </p>
      </div>

      {state === 'loading' ? (
        <LoadingState label={tr('login.loading', language)}/>
      ) : (
        <div style={{ padding: '36px 28px 0', display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>
              {tr('auth.email', language)}
            </label>
            <input className="ns-input" type="email" placeholder="you@example.com"
              defaultValue={isError ? 'bayar@nightowl.mn' : ''}
              style={isError ? { borderColor: 'var(--error)' } : {}}/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>
              {tr('auth.password', language)}
            </label>
            <div style={{ position: 'relative' }}>
              <input className="ns-input" type={showPw ? 'text' : 'password'}
                placeholder="••••••••" defaultValue={isError ? '••••••' : ''}
                style={isError ? { borderColor: 'var(--error)', paddingRight: 48 } : { paddingRight: 48 }}/>
              <button onClick={() => setShowPw(!showPw)} style={{
                position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)',
                background: 'transparent', border: 0, color: 'var(--text-secondary)', cursor: 'pointer',
                padding: 6,
              }}><Icon name="eye" size={18}/></button>
            </div>
            {isError && (
              <div style={{
                marginTop: 8, fontSize: 12, color: 'var(--error)',
                display: 'flex', alignItems: 'center', gap: 6,
              }}>
                <Icon name="alert" size={14}/>
                {tr('login.error', language)}
              </div>
            )}
          </div>
          <button className="ns-btn-ghost" style={{
            alignSelf: 'flex-end', height: 32, padding: 0,
            color: 'var(--accent-start)', fontSize: 13, fontWeight: 600,
          }} onClick={() => go('forgot-password')}>
            {tr('login.forgot', language)}
          </button>
        </div>
      )}

      <div style={{ flex: 1 }}/>

      <div style={{ padding: '0 28px 28px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('feed')}>
          {tr('auth.signIn', language)}
        </button>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          color: 'var(--text-tertiary)', fontSize: 11, letterSpacing: '0.14em',
        }}>
          <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
          {tr('auth.or', language)}
          <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
        </div>
        <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('feed')}>
          <span style={{
            width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'serif', fontWeight: 700, fontSize: 13,
          }}>G</span>
          {tr('login.withGoogle', language)}
        </button>
        <div style={{ textAlign: 'center', fontSize: 13, color: 'var(--text-secondary)', marginTop: 4 }}>
          {tr('login.noAccount', language)}{' '}
          <span onClick={() => go('register')} style={{
            color: 'var(--accent-start)', fontWeight: 700, cursor: 'pointer',
          }}>{tr('auth.register', language)}</span>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 07 — REGISTER
// ────────────────────────────────────────────────────────────
function ScreenRegister({ go, state, language }) {
  const [checked, setChecked] = React.useState(false);
  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ top: -100, left: -100, opacity: 0.5,
            background: 'radial-gradient(circle, rgba(255,179,71,0.2), transparent 70%)' }}/>
      <PhoneStatus/>

      <div style={{ padding: '8px 28px 0', display: 'flex', justifyContent: 'space-between' }}>
        <button onClick={() => go('auth-landing')} style={{
          background: 'transparent', border: 0, color: 'var(--text-secondary)',
          cursor: 'pointer', padding: 8, marginLeft: -8,
        }}><Icon name="arrow-left" size={22}/></button>
        <ScreenMeta index={8} total={19} label="Register"/>
      </div>

      <div style={{ padding: '24px 28px 0' }}>
        <PageTitle>{tr('auth.register', language)}</PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 13, color: 'var(--text-secondary)' }}>
          {tr('reg.sub', language)}
        </p>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '24px 28px 24px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[
            { labelKey: 'reg.name',             placeholder: language === 'mn' ? 'Болд' : 'Alex',      type: 'text' },
            { labelKey: 'auth.email',            placeholder: 'bold@nightowl.mn',                       type: 'email' },
            { labelKey: 'auth.password',         placeholder: '••••••••',                               type: 'password' },
            { labelKey: 'auth.confirmPassword',  placeholder: '••••••••',                               type: 'password' },
          ].map(f => (
            <div key={f.labelKey}>
              <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>
                {tr(f.labelKey, language)}
              </label>
              <input className="ns-input" type={f.type} placeholder={f.placeholder}/>
            </div>
          ))}

          <label style={{
            display: 'flex', alignItems: 'flex-start', gap: 10, marginTop: 8,
            fontSize: 12, color: 'var(--text-secondary)', cursor: 'pointer',
          }}>
            <span
              onClick={() => setChecked(!checked)}
              style={{
                width: 20, height: 20, borderRadius: 6, flexShrink: 0,
                background: checked ? 'var(--accent-grad)' : 'transparent',
                border: checked ? 0 : '1.5px solid var(--hairline-2)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                color: '#1B0210',
              }}>
              {checked && <Icon name="check" size={14} stroke="#1B0210" strokeWidth={2.5}/>}
            </span>
            <span style={{ lineHeight: 1.45 }}>
              {language === 'mn' ? (
                <>
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{tr('auth.tos', language)}</span>
                  {' ба '}
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{tr('auth.privacy', language)}</span>
                  {tr('reg.tosAgree', language)}
                </>
              ) : (
                <>
                  {tr('reg.tosAgree', language)}{' '}
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{tr('auth.tos', language)}</span>
                  {' '}{tr('reg.and', language)}{' '}
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{tr('auth.privacy', language)}</span>
                </>
              )}
            </span>
          </label>
        </div>
      </div>

      <div style={{ padding: '0 28px 28px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('setup')}>
          {tr('auth.register', language)}
        </button>
        <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('setup')}>
          <span style={{
            width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'serif', fontWeight: 700, fontSize: 13,
          }}>G</span>
          {tr('reg.withGoogle', language)}
        </button>
        <div style={{ textAlign: 'center', fontSize: 13, color: 'var(--text-secondary)' }}>
          {tr('reg.hasAccount', language)}{' '}
          <span onClick={() => go('login')} style={{
            color: 'var(--accent-start)', fontWeight: 700, cursor: 'pointer',
          }}>{tr('auth.signIn', language)}</span>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 08 — PROFILE SETUP
// ────────────────────────────────────────────────────────────
function ScreenSetup({ go, state, language, profile }) {
  const interests = ['Bar', 'Lounge', 'Live music', 'DJ', 'Cocktail', 'Karaoke', 'Pub', 'Hookah'];
  const [picked,   setPicked]   = React.useState(profile?.interests || ['Bar', 'Live music', 'Cocktail']);
  const [username, setUsername] = React.useState(profile?.username  ? `@${profile.username}` : '@bold_ub');
  const [bio,      setBio]      = React.useState(profile?.bio       || '');

  const toggle = (x) => setPicked(p => p.includes(x) ? p.filter(y => y !== x) : [...p, x]);

  // Derive display name: "@sugar_247" → "Sugar 247"
  const toDisplayName = (raw) =>
    raw.replace(/^@/, '').replace(/[_.-]/g, ' ')
       .split(' ').map(w => w ? w[0].toUpperCase() + w.slice(1) : '').join(' ').trim() || raw;

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ bottom: -120, right: -120, opacity: 0.5 }}/>
      <PhoneStatus/>

      <div style={{ padding: '8px 28px 0', display: 'flex', justifyContent: 'space-between' }}>
        <button onClick={() => go('register')} style={{
          background: 'transparent', border: 0, color: 'var(--text-secondary)',
          cursor: 'pointer', padding: 8, marginLeft: -8,
        }}><Icon name="arrow-left" size={22}/></button>
        <ScreenMeta index={9} total={19} label="Setup"/>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '24px 28px 24px' }}>
        <PageTitle>
          {tr('setup.titleLine1', language)}<br/>
          <span className="ns-grad-text" style={{ fontStyle: 'italic' }}>
            {tr('setup.titleLine2', language)}
          </span>
        </PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
          {tr('setup.sub', language)}
        </p>

        <div style={{ display: 'flex', justifyContent: 'center', margin: '32px 0 28px' }}>
          <div style={{ position: 'relative' }}>
            <div className="ns-avatar has-ring" style={{ width: 110, height: 110 }}>
              <div className="ns-avatar-inner">
                <image-slot id="setup-avatar" shape="circle"
                  placeholder="📷"
                  style={{ width: '100%', height: '100%', display: 'block',
                    background: 'rgba(255,255,255,0.04)' }}>
                </image-slot>
              </div>
            </div>
            <div style={{
              position: 'absolute', right: -2, bottom: -2,
              width: 36, height: 36, borderRadius: '50%',
              background: 'var(--accent-grad)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 4px 12px rgba(255,77,141,0.4), 0 0 0 4px var(--bg-base)',
              color: '#1B0210',
            }}>
              <Icon name="camera" size={18} stroke="#1B0210" strokeWidth={2}/>
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>
              {tr('auth.username', language)}
            </label>
            <input className="ns-input" type="text" placeholder="@bold_ub"
              value={username}
              onChange={e => {
                let v = e.target.value;
                if (v && !v.startsWith('@')) v = '@' + v;
                setUsername(v);
              }}/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>
              {tr('setup.bio', language)}
            </label>
            <textarea className="ns-input" rows={3} placeholder={tr('setup.bioPh', language)}
              value={bio} onChange={e => setBio(e.target.value)}
              style={{ height: 'auto', paddingTop: 14, paddingBottom: 14, resize: 'none' }}/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 10, display: 'block' }}>
              {tr('setup.interests', language)}
            </label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {interests.map(i => (
                <span key={i} className={`ns-chip ${picked.includes(i) ? 'is-on' : ''}`}
                      onClick={() => toggle(i)}>
                  {i}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div style={{ padding: '0 28px 28px' }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => {
          const uname = username.replace(/^@/, '') || 'user';
          window.__setProfile?.({
            profileDisplayName: toDisplayName(username),
            profileUsername:    uname,
            profileBio:         bio,
            profileInterests:   picked,
          });
          window.__showNotification?.(tr('auth.agreed', language), 'check');
          setTimeout(() => go('feed'), 500);
        }}>
          {tr('btn.continue', language)}
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 09 — CHANGE PASSWORD
// ────────────────────────────────────────────────────────────
function ScreenChangePassword({ go, state, language }) {
  const [showCur,  setShowCur]  = React.useState(false);
  const [showNew,  setShowNew]  = React.useState(false);
  const [showConf, setShowConf] = React.useState(false);
  const [saved, setSaved] = React.useState(false);

  const fields = [
    { id: 'cur',  lKey: 'pw.current',  show: showCur,  toggle: () => setShowCur(v => !v) },
    { id: 'new',  lKey: 'pw.new',      show: showNew,  toggle: () => setShowNew(v => !v) },
    { id: 'conf', lKey: 'pw.confirm',  show: showConf, toggle: () => setShowConf(v => !v) },
  ];

  const save = () => {
    setSaved(true);
    window.__showNotification?.(language === 'mn' ? 'Нууц үг амжилттай солигдлоо' : 'Password changed successfully', 'check');
    setTimeout(() => go('settings'), 600);
  };

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ top: -100, left: -100, opacity: 0.4,
        background: 'radial-gradient(circle, rgba(123,47,247,0.25), transparent 70%)' }}/>
      <PhoneStatus/>

      {/* header */}
      <div style={{
        flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 12px 12px',
      }}>
        <button style={iconBtn} onClick={() => go('settings')}>
          <Icon name="arrow-left" size={22}/>
        </button>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>
          {tr('set.changePassword', language)}
        </div>
        <div style={{ width: 40 }}/>
      </div>

      <div style={{ padding: '12px 28px 0' }}>
        <p style={{ margin: 0, fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
          {language === 'mn'
            ? 'Аюулгүй байдлынхаа тулд хүчтэй нууц үг ашиглана уу.'
            : 'Use a strong password to keep your account secure.'}
        </p>
      </div>

      <div style={{ padding: '28px 28px 0', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {fields.map(f => (
          <div key={f.id}>
            <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>
              {tr(f.lKey, language)}
            </label>
            <div style={{ position: 'relative' }}>
              <input className="ns-input"
                type={f.show ? 'text' : 'password'}
                placeholder="••••••••"
                style={{ paddingRight: 48 }}/>
              <button onClick={f.toggle} style={{
                position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)',
                background: 'transparent', border: 0,
                color: 'var(--text-secondary)', cursor: 'pointer', padding: 6,
              }}>
                <Icon name="eye" size={18}/>
              </button>
            </div>
          </div>
        ))}
      </div>

      <div style={{ flex: 1 }}/>

      <div style={{ padding: '0 28px 40px' }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={save}>
          {language === 'mn' ? 'Хадгалах' : 'Save Changes'}
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 10 — FORGOT PASSWORD
// ────────────────────────────────────────────────────────────
function ScreenForgotPassword({ go, state, language }) {
  const [email, setEmail] = React.useState('');
  const [sent,  setSent]  = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [countdown, setCountdown] = React.useState(0);

  const send = () => {
    if (!email) return;
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setSent(true);
      setCountdown(30);
    }, 1400);
  };

  // countdown timer after send
  React.useEffect(() => {
    if (countdown <= 0) return;
    const id = setTimeout(() => setCountdown(c => c - 1), 1000);
    return () => clearTimeout(id);
  }, [countdown]);

  const resend = () => {
    if (countdown > 0) return;
    setLoading(true);
    setTimeout(() => { setLoading(false); setCountdown(30); }, 1200);
  };

  return (
    <div className="ns-screen">
      <div className="ns-aurora" style={{ top: -80, right: -80, opacity: 0.45,
        background: 'radial-gradient(circle, rgba(123,47,247,0.3), transparent 70%)' }}/>
      <PhoneStatus/>

      {/* header */}
      <div style={{ padding: '8px 28px 0', display: 'flex', justifyContent: 'space-between' }}>
        <button onClick={() => go('login')} style={{
          background: 'transparent', border: 0, color: 'var(--text-secondary)',
          cursor: 'pointer', padding: 8, marginLeft: -8,
        }}><Icon name="arrow-left" size={22}/></button>
        <ScreenMeta index={8} total={24} label="Forgot PW"/>
      </div>

      {sent ? (
        /* ── SUCCESS STATE ── */
        <div style={{
          flex: 1, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
          padding: '0 32px', gap: 0, position: 'relative', zIndex: 2,
        }}>
          {/* envelope icon with glow rings */}
          <div style={{ position: 'relative', marginBottom: 32 }}>
            {[100, 76].map((sz, i) => (
              <div key={i} style={{
                position: 'absolute', width: sz, height: sz, borderRadius: '50%',
                border: `1px solid rgba(123,47,247,${0.1 + i * 0.08})`,
                top: '50%', left: '50%', transform: 'translate(-50%,-50%)',
              }}/>
            ))}
            <div style={{
              width: 72, height: 72, borderRadius: '50%',
              background: 'radial-gradient(circle, rgba(123,47,247,0.25), rgba(255,77,141,0.12) 60%, transparent)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              filter: 'drop-shadow(0 0 20px rgba(123,47,247,0.5))',
              position: 'relative',
            }}>
              <svg width="34" height="34" viewBox="0 0 24 24" fill="none"
                   stroke="var(--accent-start)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="2" y="4" width="20" height="16" rx="2"/>
                <path d="M2 7l10 7 10-7"/>
              </svg>
            </div>
          </div>

          <h1 style={{ margin: 0, fontFamily: 'var(--ff-display)', fontSize: 26,
            fontWeight: 700, letterSpacing: '-0.01em', textAlign: 'center' }}>
            {language === 'mn' ? 'И-мэйл илгээгдлээ!' : 'Email sent!'}
          </h1>
          <p style={{ margin: '14px 0 0', fontSize: 14, color: 'var(--text-secondary)',
            textAlign: 'center', lineHeight: 1.6, maxWidth: 300 }}>
            {language === 'mn'
              ? <>
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{email || 'bayar@nightowl.mn'}</span>
                  {' руу нууц үг сэргээх холбоос явсан.'}
                </>
              : <>
                  {'A reset link was sent to '}
                  <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>{email || 'bayar@nightowl.mn'}</span>
                </>
            }
          </p>
          <p style={{ margin: '8px 0 0', fontSize: 13, color: 'var(--text-tertiary)',
            textAlign: 'center', lineHeight: 1.5 }}>
            {language === 'mn'
              ? 'Спам хавтасаа ч шалгаарай.'
              : 'Also check your spam folder.'}
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: '100%', marginTop: 36 }}>
            <button className="ns-btn-primary" style={{ width: '100%' }}
              onClick={() => go('login')}>
              {language === 'mn' ? 'Нэвтрэх рүү буцах' : 'Back to Sign In'}
            </button>
            <button onClick={resend} disabled={countdown > 0} style={{
              background: 'transparent', border: 0, cursor: countdown > 0 ? 'default' : 'pointer',
              color: countdown > 0 ? 'var(--text-tertiary)' : 'var(--accent-start)',
              fontSize: 13, fontWeight: 600, padding: '8px 0',
            }}>
              {countdown > 0
                ? (language === 'mn' ? `Дахин илгээх (${countdown}с)` : `Resend in ${countdown}s`)
                : (language === 'mn' ? 'Дахин илгээх'                 : 'Resend email')}
            </button>
          </div>
        </div>
      ) : (
        /* ── INPUT STATE ── */
        <>
          <div style={{ padding: '32px 28px 0' }}>
            <PageTitle>{language === 'mn' ? 'Нууц үг\nмартсан' : 'Forgot\nPassword'}</PageTitle>
            <p style={{ margin: '12px 0 0', fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.55 }}>
              {language === 'mn'
                ? 'И-мэйл хаягаа оруулна уу. Нууц үг сэргээх холбоос илгээнэ.'
                : "Enter your email and we'll send you a reset link."}
            </p>
          </div>

          {loading ? (
            <LoadingState label={language === 'mn' ? 'Илгээж байна...' : 'Sending...'}/>
          ) : (
            <div style={{ padding: '32px 28px 0' }}>
              <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>
                {tr('auth.email', language)}
              </label>
              <input
                className="ns-input"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={e => setEmail(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && send()}
              />
            </div>
          )}

          <div style={{ flex: 1 }}/>

          <div style={{ padding: '0 28px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <button className="ns-btn-primary" style={{ width: '100%' }}
              onClick={send} disabled={!email || loading}>
              {language === 'mn' ? 'Холбоос илгээх' : 'Send Reset Link'}
            </button>
            <button onClick={() => go('login')} style={{
              background: 'transparent', border: 0, cursor: 'pointer',
              color: 'var(--text-secondary)', fontSize: 13, fontWeight: 600, padding: '8px 0',
            }}>
              {language === 'mn' ? '← Нэвтрэх рүү буцах' : '← Back to Sign In'}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

Object.assign(window, { ScreenAuthLanding, ScreenLogin, ScreenRegister, ScreenSetup, ScreenChangePassword, ScreenForgotPassword });
