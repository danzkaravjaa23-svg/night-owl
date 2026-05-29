/* screens-social.jsx
   16 Notifications · 17 Profile · 18 Settings · 19 Business Dashboard
*/

// ────────────────────────────────────────────────────────────
// 16 — NOTIFICATIONS
// ────────────────────────────────────────────────────────────
function ScreenNotifications({ go, state, language }) {
  const today = [
    { u: '@nara.ulaan',  k: 'like',    txt: 'таны зургийг лайклалаа',    t: '5м',  thumb: true },
    { u: '@bayar.dj',    k: 'follow',  txt: 'таныг дагалаа',              t: '32м'              },
    { u: '@solongo',     k: 'comment', txt: 'таны зургийг коммент хийлээ', t: '1ц', thumb: true },
    { u: '@odgerel',     k: 'mention', txt: 'таныг таглалаа',              t: '2ц', thumb: true },
    { u: '@enkh_94',     k: 'follow',  txt: 'таныг дагалаа',              t: '3ц'              },
  ];
  const week = [
    { u: '@erden_dj',  k: 'like',  txt: 'таны зургийг лайклалаа',   t: '2 өд', thumb: true },
    { u: '@mass_club', k: 'venue', txt: 'таныг таглаж постолсон',    t: '3 өд', thumb: true },
    { u: '@vertigo',   k: 'venue', txt: 'эвент эхэллээ · Jazz Night', t: '5 өд' },
  ];

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <NotifHeader language={language}/>
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
        <NotifHeader language={language}/>
        <EmptyState
          icon="bell"
          title={tr('notif.empty.title', language)}
          body={tr('notif.empty.body', language)}
        />
      </div>
    );
  }

  if (state === 'error') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <NotifHeader language={language}/>
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
        }}>{tr('lbl.follow', language)}</button>
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
      <NotifHeader language={language}/>

      <div className="ns-screen-scroll" style={{ paddingBottom: 12 }}>
        <SectionLabel>{tr('lbl.today2', language)}</SectionLabel>
        {today.map((n, i) => <Row key={i} n={n} unread={i < 2}/>)}
        <SectionLabel>{tr('lbl.thisWeek', language)}</SectionLabel>
        {week.map((n, i) => <Row key={i} n={n}/>)}

        <div style={{ padding: '24px 20px', textAlign: 'center' }}>
          <button className="ns-btn-ghost">{tr('btn.viewAll', language)}</button>
        </div>
      </div>
    </div>
  );
}

