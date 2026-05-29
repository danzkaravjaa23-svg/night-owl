/* screens-social.jsx
   16 Notifications · 17 Profile · 18 Settings · 19 Business Dashboard
*/

// ────────────────────────────────────────────────────────────
// 16 — NOTIFICATIONS
// ────────────────────────────────────────────────────────────
function ScreenNotifications({ go, state }) {
  const today = [
    { u: '@nara.ulaan',  k: 'like',   txt: 'таны зургийг лайклалаа',   t: '5м',   thumb: true },
    { u: '@bayar.dj',    k: 'follow', txt: 'таныг дагалаа',                 t: '32м'             },
    { u: '@solongo',     k: 'comment', txt: 'таны зургийг коммент хийлээ', t: '1ц',  thumb: true },
    { u: '@odgerel',     k: 'mention', txt: 'таныг таглалаа',                 t: '2ц',  thumb: true },
    { u: '@enkh_94',     k: 'follow', txt: 'таныг дагалаа',                 t: '3ц'             },
  ];
  const week = [
    { u: '@erden_dj',    k: 'like',   txt: 'таны зургийг лайклалаа',   t: '2 өд', thumb: true },
    { u: '@mass_club',   k: 'venue',  txt: 'таныг таглаж постолсон',       t: '3 өд', thumb: true },
    { u: '@vertigo',     k: 'venue',  txt: 'эвент эхэллээ · Jazz Night',     t: '5 өд' },
  ];

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <NotifHeader/>
        <div className="ns-screen-scroll" style={{ padding: '8px 20px' }}>
          {[1,2,3,4,5].map(i => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 0' }}>
              <Skel w={42} h={42} r={21}/>
              <div style={{ flex: 1 }}>
                <Skel w="80%" h={12}/>
                <div style={{ height: 6 }}/>
                <Skel w="40%" h={10}/>
              </div>
              <Skel w={42} h={42} r={8}/>
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (state === 'empty') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <NotifHeader/>
        <EmptyState
          icon="bell"
          title="Мэдэгдэл алга"
          body="Шинэ лайк, дагагч, коммент энд харагдана. Хэн нэгнийг дагаад эхлээрэй."
        />
      </div>
    );
  }

  if (state === 'error') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <NotifHeader/>
        <ErrorState onRetry={() => go('notifications')}/>
      </div>
    );
  }

  const Row = ({ n, unread }) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 18px 12px 16px',
      position: 'relative',
    }}>
      {unread && (
        <span style={{
          position: 'absolute', left: 0, top: 8, bottom: 8, width: 3,
          borderRadius: 3, background: 'var(--accent-grad)',
        }}/>
      )}
      <Avatar size={42} initial={n.u[1].toUpperCase()} ring={n.k === 'follow'}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13, lineHeight: 1.4 }}>
          <span style={{ fontWeight: 700 }}>{n.u}</span>
          <span style={{ color: 'var(--text-secondary)' }}> {n.txt}</span>
        </div>
        <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>{n.t}</div>
      </div>
      {n.k === 'follow' ? (
        <button style={{
          padding: '7px 14px', borderRadius: 9999,
          background: 'var(--accent-grad)', border: 0,
          color: '#1B0210', fontSize: 12, fontWeight: 700,
          letterSpacing: '0.03em', cursor: 'pointer',
        }}>Дагах</button>
      ) : n.thumb ? (
        <div onClick={() => go('post-detail')} style={{
          width: 42, height: 42, borderRadius: 8, overflow: 'hidden', cursor: 'pointer',
        }}>
          <Placeholder label="" style={{ aspectRatio: '1', borderRadius: 8 }}/>
        </div>
      ) : null}
    </div>
  );

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <NotifHeader/>

      <div className="ns-screen-scroll" style={{ paddingBottom: 12 }}>
        <SectionLabel>Өнөөдөр</SectionLabel>
        {today.map((n, i) => <Row key={i} n={n} unread={i < 2}/>)}
        <SectionLabel>Энэ долоо хоног</SectionLabel>
        {week.map((n, i) => <Row key={i} n={n}/>)}

        <div style={{ padding: '24px 20px', textAlign: 'center' }}>
          <button className="ns-btn-ghost">Бүгдийг харах</button>
        </div>
      </div>
    </div>
  );
}

