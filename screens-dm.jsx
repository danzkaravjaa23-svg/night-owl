/* screens-dm.jsx
   20 DM List  ·  21 DM Thread
*/

const DM_THREADS = [
  { id: 't1', name: 'Bayarmaa DJ',   user: '@bayar.dj',     initial: 'Б',
    last: 'Маргааш Mass-д ирэх үү?', time: '21:42', unread: 2, online: true, ring: true },
  { id: 't2', name: 'Sugar Lounge',  user: '@sugar.lounge', initial: 'S',
    last: 'Эвентэд урьж байна 🥂',   time: '20:15', unread: 1, venue: true },
  { id: 't3', name: 'Nara U',         user: '@nara.ulaan',    initial: 'Н',
    last: 'Тэр зурагнаас илгээгээч', time: '18:04', unread: 0 },
  { id: 't4', name: 'Solongo',        user: '@solongo',       initial: 'С',
    last: 'Жажингаас уулзъя.',        time: 'Өчигдөр', unread: 0 },
  { id: 't5', name: 'Odgerel',        user: '@odgerel',       initial: 'О',
    last: 'Хүлээнэ, амжаарай',        time: 'Лха',     unread: 0 },
  { id: 't6', name: 'Erden DJ',       user: '@erden_dj',      initial: 'Э',
    last: 'Set 9-д эхэлнэ',           time: 'Мяг',     unread: 0 },
  { id: 't7', name: 'Mass Club',      user: '@mass_club',     initial: 'M',
    last: 'Шинэ резидент DJ зарлав',  time: '5/22',    unread: 0, venue: true },
];

const ACTIVE_THREAD = [
  { from: 'them', t: 'Энэ долоо хоног хаана аялах вэ?',  time: '21:12' },
  { from: 'me',   t: 'Бямбад Mass руу очих гэсэн',        time: '21:14' },
  { from: 'them', t: 'Mass гэнэ үү? Шинэ set байгаа гэсэн', time: '21:16' },
  { from: 'them', t: 'Vinyl байх',                          time: '21:16' },
  { from: 'me',   t: 'Аан. Хэдэн цагаас?',                 time: '21:38' },
  { from: 'them', t: 'Маргааш Mass-д ирэх үү?',            time: '21:42' },
];