function NotifHeader({ language }) {
  return (
    <div style={{
      flexShrink: 0,
      padding: '6px 20px 12px',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
    }}>
      <PageTitle small>{tr('lbl.notifications', language)}</PageTitle>
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
function ScreenProfile({ go, state, language, profile = {} }) {
  const [tab, setTab] = React.useState('posts');
  const displayName = profile.displayName || 'Munkh Erdene';
  const username    = profile.username    || 'munkh_ub';
  const bio         = profile.bio         || 'Live music · vinyl · cocktail. UB.\nШинэ газар нээх дуртай.';
  const initial     = (displayName[0] || 'М').toUpperCase();

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <ProfileTopBar go={go} username={username} onSettings={() => go('settings')}/>
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
      <ProfileTopBar go={go} username={username} onSettings={() => go('settings')}/>

      <div className="ns-screen-scroll">
        <div style={{ padding: '12px 20px 0' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
            <Avatar size={88} initial={initial} ring slotId="me-avatar"/>
            <div style={{ flex: 1, display: 'flex', gap: 22 }}>
              {[
                [tr('lbl.posts', language),        isEmpty ? '0' : '47'],
                [tr('lbl.followers', language),    isEmpty ? '0' : '1.2K'],
                [tr('lbl.followingLbl', language), isEmpty ? '0' : '184'],
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
          }}>{displayName}</h2>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>
            @{username}
          </div>
          {bio ? (
            <p style={{ margin: '8px 0 0', fontSize: 13, lineHeight: 1.5, color: 'var(--text-secondary)',
              whiteSpace: 'pre-line' }}>
              {bio}
            </p>
          ) : null}

          <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 40, fontSize: 13 }}>
              <Icon name="edit" size={14}/>
              {tr('btn.editProfile', language)}
            </button>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 40, fontSize: 13 }}>
              <Icon name="send" size={14}/>
              {tr('btn.shareProfile', language)}
            </button>
            <button className="ns-btn-secondary" style={{ width: 40, height: 40, padding: 0 }}>
              <Icon name="plus" size={18}/>
            </button>
          </div>

          {/* Affiliate button — gold */}
          <button
            onClick={() => go('affiliate-unlock')}
            style={{
              marginTop: 10, width: '100%', height: 42,
              borderRadius: 12,
              background: 'linear-gradient(135deg, #F5C518 0%, #FFB347 60%, #FF8C00 100%)',
              border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
              color: '#1B0210',
              fontFamily: 'var(--ff-body)', fontWeight: 800, fontSize: 13,
              letterSpacing: '0.06em', textTransform: 'uppercase',
              boxShadow: '0 4px 18px rgba(245,197,24,0.38), 0 0 0 1px rgba(245,197,24,0.2)',
            }}>
            <Icon name="sparkles" size={15} stroke="#1B0210" strokeWidth={2.2} filled/>
            {language === 'mn' ? 'Партнер хөтөлбөр' : 'Affiliate'}
          </button>

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
            title={tr('profile.empty.title', language)}
            body={tr('profile.empty.body', language)}
            action={
              <button className="ns-btn-primary" onClick={() => go('post')}>
                <Icon name="plus" size={18} stroke="#1B0210" strokeWidth={2.2}/>
                {tr('btn.uploadPhoto', language)}
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

function ProfileTopBar({ onSettings, go, username = 'munkh_ub' }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 20px 8px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 600 }}>
          @{username}
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
function ScreenSettings({ go, state, language }) {
  const sections = [
    { titleKey: 'sect.account', items: [
      { icon: 'user',     lKey: 'set.editProfile',    dest: 'setup' },
      { icon: 'lock',     lKey: 'set.changePassword', dest: 'change-password' },
      { icon: 'globe',    lKey: 'set.language',       dest: 'lang-select',
        v: language === 'mn' ? 'Монгол' : 'English' },
      { icon: 'sparkles', lKey: 'set.appearance',     themeToggle: true },
    ]},
    { titleKey: 'sect.notifications', items: [
      { icon: 'heart',  lKey: 'set.likesComments', toggle: true, on: true },
      { icon: 'user',   lKey: 'set.newFollowers',  toggle: true, on: true },
      { icon: 'ticket', lKey: 'set.eventsInvites', toggle: true, on: false },
    ]},
    { titleKey: 'sect.privacy', items: [
      { icon: 'shield', lKey: 'set.privateAccount',  toggle: true, on: false },
      { icon: 'eye',    lKey: 'set.activityStatus',  toggle: true, on: true },
    ]},
    { titleKey: 'sect.payments', items: [
      { icon: 'wallet', lKey: 'set.qpayHistory',
        v: language === 'mn' ? '5 гүйлгээ' : '5 transactions' },
    ]},
    { titleKey: 'sect.other', items: [
      { icon: 'help',   lKey: 'set.help' },
      { icon: 'logout', lKey: 'set.signOut', danger: true, dest: 'auth-landing' },
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
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>
          {tr('lbl.settings', language)}
        </div>
        <div style={{ width: 40 }}/>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '0 20px 28px' }}>
        {sections.map(s => (
          <div key={s.titleKey} style={{ marginTop: 18 }}>
            <div className="ns-mono" style={{ marginBottom: 8, paddingLeft: 4 }}>
              {tr(s.titleKey, language)}
            </div>
            <div className="ns-glass" style={{ overflow: 'hidden' }}>
              {s.items.map((it, i, arr) => {
                const isNav = !it.themeToggle && !it.toggle && it.dest;
                return (
                  <div key={it.lKey}
                    onClick={isNav ? () => go(it.dest) : undefined}
                    style={{
                      display: 'flex', alignItems: 'center', gap: 14,
                      padding: '14px 16px',
                      borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
                      cursor: isNav ? 'pointer' : 'default',
                      transition: isNav ? 'background .15s' : undefined,
                    }}
                    onMouseEnter={isNav ? (e) => e.currentTarget.style.background = 'rgba(255,255,255,0.03)' : undefined}
                    onMouseLeave={isNav ? (e) => e.currentTarget.style.background = '' : undefined}
                  >
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
                    }}>{tr(it.lKey, language)}</span>
                    {it.themeToggle ? <ThemeSegment language={language}/> :
                      it.toggle ? <SettingsToggle on={it.on}/> :
                      <>
                        {it.v && <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{it.v}</span>}
                        {!it.danger && <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>}
                      </>
                    }
                  </div>
                );
              })}
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

function ThemeSegment({ language }) {
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
        { k: 'dark',  lKey: 'lbl.dark' },
        { k: 'light', lKey: 'lbl.light' },
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
            {o.k === 'dark' ? '☾' : '☀'} {tr(o.lKey, language)}
          </button>
        );
      })}
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 19 — BUSINESS DASHBOARD
// ────────────────────────────────────────────────────────────
function ScreenBusiness({ go, state, language }) {
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
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>
          {tr('lbl.business', language)}
        </div>
        <button style={iconBtn}><Icon name="settings" size={22}/></button>
      </div>

      <div className="ns-screen-scroll">
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
          <div className="ns-mono" style={{ marginBottom: 10 }}>{tr('lbl.last7days', language)}</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
            {[
              { lKey: 'lbl.views',    v: '12.4K', d: '+18%', up: true },
              { lKey: 'lbl.followers', v: '+184',  d: '+8%',  up: true },
              { lKey: 'lbl.rating',   v: '4.8',   d: '+0.1', up: true },
            ].map(s => (
              <div key={s.lKey} className="ns-glass" style={{ padding: 12 }}>
                <div className="ns-mono">{tr(s.lKey, language)}</div>
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

          <div className="ns-glass" style={{ marginTop: 12, padding: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <div>
                <div className="ns-mono">{tr('lbl.viewsChart', language)}</div>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 26, fontWeight: 500, marginTop: 4 }}>
                  12,408
                </div>
              </div>
              <span className="ns-chip is-on" style={{ height: 26, fontSize: 11 }}>7D</span>
            </div>
            <ChartMini/>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontFamily: 'var(--ff-mono)', fontSize: 9, color: 'var(--text-tertiary)',
              marginTop: 6, letterSpacing: '0.1em',
            }}>
              {['day.mon','day.tue','day.wed','day.thu','day.fri','day.sat','day.sun'].map(k => (
                <span key={k}>{tr(k, language)}</span>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 18 }}>
            <button className="ns-btn-primary" style={{ width: '100%' }}>
              <Icon name="ticket" size={18} stroke="#1B0210" strokeWidth={2}/>
              {tr('btn.addEvent', language)}
            </button>
            <button className="ns-btn-secondary" style={{ width: '100%' }}>
              <Icon name="image" size={18}/>
              {tr('btn.uploadContent', language)}
            </button>
          </div>

          <div className="ns-mono" style={{ marginTop: 24, marginBottom: 10 }}>
            {tr('lbl.management', language)}
          </div>
          <div className="ns-glass" style={{ overflow: 'hidden' }}>
            {[
              { i: 'pin',   lKey: 'biz.address', v: 'Сүхбаатарын талбай 5' },
              { i: 'globe', lKey: 'biz.hours',   v: 'Пүр-Бямба 18-02' },
              { i: 'image', lKey: 'biz.gallery', v: language === 'mn' ? '24 зураг' : '24 photos' },
              { i: 'music', lKey: 'biz.music',   v: 'Live jazz · DJ' },
              { i: 'phone', lKey: 'biz.contact', v: '+976 7700 1234' },
            ].map((r, i, arr) => (
              <div key={r.lKey} style={{
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
                  <div style={{ fontSize: 13, fontWeight: 600 }}>{tr(r.lKey, language)}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
                        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {r.v}
                  </div>
                </div>
                <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
              </div>
            ))}
          </div>

          <div className="ns-mono" style={{ marginTop: 24, marginBottom: 10 }}>
            {tr('lbl.upcomingEvents', language)}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[
              { d: '31', mKey: 'month.may', t: 'Jazz night · trio',  sKey: 'evt.active' },
              { d: '07', mKey: 'month.jun', t: 'Cocktail tasting',   sKey: 'evt.active' },
              { d: '14', mKey: 'month.jun', t: 'Vinyl Sunday',       sKey: 'evt.draft'  },
            ].map((e, i) => (
              <div key={i} className="ns-glass" style={{ padding: 14, display: 'flex', gap: 12, alignItems: 'center' }}>
                <div style={{
                  width: 52, textAlign: 'center', padding: '8px 0',
                  borderRadius: 12, background: 'var(--bg-surface)',
                }}>
                  <div style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 500 }}>{e.d}</div>
                  <div className="ns-mono">{tr(e.mKey, language)}</div>
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 700, fontSize: 13 }}>{e.t}</div>
                  <div style={{
                    fontSize: 11, marginTop: 4, fontWeight: 600,
                    color: e.sKey === 'evt.draft' ? 'var(--warning)' : 'var(--success)',
                  }}>
                    {e.sKey === 'evt.draft' ? '◌' : '●'} {tr(e.sKey, language)}
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

// ─── Affiliate stats chart ───
function AffiliateChart({ language }) {
  const [mode, setMode] = React.useState('earnings');
  const GOLD = '#F5C518';

  const earningsData  = [8000, 5000, 0, 15000, 5000, 14000, 15000];
  const referralData  = [2, 1, 0, 3, 1, 3, 4];
  const pts   = mode === 'earnings' ? earningsData : referralData;
  const max   = Math.max(...pts) * 1.25 || 1;
  const W = 300, H = 80;

  const svgPath = pts.map((p, i) => {
    const x = (i / (pts.length - 1)) * W;
    const y = H - (p / max) * H;
    return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
  }).join(' ');

  const total = mode === 'earnings'
    ? `₮${(earningsData.reduce((a, b) => a + b, 0) / 1000).toFixed(0)}K`
    : String(referralData.reduce((a, b) => a + b, 0));

  const dayKeys = ['day.mon','day.tue','day.wed','day.thu','day.fri','day.sat','day.sun'];

  return (
    <div className="ns-glass" style={{ padding: 16, marginBottom: 20 }}>
      {/* header row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 4 }}>
        <div>
          <div className="ns-mono" style={{ fontSize: 9, color: GOLD, letterSpacing: '0.14em' }}>
            {mode === 'earnings'
              ? (language === 'mn' ? 'НИЙТ ОРЛОГО · 7 ХОНОГ' : 'TOTAL EARNINGS · 7 DAYS')
              : (language === 'mn' ? 'БҮРТГЭЛ · 7 ХОНОГ'     : 'REFERRALS · 7 DAYS')}
          </div>
          <div style={{
            fontFamily: 'var(--ff-display)', fontSize: 28, fontWeight: 700, marginTop: 2,
            color: GOLD, filter: 'drop-shadow(0 0 10px rgba(245,197,24,0.45))',
          }}>{total}</div>
        </div>

        {/* mode toggle */}
        <div style={{
          display: 'inline-flex', padding: 2, borderRadius: 9,
          background: 'rgba(255,255,255,0.04)',
          border: '1px solid rgba(245,197,24,0.15)',
        }}>
          {[
            { k: 'earnings',  l: language === 'mn' ? 'Орлого' : 'Earnings' },
            { k: 'referrals', l: language === 'mn' ? 'Бүртгэл' : 'Refs' },
          ].map(o => {
            const on = mode === o.k;
            return (
              <button key={o.k} onClick={() => setMode(o.k)} style={{
                padding: '5px 11px', borderRadius: 7,
                background: on ? 'rgba(245,197,24,0.18)' : 'transparent',
                border: on ? '1px solid rgba(245,197,24,0.32)' : '1px solid transparent',
                color: on ? GOLD : 'var(--text-tertiary)',
                fontSize: 11, fontWeight: 700, cursor: 'pointer',
                fontFamily: 'var(--ff-body)', letterSpacing: '0.02em',
                transition: 'all .15s ease',
              }}>{o.l}</button>
            );
          })}
        </div>
      </div>

      {/* SVG chart */}
      <svg viewBox={`0 0 ${W} ${H + 8}`}
           style={{ width: '100%', height: 90, display: 'block', marginTop: 8 }}>
        <defs>
          <linearGradient id="aff-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0"   stopColor={GOLD} stopOpacity="0.35"/>
            <stop offset="1"   stopColor={GOLD} stopOpacity="0"/>
          </linearGradient>
          <linearGradient id="aff-line" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0"   stopColor="#F5C518"/>
            <stop offset="1"   stopColor="#FF8C00"/>
          </linearGradient>
        </defs>
        <path d={`${svgPath} L ${W} ${H} L 0 ${H} Z`} fill="url(#aff-fill)"/>
        <path d={svgPath} stroke="url(#aff-line)" strokeWidth="2.2" fill="none"
              strokeLinecap="round" strokeLinejoin="round"/>
        {pts.map((p, i) => {
          const x = (i / (pts.length - 1)) * W;
          const y = H - (p / max) * H;
          const isLast = i === pts.length - 1;
          return (
            <g key={i}>
              {isLast && <circle cx={x} cy={y} r={6} fill={GOLD} opacity="0.22"/>}
              <circle cx={x} cy={y} r={isLast ? 3.5 : 2.2}
                      fill={isLast ? GOLD : 'rgba(245,197,24,0.55)'}/>
            </g>
          );
        })}
      </svg>

      {/* day labels */}
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        fontFamily: 'var(--ff-mono)', fontSize: 9,
        color: 'var(--text-tertiary)', marginTop: 4, letterSpacing: '0.1em',
      }}>
        {dayKeys.map(k => <span key={k}>{tr(k, language)}</span>)}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 20 — AFFILIATE PROGRAM
// ────────────────────────────────────────────────────────────
function ScreenAffiliate({ go, language }) {
  const code = 'SUGAR-OWL247';
  const [copied, setCopied] = React.useState(false);
  const [showHow, setShowHow] = React.useState(false);
  const GOLD = '#F5C518';

  const copyCode = () => {
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
    window.__showNotification?.(
      language === 'mn' ? `Код хуулагдлаа: ${code}` : `Code copied: ${code}`,
      'check', 2200
    );
  };

  const shareCode = () => {
    window.__showNotification?.(
      language === 'mn' ? 'Нэгдэлийн код хуваалцагдлаа 🌟' : 'Referral code shared 🌟',
      'send', 2200
    );
  };

  const stats = [
    { label: language === 'mn' ? 'Нийт орлого' : 'Earnings',   value: '₮62K', gold: true },
    { label: language === 'mn' ? 'Бүртгэл'     : 'Referrals',  value: '14' },
    { label: language === 'mn' ? 'Хувирлалт'   : 'Conv. Rate', value: '8%' },
  ];

  const steps = [
    {
      n: '01',
      title: language === 'mn' ? 'Код хуваалц'      : 'Share your code',
      body:  language === 'mn'
        ? 'Найздаа кодоо илгээ эсвэл постдоо нэм'
        : 'Send your code to friends or add it to your posts',
    },
    {
      n: '02',
      title: language === 'mn' ? 'Найз бүртгүүлэх' : 'Friend registers',
      body:  language === 'mn'
        ? 'Найз чинь таны кодыг ашиглан Night Owl-д нэгдэнэ'
        : 'Your friend joins Night Owl using your referral code',
    },
    {
      n: '03',
      title: language === 'mn' ? 'Шагнал авах'      : 'Earn rewards',
      body:  language === 'mn'
        ? 'Бүртгэл тутамд ₮5,000 + paid контентын 10%-ийг авна'
        : 'Get ₮5,000 per signup + 10% on paid content',
    },
  ];

  const commissions = [
    {
      icon: 'user',
      label: language === 'mn' ? 'Шинэ VIP тутамд'           : 'Per new registration',
      value: '₮5,000',
    },
    {
      icon: 'lock',
      label: language === 'mn' ? 'Paid контент худалдан авалтаас' : 'On paid content purchases',
      value: '10%',
    },
    {
      icon: 'ticket',
      label: language === 'mn' ? 'Эвент тасалбар борлуулалтаас'  : 'On event ticket sales',
      value: '5%',
    },
  ];

  const recent = [
    { user: '@nara.ulaan', amount: '₮5,000', time: language === 'mn' ? '2 өдрийн өмнө'  : '2 days ago',  type: 'signup' },
    { user: '@bayar.dj',   amount: '₮5,000', time: language === 'mn' ? '5 өдрийн өмнө'  : '5 days ago',  type: 'signup' },
    { user: '@solongo',    amount: '₮800',   time: language === 'mn' ? '7 өдрийн өмнө'  : '7 days ago',  type: 'content' },
    { user: '@odgerel',    amount: '₮5,000', time: language === 'mn' ? '12 өдрийн өмнө' : '12 days ago', type: 'signup' },
  ];

  return (
    <div className="ns-screen">
      <PhoneStatus/>

      {/* header */}
      <div style={{
        flexShrink: 0, display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '6px 12px 12px',
      }}>
        <button style={iconBtn} onClick={() => go('me')}>
          <Icon name="arrow-left" size={22}/>
        </button>
        <div style={{
          fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500,
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{ color: GOLD, filter: 'drop-shadow(0 0 6px rgba(245,197,24,0.6))' }}>
            <Icon name="sparkles" size={18} stroke={GOLD} strokeWidth={1.8} filled/>
          </span>
          {language === 'mn' ? 'Партнер хөтөлбөр' : 'Affiliate Program'}
        </div>
        <div style={{ width: 40 }}/>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '0 20px 36px' }}>

        {/* ── CODE CARD ── */}
        <div style={{
          borderRadius: 22,
          background: 'linear-gradient(135deg, rgba(245,197,24,0.14) 0%, rgba(255,140,0,0.10) 100%)',
          border: '1px solid rgba(245,197,24,0.28)',
          padding: '20px 20px 18px',
          marginBottom: 18,
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', top: -50, right: -50,
            width: 180, height: 180, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(245,197,24,0.28), transparent 65%)',
            filter: 'blur(22px)', pointerEvents: 'none',
          }}/>

          <div className="ns-mono" style={{ color: GOLD, marginBottom: 10, letterSpacing: '0.16em' }}>
            {language === 'mn' ? 'ТАНЫ НЭГДЭЛИЙН КОД' : 'YOUR REFERRAL CODE'}
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
            <div style={{
              flex: 1,
              fontFamily: 'JetBrains Mono, monospace', fontSize: 34, fontWeight: 800,
              letterSpacing: '0.14em', color: '#fff',
              filter: 'drop-shadow(0 0 12px rgba(245,197,24,0.35))',
            }}>{code}</div>
            <button onClick={copyCode} style={{
              height: 42, padding: '0 16px', borderRadius: 10,
              background: copied ? 'rgba(61,214,140,0.18)' : 'rgba(245,197,24,0.15)',
              border: `1px solid ${copied ? 'rgba(61,214,140,0.4)' : 'rgba(245,197,24,0.35)'}`,
              color: copied ? 'var(--success)' : GOLD,
              fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 12,
              letterSpacing: '0.06em', textTransform: 'uppercase', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 5,
              transition: 'all .2s ease', flexShrink: 0,
            }}>
              <Icon name={copied ? 'check' : 'qr'} size={15} stroke="currentColor" strokeWidth={1.8}/>
              {copied
                ? (language === 'mn' ? 'Хуулсан!' : 'Copied!')
                : (language === 'mn' ? 'Хуулах'   : 'Copy')}
            </button>
          </div>

          <button onClick={shareCode} style={{
            width: '100%', height: 42, borderRadius: 12,
            background: 'linear-gradient(135deg, #F5C518 0%, #FFB347 60%, #FF8C00 100%)',
            border: 'none', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            color: '#1B0210', fontFamily: 'var(--ff-body)', fontWeight: 800, fontSize: 13,
            letterSpacing: '0.06em', textTransform: 'uppercase',
            boxShadow: '0 6px 20px rgba(245,197,24,0.35)',
          }}>
            <Icon name="send" size={15} stroke="#1B0210" strokeWidth={2.2}/>
            {language === 'mn' ? 'Код хуваалцах' : 'Share Code'}
          </button>
        </div>

        {/* ── STATS ── */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10, marginBottom: 18 }}>
          {stats.map((s, i) => (
            <div key={i} className="ns-glass" style={{ padding: '14px 10px', textAlign: 'center' }}>
              <div style={{
                fontFamily: 'var(--ff-display)', fontSize: i === 0 ? 17 : 22, fontWeight: 700,
                color: s.gold ? GOLD : 'var(--text-primary)', letterSpacing: '-0.01em',
                filter: s.gold ? 'drop-shadow(0 0 8px rgba(245,197,24,0.5))' : 'none',
              }}>{s.value}</div>
              <div className="ns-mono" style={{ marginTop: 5, fontSize: 9 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* ── CHART ── */}
        <AffiliateChart language={language}/>

        {/* ── HOW IT WORKS — compact collapsible button ── */}
        <button onClick={() => setShowHow(v => !v)} style={{
          width: '100%', marginBottom: showHow ? 0 : 20,
          display: 'flex', alignItems: 'center', gap: 12,
          padding: '13px 16px', borderRadius: 14,
          background: showHow ? 'rgba(245,197,24,0.10)' : 'rgba(245,197,24,0.06)',
          border: `1px solid rgba(245,197,24,${showHow ? '0.28' : '0.16'})`,
          cursor: 'pointer', textAlign: 'left', color: 'var(--text-primary)',
          transition: 'all .2s ease',
        }}>
          <span style={{
            width: 28, height: 28, borderRadius: 8, flexShrink: 0,
            background: 'rgba(245,197,24,0.15)',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="help" size={14} stroke={GOLD} strokeWidth={1.8}/>
          </span>
          <span style={{ flex: 1, fontSize: 13, fontWeight: 700, color: GOLD, letterSpacing: '0.01em' }}>
            {language === 'mn' ? 'Хэрхэн ажилдаг?' : 'How does it work?'}
          </span>
          <Icon name={showHow ? 'chevron-down' : 'chevron-right'} size={16} stroke={GOLD}/>
        </button>

        {showHow && (
          <div className="ns-glass" style={{
            padding: '4px 0', marginBottom: 20, overflow: 'hidden',
            borderTopLeftRadius: 0, borderTopRightRadius: 0,
            borderTop: '1px solid rgba(245,197,24,0.14)',
            animation: 'ns-slide-in-up .2s ease-out',
          }}>
            {steps.map((s, i) => (
              <div key={i} style={{
                display: 'flex', gap: 14, padding: '15px 18px',
                borderBottom: i < steps.length - 1 ? '1px solid var(--hairline)' : 'none',
              }}>
                <div style={{
                  width: 36, height: 36, borderRadius: '50%', flexShrink: 0,
                  background: 'rgba(245,197,24,0.12)',
                  border: '1px solid rgba(245,197,24,0.25)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontFamily: 'JetBrains Mono, monospace', fontSize: 11, fontWeight: 700, color: GOLD,
                }}>{s.n}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 13 }}>{s.title}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 3, lineHeight: 1.45 }}>
                    {s.body}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* ── COMMISSION RATES ── */}
        <div className="ns-mono" style={{ marginBottom: 10 }}>
          {language === 'mn' ? 'КОМИССЫН ХЭМЖЭЭ' : 'COMMISSION RATES'}
        </div>
        <div className="ns-glass" style={{ overflow: 'hidden', marginBottom: 22 }}>
          {commissions.map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px',
              borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
            }}>
              <span style={{
                width: 34, height: 34, borderRadius: 10, flexShrink: 0,
                background: 'rgba(245,197,24,0.10)', color: GOLD,
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name={r.icon} size={16}/>
              </span>
              <span style={{ flex: 1, fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.4 }}>
                {r.label}
              </span>
              <span style={{
                fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 700, color: GOLD,
                filter: 'drop-shadow(0 0 6px rgba(245,197,24,0.4))', flexShrink: 0,
              }}>{r.value}</span>
            </div>
          ))}
        </div>

        {/* ── WITHDRAW ── */}
        <div className="ns-mono" style={{ marginBottom: 10 }}>
          {language === 'mn' ? 'ОРЛОГО ТАТАХ' : 'WITHDRAW EARNINGS'}
        </div>
        <div style={{
          borderRadius: 20,
          background: 'linear-gradient(135deg, rgba(245,197,24,0.11) 0%, rgba(255,140,0,0.07) 100%)',
          border: '1px solid rgba(245,197,24,0.24)',
          padding: '18px 18px 16px',
          marginBottom: 22,
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', top: -40, right: -40, width: 130, height: 130, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(245,197,24,0.2), transparent 65%)',
            filter: 'blur(16px)', pointerEvents: 'none',
          }}/>

          {/* balance row */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 16 }}>
            <div>
              <div className="ns-mono" style={{ fontSize: 9, color: GOLD, letterSpacing: '0.14em' }}>
                {language === 'mn' ? 'ТАТАХ БОЛОМЖТОЙ' : 'AVAILABLE'}
              </div>
              <div style={{ fontFamily: 'var(--ff-display)', fontSize: 32, fontWeight: 700, color: GOLD, marginTop: 4,
                filter: 'drop-shadow(0 0 10px rgba(245,197,24,0.45))' }}>
                ₮62,000
              </div>
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-tertiary)', textAlign: 'right', lineHeight: 1.55 }}>
              {language === 'mn' ? 'Хамгийн бага\n₮10,000' : 'Min. withdrawal\n₮10,000'}
            </div>
          </div>

          {/* bank account row */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
            borderRadius: 12,
            background: 'rgba(255,255,255,0.04)',
            border: '1px solid rgba(245,197,24,0.18)',
            marginBottom: 14, cursor: 'pointer',
          }}>
            <span style={{
              width: 36, height: 36, borderRadius: 10, flexShrink: 0,
              background: 'rgba(245,197,24,0.12)',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon name="wallet" size={16} stroke={GOLD}/>
            </span>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>Khan Bank</div>
              <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>**** **** **** 4821</div>
            </div>
            <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
          </div>

          {/* withdraw button */}
          <button onClick={() => window.__showNotification?.(
            language === 'mn' ? '₮62,000 татах хүсэлт илгээгдлээ ✓' : 'Withdrawal request sent: ₮62,000',
            'check', 3000
          )} style={{
            width: '100%', height: 46, borderRadius: 12,
            background: 'linear-gradient(135deg, #F5C518 0%, #FFB347 60%, #FF8C00 100%)',
            border: 'none', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            color: '#1B0210', fontFamily: 'var(--ff-body)', fontWeight: 800, fontSize: 14,
            letterSpacing: '0.05em', textTransform: 'uppercase',
            boxShadow: '0 6px 20px rgba(245,197,24,0.38)',
          }}>
            <Icon name="wallet" size={16} stroke="#1B0210" strokeWidth={2.2}/>
            {language === 'mn' ? '₮62,000 татах' : 'Withdraw ₮62,000'}
          </button>
        </div>

        {/* ── RECENT REFERRALS ── */}
        <div className="ns-mono" style={{ marginBottom: 10 }}>
          {language === 'mn' ? 'СҮҮЛИЙН БҮРТГЭЛҮҮД' : 'RECENT REFERRALS'}
        </div>
        <div className="ns-glass" style={{ overflow: 'hidden' }}>
          {recent.map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px',
              borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
            }}>
              <Avatar size={38} initial={r.user[1].toUpperCase()} ring/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: 13 }}>{r.user}</div>
                <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>
                  {r.time} · {r.type === 'signup'
                    ? (language === 'mn' ? 'Бүртгэл'  : 'Signup')
                    : (language === 'mn' ? 'Контент'   : 'Content')}
                </div>
              </div>
              <div style={{
                fontFamily: 'var(--ff-display)', fontSize: 16, fontWeight: 700, color: GOLD,
              }}>{r.amount}</div>
            </div>
          ))}
        </div>

      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 21 — AFFILIATE UNLOCK (paywall)