function NotifHeader() {
  return (
    <div style={{
      flexShrink: 0,
      padding: '6px 20px 12px',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
    }}>
      <PageTitle small>Мэдэгдэл</PageTitle>
      <ScreenMeta index={16} total={19} label="Notif"/>
    </div>
  );
}

function SectionLabel({ children }) {
  return (
    <div style={{
      padding: '14px 20px 6px',
      fontFamily: 'var(--ff-mono)', fontSize: 10,
      letterSpacing: '0.18em', textTransform: 'uppercase',
      color: 'var(--text-tertiary)',
    }}>{children}</div>
  );
}

// ────────────────────────────────────────────────────────────
// 17 — PROFILE (own)
// ────────────────────────────────────────────────────────────
function ScreenProfile({ go, state }) {
  const [tab, setTab] = React.useState('posts');

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <ProfileTopBar go={go} onSettings={() => go('settings')}/>
        <div className="ns-screen-scroll" style={{ padding: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <Skel w={84} h={84} r={42}/>
            <div style={{ flex: 1, display: 'flex', gap: 18 }}>
              {[0,1,2].map(i => <div key={i}><Skel w={36} h={18}/><div style={{ height: 6 }}/><Skel w={50} h={10}/></div>)}
            </div>
          </div>
          <div style={{ height: 14 }}/>
          <Skel w="55%" h={16}/>
          <div style={{ height: 8 }}/>
          <Skel w="75%" h={11}/>
        </div>
      </div>
    );
  }

  const isEmpty = state === 'empty';

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <ProfileTopBar go={go} onSettings={() => go('settings')}/>

      <div className="ns-screen-scroll">
        <div style={{ padding: '12px 20px 0' }}>
          {/* head */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
            <Avatar size={88} initial="М" ring slotId="me-avatar"/>
            <div style={{ flex: 1, display: 'flex', gap: 22 }}>
              {[
                ['Пост', isEmpty ? '0' : '47'],
                ['Дагагч', isEmpty ? '0' : '1.2K'],
                ['Дагаж буй', isEmpty ? '0' : '184'],
              ].map(([l, v]) => (
                <div key={l} style={{ textAlign: 'center' }}>
                  <div style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 500 }}>{v}</div>
                  <div className="ns-mono" style={{ marginTop: 2 }}>{l}</div>
                </div>
              ))}
            </div>
          </div>

          <h2 style={{
            margin: '14px 0 0', fontFamily: 'var(--ff-display)',
            fontSize: 22, fontWeight: 500, letterSpacing: '-0.01em',
          }}>Munkh Erdene</h2>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>
            @munkh_ub · Шөнийн соёлд дуртай
          </div>
          <p style={{ margin: '8px 0 0', fontSize: 13, lineHeight: 1.5, color: 'var(--text-secondary)' }}>
            Live music · vinyl · cocktail. UB.<br/>
            Шинэ газар нээх дуртай.
          </p>

          <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 40, fontSize: 13 }}>
              <Icon name="edit" size={14}/>
              Профайл засах
            </button>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 40, fontSize: 13 }}>
              <Icon name="send" size={14}/>
              Хуваалцах
            </button>
            <button className="ns-btn-secondary" style={{ width: 40, height: 40, padding: 0 }}>
              <Icon name="plus" size={18}/>
            </button>
          </div>

          {/* highlights */}
          {!isEmpty && (
            <div style={{ display: 'flex', gap: 14, marginTop: 22, overflowX: 'auto', paddingBottom: 6 }}>
              {['Vertigo', 'Mass NYE', '2024', 'Travel', 'Vinyl'].map(h => (
                <div key={h} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
                  <Avatar size={64} initial={h[0]}/>
                  <span style={{ fontSize: 10, color: 'var(--text-secondary)' }}>{h}</span>
                </div>
              ))}
            </div>
          )}

          {/* tabs */}
          <div style={{
            display: 'flex', marginTop: isEmpty ? 24 : 12,
            borderBottom: '1px solid var(--hairline)',
          }}>
            {[['posts', 'feed'], ['saved', 'bookmark'], ['tagged', 'user']].map(([k, icon]) => (
              <button key={k} onClick={() => setTab(k)} style={{
                flex: 1, padding: '14px 0', background: 'transparent', cursor: 'pointer',
                border: 0, borderBottom: tab === k ? '2px solid var(--accent-start)' : '2px solid transparent',
                color: tab === k ? 'var(--text-primary)' : 'var(--text-tertiary)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}><Icon name={icon} size={18}/></button>
            ))}
          </div>
        </div>

        {isEmpty ? (
          <EmptyState
            icon="sparkles"
            title="Эхний зургаа оруулаарай 🦉"
            body="Дуртай газраа, дуртай шөнөө хуваалцаад тэжээлээ эхлүүлээрэй."
            action={
              <button className="ns-btn-primary" onClick={() => go('post')}>
                <Icon name="plus" size={18} stroke="#1B0210" strokeWidth={2.2}/>
                Зураг оруулах
              </button>
            }
          />
        ) : (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 2, marginTop: 2 }}>
            {Array.from({ length: 12 }).map((_, i) => (
              <Placeholder key={i} label={`#${i+1}`} style={{ aspectRatio: '1' }}/>
            ))}
          </div>
        )}
        <div style={{ height: 28 }}/>
      </div>
    </div>
  );
}

