/* screens-auth.jsx
   05 Auth Landing · 06 Login · 07 Register · 08 Profile Setup
*/

// ────────────────────────────────────────────────────────────
// 05 — AUTH LANDING
// ────────────────────────────────────────────────────────────
function ScreenAuthLanding({ go, state }) {
  return (
    <div className="ns-screen">
      {/* blurred bokeh background */}
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
              Шөнө<span className="ns-grad-text" style={{ fontWeight: 800 }}> эхэлж</span> байна
            </h1>
            <p style={{ margin: '12px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
              УБ-ын бар, lounge-уудын нийгэм
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, paddingBottom: 56 }}>
          <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('login')}>
            Нэвтрэх
          </button>
          <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('register')}>
            Бүртгүүлэх
          </button>

          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, margin: '12px 0 4px',
            color: 'var(--text-tertiary)', fontSize: 11, letterSpacing: '0.14em',
          }}>
            <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
            ЭСВЭЛ
            <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
          </div>

          <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('setup')}>
            <span style={{
              width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'serif', fontWeight: 700, fontSize: 13,
            }}>G</span>
            Google-ээр үргэлжлүүлэх
          </button>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 06 — LOGIN
// ────────────────────────────────────────────────────────────
function ScreenLogin({ go, state }) {
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
        <PageTitle>Нэвтрэх</PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
          Шөнийн ертөнцөдөө буцаж тавтай морил
        </p>
      </div>

      {state === 'loading' ? (
        <LoadingState label="Нэвтэрч байна..."/>
      ) : (
        <div style={{ padding: '36px 28px 0', display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>И-мэйл</label>
            <input className="ns-input" type="email" placeholder="you@example.com"
              defaultValue={isError ? 'bayar@nightowl.mn' : ''}
              style={isError ? { borderColor: 'var(--error)' } : {}}/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>Нууц үг</label>
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
                И-мэйл эсвэл нууц үг буруу байна
              </div>
            )}
          </div>
          <button className="ns-btn-ghost" style={{
            alignSelf: 'flex-end', height: 32, padding: 0,
            color: 'var(--accent-start)', fontSize: 13, fontWeight: 600,
          }}>
            Нууц үг мартсан?
          </button>
        </div>
      )}

      <div style={{ flex: 1 }}/>

      <div style={{ padding: '0 28px 28px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('feed')}>
          Нэвтрэх
        </button>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          color: 'var(--text-tertiary)', fontSize: 11, letterSpacing: '0.14em',
        }}>
          <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
          ЭСВЭЛ
          <span style={{ flex: 1, height: 1, background: 'var(--hairline)' }}/>
        </div>
        <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('feed')}>
          <span style={{
            width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'serif', fontWeight: 700, fontSize: 13,
          }}>G</span>
          Google-ээр нэвтрэх
        </button>
        <div style={{ textAlign: 'center', fontSize: 13, color: 'var(--text-secondary)', marginTop: 4 }}>
          Бүртгэл байхгүй юу?{' '}
          <span onClick={() => go('register')} style={{
            color: 'var(--accent-start)', fontWeight: 700, cursor: 'pointer',
          }}>Бүртгүүлэх</span>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 07 — REGISTER
// ────────────────────────────────────────────────────────────
function ScreenRegister({ go, state }) {
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
        <PageTitle>Бүртгүүлэх</PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 13, color: 'var(--text-secondary)' }}>
          Шинэ хаяг үүсгээд клубт ор
        </p>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '24px 28px 24px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[
            { label: 'Нэр', placeholder: 'Болд', type: 'text' },
            { label: 'И-мэйл', placeholder: 'bold@nightowl.mn', type: 'email' },
            { label: 'Нууц үг', placeholder: '••••••••', type: 'password' },
            { label: 'Нууц үг давтах', placeholder: '••••••••', type: 'password' },
          ].map(f => (
            <div key={f.label}>
              <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>{f.label}</label>
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
              <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>Үйлчилгээний нөхцөл</span>
              {' ба '}
              <span style={{ color: 'var(--accent-start)', fontWeight: 600 }}>нууцлалын бодлого</span>
              -г уншиж зөвшөөрсөн
            </span>
          </label>
        </div>
      </div>

      <div style={{ padding: '0 28px 28px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('setup')}>
          Бүртгүүлэх
        </button>
        <button className="ns-btn-secondary" style={{ width: '100%' }} onClick={() => go('setup')}>
          <span style={{
            width: 20, height: 20, borderRadius: 4, background: '#fff', color: '#1f1f1f',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'serif', fontWeight: 700, fontSize: 13,
          }}>G</span>
          Google-ээр бүртгүүлэх
        </button>
        <div style={{ textAlign: 'center', fontSize: 13, color: 'var(--text-secondary)' }}>
          Бүртгэлтэй юу?{' '}
          <span onClick={() => go('login')} style={{
            color: 'var(--accent-start)', fontWeight: 700, cursor: 'pointer',
          }}>Нэвтрэх</span>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 08 — PROFILE SETUP
// ────────────────────────────────────────────────────────────
function ScreenSetup({ go, state }) {
  const interests = ['Bar', 'Lounge', 'Live music', 'DJ', 'Cocktail', 'Karaoke', 'Pub', 'Hookah'];
  const [picked, setPicked] = React.useState(['Bar', 'Live music', 'Cocktail']);

  const toggle = (x) => setPicked(p => p.includes(x) ? p.filter(y => y !== x) : [...p, x]);

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
        <PageTitle>Өөрийгөө<br/><span className="ns-grad-text" style={{ fontStyle: 'italic' }}>танилцуул</span></PageTitle>
        <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text-secondary)' }}>
          Зураг, нэр, сонирхлоо нэм
        </p>

        {/* avatar uploader */}
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
            <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>Хэрэглэгчийн нэр</label>
            <input className="ns-input" type="text" placeholder="@bold_ub"/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 6, display: 'block' }}>Танилцуулга</label>
            <textarea className="ns-input" rows={3} placeholder="Шөнийн соёлд дуртай. Live music, jazz, vinyl."
              style={{ height: 'auto', paddingTop: 14, paddingBottom: 14, resize: 'none' }}/>
          </div>
          <div>
            <label className="ns-mono" style={{ marginBottom: 10, display: 'block' }}>Сонирхол</label>
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
        <button className="ns-btn-primary" style={{ width: '100%' }} onClick={() => go('feed')}>
          Үргэлжлүүлэх
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenAuthLanding, ScreenLogin, ScreenRegister, ScreenSetup });