// ────────────────────────────────────────────────────────────
// 20 — DM LIST
// ────────────────────────────────────────────────────────────
function ScreenDMList({ go, state, language }) {
  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DMListHeader go={go} language={language}/>
        <div className="ns-screen-scroll" style={{ padding: '8px 20px' }}>
          {[1,2,3,4,5].map(i => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0' }}>
              <Skel w={48} h={48} r={24}/>
              <div style={{ flex: 1 }}>
                <Skel w="40%" h={13}/>
                <div style={{ height: 6 }}/>
                <Skel w="70%" h={11}/>
              </div>
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
        <DMListHeader go={go} language={language}/>
        <EmptyState
          icon="send"
          title={tr('dm.empty.title', language)}
          body={tr('dm.empty.body', language)}
          action={
            <button className="ns-btn-primary" onClick={() => go('feed')}>
              <Icon name="plus" size={16} stroke="#1B0210" strokeWidth={2.2}/>
              {tr('btn.newChat', language)}
            </button>
          }
        />
      </div>
    );
  }
  if (state === 'error') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DMListHeader go={go} language={language}/>
        <ErrorState onRetry={() => go('dm-list')}/>
      </div>
    );
  }

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <DMListHeader go={go} language={language}/>

      <div style={{ flexShrink: 0, padding: '4px 20px 12px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '10px 14px', borderRadius: 9999,
          background: 'var(--bg-surface)',
          border: '1px solid var(--hairline)',
        }}>
          <Icon name="search" size={16} stroke="var(--text-secondary)"/>
          <input placeholder={tr('ph.searchChat', language)} style={{
            flex: 1, background: 'transparent', border: 0, outline: 0,
            color: 'var(--text-primary)', fontSize: 14,
          }}/>
        </div>
      </div>

      <div style={{ flexShrink: 0, padding: '0 16px 14px' }}>
        <div className="ns-mono" style={{ padding: '0 4px 8px' }}>{tr('lbl.active', language)}</div>
        <div style={{ display: 'flex', gap: 14, overflowX: 'auto', padding: '0 4px', scrollbarWidth: 'none' }}>
          {DM_THREADS.slice(0, 5).map(t => (
            <div key={t.id} onClick={() => go('dm-thread')} style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
              cursor: 'pointer', flexShrink: 0,
            }}>
              <div style={{ position: 'relative' }}>
                <Avatar size={54} initial={t.initial} ring={t.ring}/>
                {t.online && (
                  <span style={{
                    position: 'absolute', right: 0, bottom: 2,
                    width: 14, height: 14, borderRadius: 7,
                    background: 'var(--success)',
                    border: '2.5px solid var(--bg-base)',
                  }}/>
                )}
              </div>
              <span style={{ fontSize: 10.5, color: 'var(--text-secondary)', maxWidth: 60,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {t.name.split(' ')[0]}
              </span>
            </div>
          ))}
        </div>
      </div>

      <div className="ns-screen-scroll" style={{ paddingBottom: 12 }}>
        <div className="ns-mono" style={{ padding: '0 24px 6px' }}>{tr('lbl.messages', language)}</div>
        {DM_THREADS.map(t => (
          <button key={t.id} onClick={() => go('dm-thread')} style={{
            width: '100%', textAlign: 'left',
            background: 'transparent', border: 0, cursor: 'pointer',
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 20px', color: 'var(--text-primary)',
          }}>
            <div style={{ position: 'relative', flexShrink: 0 }}>
              <Avatar size={50} initial={t.initial} ring={t.ring}/>
              {t.online && (
                <span style={{
                  position: 'absolute', right: 0, bottom: 0,
                  width: 13, height: 13, borderRadius: 7,
                  background: 'var(--success)',
                  border: '2.5px solid var(--bg-base)',
                }}/>
              )}
              {t.venue && (
                <span style={{
                  position: 'absolute', right: -2, bottom: -2,
                  width: 18, height: 18, borderRadius: 9,
                  background: 'var(--accent-grad)', color: '#1B0210',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: '2px solid var(--bg-base)',
                }}>
                  <Icon name="pin" size={10} stroke="#1B0210" strokeWidth={2.2}/>
                </span>
              )}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span style={{ fontWeight: 700, fontSize: 14 }}>{t.name}</span>
                <span style={{ fontSize: 11, color: 'var(--text-tertiary)', flexShrink: 0,
                      marginLeft: 'auto' }}>{t.time}</span>
              </div>
              <div style={{
                fontSize: 13, marginTop: 2,
                color: t.unread > 0 ? 'var(--text-primary)' : 'var(--text-secondary)',
                fontWeight: t.unread > 0 ? 600 : 400,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                display: 'flex', alignItems: 'center', gap: 8,
              }}>
                <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {t.last}
                </span>
                {t.unread > 0 && (
                  <span style={{
                    minWidth: 20, height: 20, padding: '0 6px',
                    borderRadius: 10, background: 'var(--accent-grad)',
                    color: '#1B0210', fontSize: 11, fontWeight: 800,
                    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                    flexShrink: 0,
                  }}>{t.unread}</span>
                )}
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}

function DMListHeader({ go, language }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 12px 12px',
    }}>
      <button style={iconBtn} onClick={() => go('feed')}>
        <Icon name="arrow-left" size={22}/>
      </button>
      <div>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500, textAlign: 'center' }}>
          {tr('lbl.chat', language)}
        </div>
        <div className="ns-mono" style={{ textAlign: 'center', marginTop: 2 }}>@munkh_ub</div>
      </div>
      <button style={iconBtn}>
        <Icon name="edit" size={20}/>
      </button>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 21 — DM THREAD