function ProfileTopBar({ onSettings, go }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 20px 8px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 600 }}>
          @munkh_ub
        </span>
        <Icon name="chevron-down" size={16} stroke="var(--text-secondary)"/>
      </div>
      <div style={{ display: 'flex', gap: 4 }}>
        <button style={iconBtn} onClick={() => go('post')}>
          <Icon name="plus" size={22}/>
        </button>
        <button style={iconBtn} onClick={onSettings}>
          <Icon name="settings" size={22}/>
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 18 — SETTINGS
// ────────────────────────────────────────────────────────────
function ScreenSettings({ go, state }) {
  const sections = [
    { title: 'Акаунт', items: [
      { icon: 'user',   l: 'Профайл засах' },
      { icon: 'lock',   l: 'Нууц үг солих' },
      { icon: 'globe',  l: 'Хэл',           v: 'Монгол' },
      { icon: 'sparkles', l: 'Харагдац',    themeToggle: true },
    ]},
    { title: 'Мэдэгдэл', items: [
      { icon: 'heart',  l: 'Лайк ба коммент',  toggle: true, on: true },
      { icon: 'user',   l: 'Шинэ дагагч',       toggle: true, on: true },
      { icon: 'ticket', l: 'Эвент ба урилга',  toggle: true, on: false },
    ]},
    { title: 'Нууцлал', items: [
      { icon: 'shield', l: 'Хувийн акаунт',     toggle: true, on: false },
      { icon: 'eye',    l: 'Идэвх харагдах эсэх', toggle: true, on: true },
    ]},
    { title: 'Төлбөр', items: [
      { icon: 'wallet', l: 'QPay түүх', v: '5 гүйлгээ' },
    ]},
    { title: 'Бусад', items: [
      { icon: 'help',   l: 'Тусламж' },
      { icon: 'logout', l: 'Гарах', danger: true },
    ]},
  ];

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <div style={{
        flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 12px 12px',
      }}>
        <button style={iconBtn} onClick={() => go('me')}>
          <Icon name="arrow-left" size={22}/>
        </button>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>Тохиргоо</div>
        <div style={{ width: 40 }}/>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '0 20px 28px' }}>
        {sections.map(s => (
          <div key={s.title} style={{ marginTop: 18 }}>
            <div className="ns-mono" style={{ marginBottom: 8, paddingLeft: 4 }}>{s.title}</div>
            <div className="ns-glass" style={{ overflow: 'hidden' }}>
              {s.items.map((it, i, arr) => (
                <div key={it.l} style={{
                  display: 'flex', alignItems: 'center', gap: 14,
                  padding: '14px 16px',
                  borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
                }}>
                  <span style={{
                    width: 32, height: 32, borderRadius: 10,
                    background: it.danger ? 'rgba(255,84,112,0.12)' : 'rgba(255,77,141,0.08)',
                    color: it.danger ? 'var(--error)' : 'var(--accent-start)',
                    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                    <Icon name={it.icon} size={16}/>
                  </span>
                  <span style={{
                    flex: 1, fontSize: 14,
                    color: it.danger ? 'var(--error)' : 'var(--text-primary)',
                    fontWeight: it.danger ? 600 : 400,
                  }}>{it.l}</span>
                  {it.themeToggle ? <ThemeSegment/> :
                    it.toggle ? <SettingsToggle on={it.on}/> :
                    <>
                      {it.v && <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{it.v}</span>}
                      {!it.danger && <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>}
                    </>
                  }
                </div>
              ))}
            </div>
          </div>
        ))}
        <div style={{ textAlign: 'center', marginTop: 24, fontSize: 11,
              color: 'var(--text-tertiary)', fontFamily: 'var(--ff-mono)', letterSpacing: '0.1em' }}>
          v0.4.2 · NIGHT OWL · UB
        </div>
      </div>
    </div>
  );
}