// ────────────────────────────────────────────────────────────
function ScreenAffiliateUnlock({ go, language }) {
  const [paying, setPaying] = React.useState(false);
  const GOLD = '#F5C518';

  const pay = () => {
    setPaying(true);
    setTimeout(() => {
      window.__showNotification?.(
        language === 'mn'
          ? '₮5,000 төлбөр амжилттай! Таны код үүслээ 🌟'
          : 'Payment successful! Your code is ready 🌟',
        'check', 3000
      );
      go('affiliate');
    }, 1800);
  };

  const benefits = [
    language === 'mn' ? 'Бүртгэл тутамд ₮5,000 орлого'          : 'Earn ₮5,000 per referral signup',
    language === 'mn' ? 'Paid контентын орлогоос 10%'              : '10% commission on paid content',
    language === 'mn' ? 'Эвент тасалбар борлуулалтаас 5%'         : '5% on event ticket sales',
    language === 'mn' ? 'Бодит цагийн орлогын dashboard'          : 'Real-time earnings dashboard',
    language === 'mn' ? 'Нэг удаагийн идэвхжүүлэлт, насан туршид' : 'One-time activation, lifetime access',
  ];

  return (
    <div className="ns-screen">
      <PhoneStatus/>

      {/* header */}
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '6px 12px 12px' }}>
        <button style={iconBtn} onClick={() => go('me')}>
          <Icon name="arrow-left" size={22}/>
        </button>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500,
          display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ color: GOLD, filter: 'drop-shadow(0 0 6px rgba(245,197,24,0.6))' }}>
            <Icon name="sparkles" size={18} stroke={GOLD} strokeWidth={1.8} filled/>
          </span>
          {language === 'mn' ? 'Партнер хөтөлбөр' : 'Affiliate Program'}
        </div>
        <div style={{ width: 40 }}/>
      </div>

      <div className="ns-screen-scroll" style={{ padding: '0 24px 40px' }}>

        {/* hero */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '20px 0 24px', position: 'relative' }}>
          <div style={{ position: 'absolute', inset: 0,
            background: 'radial-gradient(circle at 50% 50%, rgba(245,197,24,0.1), transparent 65%)' }}/>
          {[160, 120, 86].map((sz, i) => (
            <div key={i} style={{
              position: 'absolute', width: sz, height: sz, borderRadius: '50%',
              border: `1px solid rgba(245,197,24,${0.08 + i * 0.06})`,
              top: '50%', left: '50%', transform: 'translate(-50%,-50%)',
            }}/>
          ))}
          <div style={{
            width: 82, height: 82, borderRadius: '50%', position: 'relative',
            background: 'radial-gradient(circle, rgba(245,197,24,0.22), rgba(255,140,0,0.10) 60%, transparent)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            filter: 'drop-shadow(0 0 24px rgba(245,197,24,0.55))',
          }}>
            <Icon name="sparkles" size={38} stroke={GOLD} strokeWidth={1.4} filled/>
          </div>
        </div>

        {/* title */}
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <h1 style={{ margin: 0, fontFamily: 'var(--ff-display)', fontSize: 28,
            fontWeight: 700, letterSpacing: '-0.01em', lineHeight: 1.1 }}>
            {language === 'mn' ? 'Партнер' : 'Join the'}
            <br/>
            <span style={{ color: GOLD, fontStyle: 'italic',
              filter: 'drop-shadow(0 0 14px rgba(245,197,24,0.5))' }}>
              {language === 'mn' ? 'хөтөлбөрт нэгд' : 'Affiliate Program'}
            </span>
          </h1>
          <p style={{ margin: '12px 0 0', fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.55 }}>
            {language === 'mn'
              ? 'Night Owl-г найддаа санал болгоод тогтмол орлого ол. Нэг удаагийн идэвхжүүлэлт.'
              : 'Refer friends to Night Owl and earn recurring commissions. One-time activation.'}
          </p>
        </div>

        {/* benefits */}
        <div className="ns-glass" style={{ padding: '4px 0', marginBottom: 22, overflow: 'hidden' }}>
          {benefits.map((b, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px',
              borderBottom: i < benefits.length - 1 ? '1px solid var(--hairline)' : 'none',
            }}>
              <span style={{
                width: 24, height: 24, borderRadius: '50%', flexShrink: 0,
                background: 'rgba(245,197,24,0.14)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name="check" size={12} stroke={GOLD} strokeWidth={2.5}/>
              </span>
              <span style={{ fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.4 }}>{b}</span>
            </div>
          ))}
        </div>

        {/* price + QPay button */}
        <div style={{
          borderRadius: 22,
          background: 'linear-gradient(135deg, rgba(245,197,24,0.14) 0%, rgba(255,140,0,0.09) 100%)',
          border: '1px solid rgba(245,197,24,0.3)',
          padding: '20px 20px 18px',
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', top: -48, right: -48, width: 160, height: 160,
            borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(245,197,24,0.24), transparent 65%)',
            filter: 'blur(20px)', pointerEvents: 'none',
          }}/>

          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 4 }}>
            <div style={{ fontFamily: 'var(--ff-display)', fontSize: 46, fontWeight: 800,
              color: GOLD, lineHeight: 1,
              filter: 'drop-shadow(0 0 14px rgba(245,197,24,0.5))' }}>
              ₮5,000
            </div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              {language === 'mn' ? '/ нэг удаа' : '/ one time'}
            </div>
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 18 }}>
            {language === 'mn' ? 'QPay-р төлж, нэн даруй эхлэ' : 'Pay via QPay and start instantly'}
          </div>

          {paying ? (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center',
              gap: 10, padding: '14px 0' }}>
              <div className="ns-spin"/>
              <span style={{ color: GOLD, fontSize: 13, fontWeight: 600 }}>
                {language === 'mn' ? 'Төлбөр баталгаажиж байна...' : 'Processing payment...'}
              </span>
            </div>
          ) : (
            <button onClick={pay} style={{
              width: '100%', height: 52, borderRadius: 14,
              background: 'linear-gradient(135deg, #F5C518 0%, #FFB347 55%, #FF8C00 100%)',
              border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
              color: '#1B0210', fontFamily: 'var(--ff-body)', fontWeight: 800, fontSize: 15,
              letterSpacing: '0.04em', textTransform: 'uppercase',
              boxShadow: '0 8px 28px rgba(245,197,24,0.42)',
            }}>
              <span style={{
                width: 24, height: 24, borderRadius: 5,
                background: 'rgba(27,2,16,0.18)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: 'serif', fontWeight: 900, fontSize: 14,
              }}>Q</span>
              {language === 'mn' ? 'QPay-р нэгдэх' : 'Pay with QPay'}
            </button>
          )}
        </div>

      </div>
    </div>
  );
}

Object.assign(window, { ScreenNotifications, ScreenProfile, ScreenSettings, ScreenBusiness, ScreenAffiliate, ScreenAffiliateUnlock });