// ────────────────────────────────────────────────────────────
function ScreenDMThread({ go, state, language }) {
  const partner = DM_THREADS[0];

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DMThreadHeader go={go} partner={partner} language={language}/>
        <LoadingState label={tr('lbl.loading.dm', language)}/>
      </div>
    );
  }
  if (state === 'empty') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DMThreadHeader go={go} partner={partner} language={language}/>
        <EmptyState
          icon="send"
          title={tr('dm.thread.empty.title', language)}
          body={tr('dm.thread.empty.body', language)}
        />
        <DMInput language={language}/>
      </div>
    );
  }
  if (state === 'error') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DMThreadHeader go={go} partner={partner} language={language}/>
        <ErrorState onRetry={() => go('dm-thread')}/>
      </div>
    );
  }

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <DMThreadHeader go={go} partner={partner} language={language}/>

      <div className="ns-screen-scroll" style={{ padding: '4px 16px 12px',
            display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{ textAlign: 'center', padding: '14px 0' }}>
          <span className="ns-mono">{tr('lbl.today', language)} · 21:00</span>
        </div>

        {ACTIVE_THREAD.map((m, i, arr) => {
          const me = m.from === 'me';
          const next = arr[i + 1];
          const last = !next || next.from !== m.from;
          return (
            <div key={i} style={{
              display: 'flex',
              justifyContent: me ? 'flex-end' : 'flex-start',
              alignItems: 'flex-end', gap: 8,
            }}>
              {!me && (
                <div style={{ width: 28, opacity: last ? 1 : 0 }}>
                  {last && <Avatar size={28} initial={partner.initial}/>}
                </div>
              )}
              <div style={{
                maxWidth: '74%',
                padding: '10px 14px',
                borderRadius: me
                  ? `18px 18px ${last ? 4 : 18}px 18px`
                  : `18px 18px 18px ${last ? 4 : 18}px`,
                background: me ? 'var(--accent-grad)' : 'var(--bg-surface)',
                color: me ? '#1B0210' : 'var(--text-primary)',
                border: me ? 'none' : '1px solid var(--hairline)',
                fontSize: 14, lineHeight: 1.45,
                fontWeight: me ? 500 : 400,
              }}>
                {m.t}
              </div>
            </div>
          );
        })}

        <div style={{ display: 'flex', justifyContent: 'flex-start', marginTop: 8,
              paddingLeft: 36, gap: 4, alignItems: 'center' }}>
          <span style={{
            display: 'inline-flex', gap: 3, padding: '8px 12px',
            background: 'var(--bg-surface)', border: '1px solid var(--hairline)',
            borderRadius: 18,
          }}>
            {[0, 1, 2].map(d => (
              <span key={d} style={{
                width: 6, height: 6, borderRadius: 3,
                background: 'var(--text-tertiary)',
                animation: `ns-dot 1.4s ${d * 0.2}s ease-in-out infinite`,
              }}/>
            ))}
          </span>
        </div>
        <style>{`
          @keyframes ns-dot {
            0%,60%,100% { transform: translateY(0); opacity: 0.4; }
            30% { transform: translateY(-3px); opacity: 1; }
          }
        `}</style>
      </div>

      <DMInput language={language}/>
    </div>
  );
}

function DMThreadHeader({ go, partner, language }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '6px 12px 12px',
      borderBottom: '1px solid var(--hairline)',
    }}>
      <button style={iconBtn} onClick={() => go('dm-list')}>
        <Icon name="arrow-left" size={22}/>
      </button>
      <Avatar size={36} initial={partner.initial} ring={partner.ring}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 14 }}>{partner.name}</div>
        <div style={{ fontSize: 11, color: 'var(--success)', display: 'flex', alignItems: 'center', gap: 4 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: 'currentColor',
            boxShadow: '0 0 6px currentColor' }}/>
          {tr('lbl.online', language)}
        </div>
      </div>
      <button style={iconBtn}><Icon name="phone" size={20}/></button>
      <button style={iconBtn}><Icon name="more" size={20}/></button>
    </div>
  );
}

function DMInput({ language }) {
  return (
    <div style={{
      flexShrink: 0,
      padding: '10px 12px 16px',
      display: 'flex', alignItems: 'center', gap: 8,
      background: 'rgba(11,1,24,0.85)', backdropFilter: 'blur(12px)',
      borderTop: '1px solid var(--hairline)',
    }}>
      <button style={iconBtn}>
        <Icon name="camera" size={20}/>
      </button>
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', gap: 6,
        padding: '6px 6px 6px 16px', borderRadius: 9999,
        background: 'var(--bg-surface)', border: '1px solid var(--hairline)',
      }}>
        <input placeholder={tr('ph.writeMessage', language)} style={{
          flex: 1, background: 'transparent', border: 0, outline: 0,
          color: 'var(--text-primary)', fontSize: 14, height: 32,
        }}/>
        <button style={{
          width: 32, height: 32, borderRadius: 16,
          border: 0, background: 'transparent', cursor: 'pointer',
          color: 'var(--text-secondary)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}><Icon name="image" size={18}/></button>
      </div>
      <button style={{
        width: 40, height: 40, borderRadius: '50%',
        border: 0, background: 'var(--accent-grad)', cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#1B0210',
      }}>
        <Icon name="send" size={18} stroke="#1B0210" strokeWidth={2}/>
      </button>
    </div>
  );
}

Object.assign(window, { ScreenDMList, ScreenDMThread });