function SettingsToggle({ on: initialOn = false }) {
  const [on, setOn] = React.useState(initialOn);
  return (
    <button onClick={() => setOn(!on)} style={{
      width: 44, height: 26, borderRadius: 14,
      background: on ? 'var(--accent-grad)' : 'rgba(255,255,255,0.1)',
      border: 0, cursor: 'pointer', padding: 2,
      display: 'flex', alignItems: 'center',
      justifyContent: on ? 'flex-end' : 'flex-start',
      transition: 'background .2s, justify-content .2s',
    }}>
      <span style={{
        width: 22, height: 22, borderRadius: '50%',
        background: '#fff',
        boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
        transition: 'transform .2s',
      }}/>
    </button>
  );
}

// Dark / Light segmented control — talks to app.jsx via window.__setTheme
function ThemeSegment() {
  const [theme, setLocalTheme] = React.useState(
    () => document.documentElement.getAttribute('data-theme') || 'dark'
  );
  React.useEffect(() => {
    const obs = new MutationObserver(() => {
      setLocalTheme(document.documentElement.getAttribute('data-theme') || 'dark');
    });
    obs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return () => obs.disconnect();
  }, []);
  const set = (v) => {
    if (typeof window.__setTheme === 'function') window.__setTheme(v);
    else document.documentElement.setAttribute('data-theme', v);
  };
  return (
    <div style={{
      display: 'inline-flex', padding: 3,
      borderRadius: 9999,
      background: 'rgba(255,255,255,0.06)',
      border: '1px solid var(--hairline)',
    }}>
      {[
        { k: 'dark',  icon: 'sparkles' },
        { k: 'light', icon: 'sparkles' },
      ].map(o => {
        const on = theme === o.k;
        return (
          <button key={o.k} onClick={() => set(o.k)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '4px 10px', borderRadius: 9999,
            background: on ? 'var(--accent-grad)' : 'transparent',
            color: on ? '#1B0210' : 'var(--text-secondary)',
            border: 0, cursor: 'pointer',
            fontSize: 11, fontWeight: 700, letterSpacing: '0.06em',
            textTransform: 'uppercase',
          }}>
            {o.k === 'dark' ? '☾' : '☀'} {o.k === 'dark' ? 'Шөнө' : 'Өдөр'}
          </button>
        );
      })}
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 19 — BUSINESS DASHBOARD
// ────────────────────────────────────────────────────────────
function ScreenBusiness({ go, state }) {
  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <div style={{
        flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 12px 12px',
      }}>
        <button style={iconBtn} onClick={() => go('me')}>
          <Icon name="arrow-left" size={22}/>
        </button>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>Бизнес</div>
        <button style={iconBtn}><Icon name="settings" size={22}/></button>
      </div>

      <div className="ns-screen-scroll">
        {/* cover */}
        <div style={{ position: 'relative', height: 160 }}>
          <Placeholder label="Vertigo · cover" style={{ aspectRatio: 'auto', height: '100%' }}/>
          <div style={{ position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, transparent 40%, rgba(11,1,24,0.9))' }}/>
          <div style={{ position: 'absolute', left: 20, bottom: 16, display: 'flex', alignItems: 'center', gap: 12 }}>
            <LogoSlot id="biz-logo" label="LOGO" width={48} height={48} radius={12}/>
            <div>
              <div className="ns-mono" style={{ color: '#FFB347' }}>BUSINESS · LOUNGE</div>
              <div style={{ fontFamily: 'var(--ff-display)', fontSize: 22, fontWeight: 500, marginTop: 2 }}>
                Vertigo Rooftop
              </div>
            </div>
          </div>
        </div>

        <div style={{ padding: '18px 20px 0' }}>
          {/* stats */}
          <div className="ns-mono" style={{ marginBottom: 10 }}>СҮҮЛИЙН 7 ХОНОГ</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
            {[
              { l: 'Үзэлт',    v: '12.4K', d: '+18%', up: true },
              { l: 'Дагагч',   v: '+184',   d: '+8%',  up: true },
              { l: 'Үнэлгээ',  v: '4.8',    d: '+0.1', up: true },
            ].map(s => (
              <div key={s.l} className="ns-glass" style={{ padding: 12 }}>
                <div className="ns-mono">{s.l}</div>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 22, fontWeight: 500, marginTop: 6 }}>
                  {s.v}
                </div>
                <div style={{
                  fontSize: 11, fontWeight: 600, marginTop: 4,
                  color: s.up ? 'var(--success)' : 'var(--error)',
                }}>
                  {s.up ? '↗' : '↘'} {s.d}
                </div>
              </div>
            ))}
          </div>

          {/* chart */}
          <div className="ns-glass" style={{ marginTop: 12, padding: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <div>
                <div className="ns-mono">ҮЗЭЛТ · 7 ХОНОГ</div>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 26, fontWeight: 500, marginTop: 4 }}>
                  12,408
                </div>
              </div>
              <span className="ns-chip is-on" style={{ height: 26, fontSize: 11 }}>7Д</span>
            </div>
            <ChartMini/>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontFamily: 'var(--ff-mono)', fontSize: 9, color: 'var(--text-tertiary)',
              marginTop: 6, letterSpacing: '0.1em',
            }}>
              {['Дав', 'Мяг', 'Лха', 'Пүр', 'Баа', 'Бям', 'Ням'].map(d => <span key={d}>{d}</span>)}
            </div>
          </div>

          {/* actions */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 18 }}>
            <button className="ns-btn-primary" style={{ width: '100%' }}>
              <Icon name="ticket" size={18} stroke="#1B0210" strokeWidth={2}/>
              Эвент нэмэх
            </button>
            <button className="ns-btn-secondary" style={{ width: '100%' }}>
              <Icon name="image" size={18}/>
              Контент оруулах
            </button>
          </div>

          {/* manage */}
          <div className="ns-mono" style={{ marginTop: 24, marginBottom: 10 }}>УДИРДЛАГА</div>
          <div className="ns-glass" style={{ overflow: 'hidden' }}>
            {[
              { i: 'pin',    l: 'Хаяг ба байршил', v: 'Сүхбаатарын талбай 5' },
              { i: 'globe',  l: 'Ажиллах цаг',      v: 'Пүр-Бямба 18-02' },
              { i: 'image',  l: 'Зургийн галерей',  v: '24 зураг' },
              { i: 'music',  l: 'Тоглолтын төрөл',  v: 'Live jazz · DJ' },
              { i: 'phone',  l: 'Холбоо барих',     v: '+976 7700 1234' },
            ].map((r, i, arr) => (
              <div key={r.l} style={{
                display: 'flex', alignItems: 'center', gap: 14,
                padding: '14px 16px',
                borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
              }}>
                <span style={{
                  width: 32, height: 32, borderRadius: 10,
                  background: 'rgba(255,77,141,0.08)', color: 'var(--accent-start)',
                  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                }}><Icon name={r.i} size={16}/></span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 600 }}>{r.l}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
                        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {r.v}
                  </div>
                </div>
                <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
              </div>
            ))}
          </div>

          {/* upcoming events */}
          <div className="ns-mono" style={{ marginTop: 24, marginBottom: 10 }}>ИРЭХ ЭВЕНТҮҮД</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[
              { d: '31', m: 'тав', t: 'Jazz night · trio',  s: 'Идэвхтэй' },
              { d: '07', m: 'зур', t: 'Cocktail tasting',   s: 'Идэвхтэй' },
              { d: '14', m: 'зур', t: 'Vinyl Sunday',       s: 'Ноорог' },
            ].map((e, i) => (
              <div key={i} className="ns-glass" style={{ padding: 14, display: 'flex', gap: 12, alignItems: 'center' }}>
                <div style={{
                  width: 52, textAlign: 'center', padding: '8px 0',
                  borderRadius: 12, background: 'var(--bg-surface)',
                }}>
                  <div style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 500 }}>{e.d}</div>
                  <div className="ns-mono">{e.m}</div>
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 700, fontSize: 13 }}>{e.t}</div>
                  <div style={{ fontSize: 11, color: e.s === 'Ноорог' ? 'var(--warning)' : 'var(--success)',
                        marginTop: 4, fontWeight: 600 }}>
                    {e.s === 'Ноорог' ? '◌' : '●'} {e.s}
                  </div>
                </div>
                <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
              </div>
            ))}
          </div>

          <div style={{ height: 28 }}/>
        </div>
      </div>
    </div>
  );
}

function ChartMini() {
  const pts = [42, 58, 51, 78, 62, 95, 82];
  const max = 100;
  const w = 280, h = 88;
  const path = pts.map((p, i) => {
    const x = (i / (pts.length - 1)) * w;
    const y = h - (p / max) * h;
    return `${i === 0 ? 'M' : 'L'} ${x} ${y}`;
  }).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h+8}`} style={{ width: '100%', height: 100, marginTop: 12, display: 'block' }}>
      <defs>
        <linearGradient id="chart-g" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FF4D8D" stopOpacity="0.4"/>
          <stop offset="1" stopColor="#FF4D8D" stopOpacity="0"/>
        </linearGradient>
        <linearGradient id="chart-line" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#FF4D8D"/>
          <stop offset="1" stopColor="#FFB347"/>
        </linearGradient>
      </defs>
      <path d={`${path} L ${w} ${h} L 0 ${h} Z`} fill="url(#chart-g)"/>
      <path d={path} stroke="url(#chart-line)" strokeWidth="2" fill="none"
            strokeLinecap="round" strokeLinejoin="round"/>
      {pts.map((p, i) => {
        const x = (i / (pts.length - 1)) * w;
        const y = h - (p / max) * h;
        const last = i === pts.length - 1;
        return (
          <g key={i}>
            {last && <circle cx={x} cy={y} r={6} fill="#FF7B5C" opacity="0.25"/>}
            <circle cx={x} cy={y} r={last ? 3.5 : 2}
                    fill={last ? '#FFB347' : 'rgba(255,255,255,0.6)'}/>
          </g>
        );
      })}
    </svg>
  );
}

Object.assign(window, { ScreenNotifications, ScreenProfile, ScreenSettings, ScreenBusiness });
