/* screens-map.jsx — Google Maps + Snap Map hybrid design
   13 Map · 14 Bar Profile · 15 Create Post
*/

const BARS = [
  { id: 'v0', name: 'Sugar Lounge',    rating: 4.9, reviews: 612, dist: '0.2 км', open: true,  tag: 'Lounge', x: 44, y: 38, featured: true, today: 'Live R&B нөөр' },
  { id: 'v1', name: 'Vertigo Rooftop', rating: 4.8, reviews: 312, dist: '0.4 км', open: true,  tag: 'Lounge', x: 32, y: 28, today: 'Jazz trio · 21:00' },
  { id: 'v2', name: 'Mass Club',        rating: 4.6, reviews: 528, dist: '1.1 км', open: true,  tag: 'Club',   x: 58, y: 18, today: 'DJ Bayar · vinyl set' },
  { id: 'v3', name: 'Brewery Praha',    rating: 4.4, reviews: 187, dist: '0.8 км', open: true,  tag: 'Pub',    x: 22, y: 56 },
  { id: 'v4', name: 'Element Lounge',   rating: 4.7, reviews: 244, dist: '1.6 км', open: false, tag: 'Lounge', x: 70, y: 50 },
  { id: 'v5', name: 'Choco Metropolis', rating: 4.5, reviews: 401, dist: '2.0 км', open: true,  tag: 'Club',   x: 48, y: 72, today: 'House night · 22:30' },
  { id: 'v6', name: 'Hops & Rocks',     rating: 4.2, reviews: 96,  dist: '2.4 км', open: false, tag: 'Pub',    x: 80, y: 78 },
];

const PEOPLE = [
  { id: 'u1', name: 'Bayarmaa DJ',  user: '@bayar.dj',    initial: 'Б', bio: 'Resident · Mass Club · House/Techno', dist: '0.5 км', followers: '8.4K', ring: true, here: 'Mass Club' },
  { id: 'u2', name: 'Nara U',       user: '@nara.ulaan',  initial: 'Н', bio: 'Live music · vinyl collector',         dist: '0.7 км', followers: '2.1K', ring: true, here: 'Vertigo Rooftop' },
  { id: 'u3', name: 'Solongo',      user: '@solongo',     initial: 'С', bio: 'Cocktail tasting · mixology',          dist: '1.2 км', followers: '4.6K', ring: true, here: 'Sugar Lounge' },
  { id: 'u4', name: 'Odgerel',      user: '@odgerel',     initial: 'О', bio: 'Pub culture · craft beer',            dist: '1.8 км', followers: '980' },
  { id: 'u5', name: 'Erden DJ',     user: '@erden_dj',    initial: 'Э', bio: 'Techno · UB underground',              dist: '2.1 км', followers: '5.2K', ring: true },
  { id: 'u6', name: 'Enkhjin',      user: '@enkh_94',     initial: 'Е', bio: 'Lounge, jazz, slow drinks',            dist: '2.6 км', followers: '1.4K' },
];

// Tag → gradient colors
const TAG_COLORS = {
  Club:   ['#7B2FF7', '#B14CF7'],
  Lounge: ['#FF4D8D', '#FF7B5C'],
  Pub:    ['#FFB347', '#FF7B5C'],
};

// ────────────────────────────────────────────────────────────
// 13 — MAP
// ────────────────────────────────────────────────────────────
function ScreenMap({ go, state, language }) {
  const [mode,   setMode]   = React.useState('places');
  const [filter, setFilter] = React.useState('all');
  const [tapped, setTapped] = React.useState(null); // tapped venue id

  const visible = mode !== 'places' ? [] :
    filter === 'all' ? BARS :
    filter === 'open' ? BARS.filter(b => b.open) :
    BARS.filter(b => b.tag.toLowerCase() === filter);

  return (
    <div className="ns-screen" style={{ background: '#080B1A' }}>
      <PhoneStatus/>

      {/* ── MAP AREA ── */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 390,
        overflow: 'hidden',
      }}>
        <MapCanvas/>

        {/* venue pins */}
        {state !== 'loading' && state !== 'error' && state !== 'empty' && mode === 'places' &&
          visible.map(b => (
            <button key={b.id} onClick={() => { setTapped(t => t === b.id ? null : b.id); go('bar'); }}
              style={{
                position: 'absolute',
                left: `${b.x}%`, top: `${b.y}%`,
                transform: 'translate(-50%, -100%)',
                background: 'transparent', border: 0, cursor: 'pointer', zIndex: 5,
              }}>
              <SnapPin
                label={b.name.split(' ')[0]}
                tag={b.tag}
                open={b.open}
                hot={b.featured || b.rating >= 4.8}
                active={tapped === b.id}
              />
            </button>
          ))
        }

        {/* people pins */}
        {state !== 'loading' && state !== 'error' && mode === 'people' &&
          PEOPLE.filter(p => p.here).map((p, i) => (
            <button key={p.id} onClick={() => go('creator')}
              style={{
                position: 'absolute',
                left: `${28 + i * 18}%`, top: `${26 + i * 13}%`,
                transform: 'translate(-50%, -100%)',
                background: 'transparent', border: 0, cursor: 'pointer', zIndex: 5,
              }}>
              <SnapPersonPin initial={p.initial} name={p.user}/>
            </button>
          ))
        }

        {/* my location dot */}
        <div style={{
          position: 'absolute', left: '50%', top: '64%',
          transform: 'translate(-50%, -50%)', zIndex: 6,
        }}>
          <div style={{
            width: 56, height: 56, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(92,123,255,0.35), transparent 68%)',
            position: 'absolute', inset: -19,
            animation: 'ns-pulse 2.4s ease-in-out infinite',
          }}/>
          <div style={{
            width: 16, height: 16, borderRadius: '50%',
            background: '#5C7BFF',
            border: '3px solid #fff',
            boxShadow: '0 0 0 1.5px rgba(92,123,255,0.4), 0 2px 10px rgba(92,123,255,0.7)',
          }}/>
        </div>

        {/* gradient fade at bottom of map */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0, height: 80,
          background: 'linear-gradient(to bottom, transparent, #080B1A)',
          pointerEvents: 'none',
        }}/>

        {/* recenter button (Google Maps style) */}
        <button style={{
          position: 'absolute', right: 14, bottom: 24, zIndex: 8,
          width: 40, height: 40, borderRadius: 12,
          background: 'rgba(14,8,32,0.88)', backdropFilter: 'blur(16px)',
          border: '1px solid rgba(255,255,255,0.1)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer', color: '#5C7BFF',
          boxShadow: '0 4px 16px rgba(0,0,0,0.5)',
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/>
            <line x1="12" y1="2" x2="12" y2="5"/>
            <line x1="12" y1="19" x2="12" y2="22"/>
            <line x1="2" y1="12" x2="5" y2="12"/>
            <line x1="19" y1="12" x2="22" y2="12"/>
          </svg>
        </button>
      </div>

      {/* ── SEARCH + CONTROLS (overlaid on map) ── */}
      <div style={{ position: 'relative', zIndex: 10, padding: '6px 14px 0' }}>
        {/* search bar — Snap style */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '11px 16px', borderRadius: 16,
          background: 'rgba(18,10,38,0.88)', backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.09)',
          boxShadow: '0 4px 20px rgba(0,0,0,0.4)',
        }}>
          <Icon name="search" size={17} stroke="rgba(255,255,255,0.5)"/>
          <input
            placeholder={mode === 'places' ? tr('ph.searchPlaces', language) : tr('ph.searchPeople', language)}
            style={{
              flex: 1, background: 'transparent', border: 0, outline: 0,
              color: '#fff', fontSize: 14,
            }}/>
          <span style={{
            fontFamily: 'var(--ff-mono)', fontSize: 9, letterSpacing: '0.16em',
            color: 'rgba(255,255,255,0.35)', paddingLeft: 6,
            borderLeft: '1px solid rgba(255,255,255,0.1)',
          }}>UB</span>
        </div>

        {/* Places / People — Snap-style pill toggle */}
        <div style={{
          display: 'flex', marginTop: 10,
          background: 'rgba(14,8,32,0.82)', backdropFilter: 'blur(16px)',
          borderRadius: 9999, padding: 3,
          border: '1px solid rgba(255,255,255,0.07)',
          width: 'fit-content',
          boxShadow: '0 2px 12px rgba(0,0,0,0.4)',
        }}>
          {[
            { k: 'places', lKey: 'lbl.places', icon: 'pin' },
            { k: 'people', lKey: 'lbl.people', icon: 'user' },
          ].map(seg => {
            const on = mode === seg.k;
            return (
              <button key={seg.k} onClick={() => setMode(seg.k)} style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '8px 18px', borderRadius: 9999,
                background: on ? 'var(--accent-grad)' : 'transparent',
                border: 0, cursor: 'pointer',
                color: on ? '#1B0210' : 'rgba(255,255,255,0.8)',
                fontFamily: 'var(--ff-body)', fontWeight: on ? 700 : 500,
                fontSize: 13,
                boxShadow: on ? '0 2px 10px rgba(255,77,141,0.4)' : 'none',
              }}>
                <Icon name={seg.icon} size={13} stroke={on ? '#1B0210' : 'currentColor'} strokeWidth={2}/>
                {tr(seg.lKey, language)}
              </button>
            );
          })}
        </div>

        {/* filter chips */}
        {mode === 'places' && (
          <div style={{
            display: 'flex', gap: 7, overflowX: 'auto', padding: '10px 0 0',
            scrollbarWidth: 'none',
          }}>
            {[
              { k: 'all',    lKey: 'filter.all' },
              { k: 'open',   lKey: 'filter.open' },
              { k: 'club',   l: 'Club' },
              { k: 'lounge', l: 'Lounge' },
              { k: 'pub',    l: 'Pub' },
              { k: 'music',  l: 'Live music' },
            ].map(f => {
              const on = filter === f.k;
              return (
                <span key={f.k}
                  onClick={() => setFilter(f.k)}
                  style={{
                    flexShrink: 0, padding: '6px 14px', borderRadius: 9999,
                    background: on ? 'var(--accent-grad)' : 'rgba(14,8,32,0.82)',
                    border: on ? 'none' : '1px solid rgba(255,255,255,0.09)',
                    color: on ? '#1B0210' : 'rgba(255,255,255,0.82)',
                    fontSize: 12, fontWeight: on ? 700 : 500, cursor: 'pointer',
                    backdropFilter: 'blur(10px)',
                    boxShadow: on ? '0 2px 10px rgba(255,77,141,0.35)' : 'none',
                  }}>
                  {f.lKey ? tr(f.lKey, language) : f.l}
                </span>
              );
            })}
          </div>
        )}
      </div>

      <div style={{ flex: 1 }}/>

      {/* ── BOTTOM SHEET (Google Maps style) ── */}
      <div style={{
        position: 'relative', zIndex: 10,
        background: 'linear-gradient(180deg, rgba(8,11,26,0.0) 0%, #0D0620 8%)',
        borderRadius: '28px 28px 0 0',
        border: '1px solid rgba(255,255,255,0.07)', borderBottom: 0,
        paddingTop: 8,
        height: 430, display: 'flex', flexDirection: 'column',
        backdropFilter: 'blur(24px)',
        boxShadow: '0 -12px 40px rgba(0,0,0,0.6)',
        background: '#0D0620',
      }}>
        {/* drag handle */}
        <div style={{
          width: 40, height: 4, borderRadius: 4,
          background: 'rgba(255,255,255,0.15)', margin: '0 auto 10px',
          flexShrink: 0,
        }}/>

        {/* sheet header */}
        <div style={{
          padding: '0 20px 12px', display: 'flex',
          justifyContent: 'space-between', alignItems: 'center', flexShrink: 0,
        }}>
          <div>
            <div style={{ fontFamily: 'var(--ff-display)', fontSize: 16, fontWeight: 700 }}>
              {mode === 'places'
                ? `${visible.length} ${tr('lbl.nearby', language).replace('ОЙРХОН ГАЗАР · ', '').replace('NEARBY', '') || (language === 'mn' ? 'газар' : 'places')}`
                : `${PEOPLE.length} ${language === 'mn' ? 'хүн ойрхон' : 'people nearby'}`}
            </div>
            <div className="ns-mono" style={{ marginTop: 2, fontSize: 9 }}>
              {mode === 'places' ? tr('lbl.nearby', language) : tr('lbl.nearbyPeople', language)}
            </div>
          </div>
          <button className="ns-btn-ghost" style={{ height: 30, padding: '0 12px', fontSize: 12,
            borderRadius: 9999, border: '1px solid var(--hairline)' }}>
            {tr('btn.sort', language)}
            <Icon name="chevron-down" size={12} stroke="var(--text-secondary)"/>
          </button>
        </div>

        {/* list */}
        {state === 'loading' ? (
          <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[1,2,3].map(i => <Skel key={i} w="100%" h={88} r={18}/>)}
          </div>
        ) : state === 'empty' || (mode === 'places' && visible.length === 0) ? (
          <div style={{ padding: '32px 20px', textAlign: 'center',
                color: 'var(--text-tertiary)', fontSize: 13 }}>
            {mode === 'places' ? tr('lbl.noNearby', language) : tr('lbl.noNearbyPeople', language)}
          </div>
        ) : mode === 'places' ? (
          <div className="ns-screen-scroll" style={{ padding: '0 14px 16px' }}>
            {visible.map(b => <GMapsCard key={b.id} b={b} go={go} language={language}/>)}
          </div>
        ) : (
          <div className="ns-screen-scroll" style={{ padding: '0 14px 16px' }}>
            {PEOPLE.map(p => <SnapPeopleRow key={p.id} p={p} go={go} language={language}/>)}
          </div>
        )}
      </div>

      <style>{`
        @keyframes ns-pulse {
          0%,100% { transform: scale(1); opacity: 0.7; }
          50%      { transform: scale(1.3); opacity: 0.3; }
        }
      `}</style>
    </div>
  );
}

// ─── Google Maps style venue card ───
function GMapsCard({ b, go, language }) {
  const [c1, c2] = TAG_COLORS[b.tag] || TAG_COLORS.Lounge;
  return (
    <button onClick={() => go('bar')} style={{
      width: '100%', marginBottom: 10,
      display: 'flex', gap: 12, alignItems: 'stretch',
      padding: 12, borderRadius: 20,
      background: b.featured
        ? `linear-gradient(135deg, ${c1}1A, ${c2}0F), rgba(255,255,255,0.03)`
        : 'rgba(255,255,255,0.03)',
      border: b.featured
        ? `1px solid ${c1}38`
        : '1px solid rgba(255,255,255,0.07)',
      cursor: 'pointer', color: 'var(--text-primary)', textAlign: 'left',
    }}>
      {/* thumbnail */}
      <div style={{
        width: 80, height: 80, borderRadius: 14, overflow: 'hidden', flexShrink: 0,
        background: `linear-gradient(135deg, ${c1}33, ${c2}22)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        border: `1px solid ${c1}22`,
        position: 'relative',
      }}>
        <span style={{ fontSize: 26, color: c1, opacity: 0.6, fontWeight: 800 }}>
          {b.name[0]}
        </span>
        {b.featured && (
          <div style={{
            position: 'absolute', top: 6, left: 6,
            background: 'var(--accent-grad)', borderRadius: 6,
            padding: '2px 6px', fontSize: 8, fontWeight: 800, color: '#1B0210',
            letterSpacing: '0.06em',
          }}>★</div>
        )}
      </div>

      {/* info */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
        <div>
          {b.featured && (
            <div style={{ fontSize: 9, fontFamily: 'var(--ff-mono)', color: c1,
              letterSpacing: '0.12em', marginBottom: 2 }}>★ FEATURED</div>
          )}
          <div style={{ fontWeight: 700, fontSize: 15, lineHeight: 1.2,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {b.name}
          </div>

          {/* rating row — Google Maps style */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 4 }}>
            <span style={{ fontWeight: 700, fontSize: 12, color: '#FFB347' }}>{b.rating}</span>
            <div style={{ display: 'flex', gap: 1 }}>
              {[0,1,2,3,4].map(i => (
                <svg key={i} width="10" height="10" viewBox="0 0 24 24">
                  <path d="m12 3 2.7 6 6.3.6-4.8 4.2 1.5 6.2L12 16.8 6.3 20l1.5-6.2L3 9.6l6.3-.6z"
                    fill={i + 0.5 <= b.rating ? '#FFB347' : 'rgba(255,255,255,0.15)'}
                    stroke="none"/>
                </svg>
              ))}
            </div>
            <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>({b.reviews})</span>
            <span style={{ opacity: 0.3 }}>·</span>
            <span style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{b.tag}</span>
          </div>

          {/* distance + status row */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 5 }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 4,
              padding: '3px 8px', borderRadius: 9999,
              background: b.open ? 'rgba(61,214,140,0.12)' : 'rgba(255,84,112,0.10)',
              border: `1px solid ${b.open ? 'rgba(61,214,140,0.2)' : 'rgba(255,84,112,0.18)'}`,
              fontSize: 10, fontWeight: 700,
              color: b.open ? 'var(--success)' : 'var(--error)',
            }}>
              <span style={{ width: 5, height: 5, borderRadius: '50%',
                background: 'currentColor',
                boxShadow: b.open ? '0 0 5px currentColor' : 'none' }}/>
              {b.open ? tr('status.open', language) : tr('status.closed', language)}
            </span>
            <span style={{ fontSize: 11, color: 'var(--text-tertiary)',
              display: 'flex', alignItems: 'center', gap: 3 }}>
              <Icon name="pin" size={10} stroke="var(--text-tertiary)"/>
              {b.dist}
            </span>
          </div>
        </div>

        {/* tonight tag */}
        {b.today && (
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 5, alignSelf: 'flex-start',
            padding: '4px 8px', borderRadius: 8,
            background: 'rgba(255,179,71,0.10)',
            border: '1px solid rgba(255,179,71,0.2)',
            color: 'var(--warning)', fontSize: 10, fontWeight: 600,
          }}>
            <Icon name="ticket" size={10} stroke="currentColor"/>
            {tr('lbl.today', language)} · {b.today}
          </div>
        )}
      </div>
    </button>
  );
}

// ─── Snap-style people row ───
function SnapPeopleRow({ p, go, language }) {
  return (
    <button onClick={() => go('creator')} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 12,
      padding: '10px 4px', marginBottom: 2,
      background: 'transparent', border: 0,
      borderBottom: '1px solid rgba(255,255,255,0.05)',
      cursor: 'pointer', color: 'var(--text-primary)', textAlign: 'left',
    }}>
      {/* snap-style avatar with story ring */}
      <div style={{ position: 'relative', flexShrink: 0 }}>
        {p.ring && (
          <div style={{
            position: 'absolute', inset: -2, borderRadius: 14,
            background: 'var(--accent-grad)', zIndex: 0,
          }}/>
        )}
        <div style={{
          width: 52, height: 52, borderRadius: 12,
          background: p.here
            ? 'linear-gradient(135deg, rgba(255,77,141,0.25), rgba(123,47,247,0.2))'
            : 'rgba(255,255,255,0.05)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: p.ring ? 'none' : '1px solid rgba(255,255,255,0.08)',
          position: 'relative', zIndex: 1,
          fontSize: 20, fontWeight: 800, color: '#fff',
        }}>{p.initial}</div>
        {p.here && (
          <div style={{
            position: 'absolute', right: -3, bottom: -3, zIndex: 2,
            width: 16, height: 16, borderRadius: 5,
            background: 'var(--success)',
            border: '2px solid #0D0620',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="8" height="8" viewBox="0 0 8 8">
              <circle cx="4" cy="4" r="2.5" fill="#fff"/>
            </svg>
          </div>
        )}
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 14 }}>{p.name}</div>
        <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 2,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {p.user} · {p.bio}
        </div>
        {p.here ? (
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4, marginTop: 4,
            fontSize: 10, color: 'var(--success)', fontWeight: 700 }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'currentColor',
              boxShadow: '0 0 6px currentColor' }}/>
            {tr('lbl.nowAt', language)} {p.here}
          </div>
        ) : (
          <div style={{ fontSize: 10, color: 'var(--text-tertiary)', marginTop: 4 }}>
            {p.dist} · {p.followers} {tr('lbl.followers', language).toLowerCase()}
          </div>
        )}
      </div>

      <button onClick={e => { e.stopPropagation(); go('creator'); }} style={{
        padding: '7px 14px', borderRadius: 9999, flexShrink: 0,
        background: 'var(--accent-grad)', border: 0,
        color: '#1B0210', fontSize: 11, fontWeight: 700,
        letterSpacing: '0.03em', cursor: 'pointer',
        boxShadow: '0 2px 10px rgba(255,77,141,0.35)',
      }}>{tr('lbl.follow', language)}</button>
    </button>
  );
}

// ─── Snap-style venue pin on map ───
function SnapPin({ label, tag, open, hot, active }) {
  const [c1, c2] = TAG_COLORS[tag] || TAG_COLORS.Lounge;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0 }}>
      {/* label chip */}
      <div style={{
        padding: '4px 9px', borderRadius: 9999, marginBottom: 5,
        background: active ? `linear-gradient(135deg, ${c1}, ${c2})` : 'rgba(12,6,28,0.85)',
        backdropFilter: 'blur(10px)',
        border: active ? 'none' : '1px solid rgba(255,255,255,0.1)',
        fontSize: 10, fontWeight: 700,
        color: active ? '#1B0210' : (open ? '#fff' : 'rgba(255,255,255,0.4)'),
        whiteSpace: 'nowrap',
        boxShadow: active ? `0 2px 10px ${c1}66` : '0 2px 8px rgba(0,0,0,0.5)',
        transition: 'all .15s ease',
      }}>{label}</div>

      {/* marker body */}
      <div style={{ position: 'relative' }}>
        {hot && (
          <div style={{
            position: 'absolute', inset: -8, borderRadius: '50%',
            background: `radial-gradient(circle, ${c1}50, transparent 60%)`,
            filter: 'blur(5px)', animation: 'ns-pulse 2s ease-in-out infinite',
          }}/>
        )}
        <div style={{
          width: active ? 38 : 32, height: active ? 38 : 32,
          borderRadius: active ? 12 : 10,
          background: open
            ? `linear-gradient(135deg, ${c1}, ${c2})`
            : 'rgba(50,40,70,0.8)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: `2px solid ${open ? 'rgba(255,255,255,0.2)' : 'rgba(255,255,255,0.07)'}`,
          boxShadow: open
            ? `0 4px 16px ${c1}66, inset 0 1px 0 rgba(255,255,255,0.25)`
            : '0 2px 8px rgba(0,0,0,0.5)',
          position: 'relative', zIndex: 1,
          transition: 'all .15s ease',
        }}>
          <span style={{ fontSize: active ? 16 : 14, color: '#fff', fontWeight: 900 }}>
            {label[0]}
          </span>
        </div>
        {/* CSS triangle pointer */}
        <div style={{
          position: 'absolute', bottom: -7, left: '50%',
          transform: 'translateX(-50%)',
          width: 0, height: 0,
          borderLeft: '6px solid transparent',
          borderRight: '6px solid transparent',
          borderTop: `8px solid ${open ? c1 : 'rgba(50,40,70,0.8)'}`,
        }}/>
      </div>
    </div>
  );
}

// ─── Snap-style person pin on map ───
function SnapPersonPin({ initial, name }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0 }}>
      <div style={{ position: 'relative' }}>
        {/* glow */}
        <div style={{
          position: 'absolute', inset: -8, borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(255,77,141,0.45), transparent 65%)',
          filter: 'blur(5px)',
        }}/>
        {/* story ring */}
        <div style={{
          width: 40, height: 40, borderRadius: 13,
          padding: 2,
          background: 'var(--accent-grad)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 4px 16px rgba(255,77,141,0.5)',
          position: 'relative', zIndex: 1,
        }}>
          <div style={{
            width: '100%', height: '100%', borderRadius: 11,
            background: '#0B0118',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontWeight: 900, fontSize: 16,
          }}>{initial}</div>
        </div>
        {/* pointer */}
        <div style={{
          position: 'absolute', bottom: -7, left: '50%',
          transform: 'translateX(-50%)',
          width: 0, height: 0,
          borderLeft: '5px solid transparent',
          borderRight: '5px solid transparent',
          borderTop: '7px solid #FF4D8D',
        }}/>
      </div>
      <div style={{
        marginTop: 10,
        padding: '3px 8px', borderRadius: 9999,
        background: 'rgba(12,6,28,0.85)', backdropFilter: 'blur(10px)',
        border: '1px solid rgba(255,255,255,0.1)',
        fontSize: 9, fontWeight: 700, color: '#fff', whiteSpace: 'nowrap',
      }}>{name}</div>
    </div>
  );
}

// ─── City-block map background (Google Maps night mode inspired) ───
function MapCanvas() {
  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="none"
         style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}>
      <defs>
        <pattern id="grid" width="12" height="12" patternUnits="userSpaceOnUse">
          <rect width="12" height="12" fill="#0D0926"/>
          <rect x="0.5" y="0.5" width="10" height="10" rx="1" fill="#111230" opacity="0.6"/>
        </pattern>
        <linearGradient id="road-h" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#1E2045" stopOpacity="0.9"/>
          <stop offset="0.5" stopColor="#252750" stopOpacity="1"/>
          <stop offset="1" stopColor="#1E2045" stopOpacity="0.9"/>
        </linearGradient>
        <linearGradient id="road-v" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1E2045" stopOpacity="0.9"/>
          <stop offset="0.5" stopColor="#252750" stopOpacity="1"/>
          <stop offset="1" stopColor="#1E2045" stopOpacity="0.9"/>
        </linearGradient>
      </defs>

      {/* base */}
      <rect width="100" height="100" fill="url(#grid)"/>

      {/* major horizontal roads */}
      <rect x="0" y="30" width="100" height="3.5" fill="url(#road-h)"/>
      <rect x="0" y="58" width="100" height="3" fill="url(#road-h)"/>

      {/* major vertical roads */}
      <rect x="19" y="0" width="3.5" height="100" fill="url(#road-v)"/>
      <rect x="45" y="0" width="3" height="100" fill="url(#road-v)"/>
      <rect x="72" y="0" width="3.5" height="100" fill="url(#road-v)"/>

      {/* secondary roads */}
      {[14, 44, 66, 82].map((y, i) => (
        <rect key={`h${i}`} x="0" y={y} width="100" height="1.5" fill="#1A1C3A" opacity="0.7"/>
      ))}
      {[8, 35, 60, 86].map((x, i) => (
        <rect key={`v${i}`} x={x} y="0" width="1.5" height="100" fill="#1A1C3A" opacity="0.7"/>
      ))}

      {/* road center lines (dashed) */}
      {[31.75, 59.5].map((y, i) => (
        Array.from({ length: 10 }).map((_, j) => (
          <rect key={`dl${i}${j}`} x={j * 11} y={y} width="5" height="0.4"
                fill="rgba(255,230,100,0.12)"/>
        ))
      ))}
      {[20.75, 46.5, 73.75].map((x, i) => (
        Array.from({ length: 10 }).map((_, j) => (
          <rect key={`dv${i}${j}`} x={x} y={j * 11} width="0.4" height="5"
                fill="rgba(255,230,100,0.12)"/>
        ))
      ))}

      {/* river / Tuul */}
      <path d="M 0 80 C 15 78, 25 84, 40 81 S 65 88, 85 82 L 100 83 L 100 100 L 0 100 Z"
            fill="#0E1835" opacity="0.85"/>
      <path d="M 0 80 C 15 78, 25 84, 40 81 S 65 88, 85 82 L 100 83"
            fill="none" stroke="#1A2E55" strokeWidth="0.6"/>

      {/* park / Sukhbaatar square area */}
      <rect x="41" y="26" width="8" height="7" rx="1" fill="#0F1F18" opacity="0.6"/>

      {/* road glow lines (main arteries) */}
      <rect x="0" y="30" width="100" height="3.5" fill="rgba(80,90,180,0.08)"/>
      <rect x="45" y="0" width="3" height="100" fill="rgba(80,90,180,0.08)"/>
    </svg>
  );
}

// ────────────────────────────────────────────────────────────
// 14 — BAR / VENUE PROFILE
// ────────────────────────────────────────────────────────────
function ScreenBar({ go, state, language }) {
  const [tab,      setTab]      = React.useState('photos');
  const [photoIdx, setPhotoIdx] = React.useState(0);

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '52px 12px 0',
      }}>
        <button style={iconBtn} onClick={() => go('map')}>
          <span style={{
            width: 36, height: 36, borderRadius: 18,
            background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(12px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="arrow-left" size={20}/>
          </span>
        </button>
        <div style={{ display: 'flex', gap: 6 }}>
          {['send', 'more'].map(n => (
            <button key={n} style={iconBtn}>
              <span style={{
                width: 36, height: 36, borderRadius: 18,
                background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(12px)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name={n} size={18}/>
              </span>
            </button>
          ))}
        </div>
      </div>

      <div className="ns-screen-scroll">
        <div style={{ position: 'relative', height: 280 }}>
          <Placeholder label="Vertigo Rooftop · hero" style={{ aspectRatio: 'auto', height: '100%' }}/>
          <div style={{
            position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, rgba(11,1,24,0.4) 0%, transparent 30%, rgba(11,1,24,0.95))',
          }}/>
          <div style={{
            position: 'absolute', bottom: 18, left: 0, right: 0,
            display: 'flex', justifyContent: 'center', gap: 6,
          }}>
            {[0, 1, 2, 3].map(i => (
              <span key={i} onClick={() => setPhotoIdx(i)} style={{
                width: photoIdx === i ? 18 : 6, height: 6, borderRadius: 3,
                background: photoIdx === i ? '#fff' : 'rgba(255,255,255,0.4)',
                cursor: 'pointer',
              }}/>
            ))}
          </div>
        </div>

        <div style={{ padding: '0 20px', marginTop: -60, position: 'relative', zIndex: 2 }}>
          <div className="ns-mono">LOUNGE · СҮХБААТАР</div>
          <h1 style={{
            margin: '6px 0 0', fontFamily: 'var(--ff-display)',
            fontSize: 32, fontWeight: 500, letterSpacing: '-0.02em', lineHeight: 1,
          }}>
            Vertigo<br/><span className="ns-grad-text" style={{ fontStyle: 'italic' }}>Rooftop</span>
          </h1>

          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 14 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <Stars value={4.8} size={14}/>
              <span style={{ fontSize: 14, fontWeight: 700 }}>4.8</span>
              <span style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>(312)</span>
            </span>
            <span style={{ width: 4, height: 4, borderRadius: 2, background: 'var(--text-tertiary)' }}/>
            <StatusBadge open/>
          </div>

          <TodayEvent language={language}/>

          <div className="ns-glass" style={{ marginTop: 16, padding: 16 }}>
            {[
              { icon: 'pin',   lKey: 'lbl.address', v: 'Сүхбаатарын талбай 5, 14-р давхар' },
              { icon: 'phone', lKey: 'lbl.phone',   v: '+976 7700 1234' },
              { icon: 'globe', lKey: 'lbl.hours',   v: 'Пүр-Бямба · 18:00 — 02:00' },
            ].map((r, i, arr) => (
              <div key={r.lKey} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 0',
                borderBottom: i < arr.length - 1 ? '1px solid var(--hairline)' : 'none',
              }}>
                <span style={{
                  width: 32, height: 32, borderRadius: 10,
                  background: 'rgba(255,77,141,0.1)', color: 'var(--accent-start)',
                  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Icon name={r.icon} size={16} stroke="currentColor"/>
                </span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="ns-mono">{tr(r.lKey, language)}</div>
                  <div style={{ fontSize: 13, marginTop: 2 }}>{r.v}</div>
                </div>
              </div>
            ))}
          </div>

          <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
            <button className="ns-btn-primary" style={{ flex: 1, height: 46 }}>
              <Icon name="compass" size={16} stroke="#1B0210" strokeWidth={2}/>
              {tr('btn.directions', language)}
            </button>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 46 }}>
              {tr('lbl.follow', language)}
            </button>
          </div>

          <div style={{
            display: 'flex', marginTop: 20,
            borderBottom: '1px solid var(--hairline)',
          }}>
            {[
              ['photos',  language === 'mn' ? 'Зураг'   : 'Photos'],
              ['reviews', language === 'mn' ? 'Үнэлгээ' : 'Reviews'],
              ['events',  language === 'mn' ? 'Эвент'   : 'Events'],
            ].map(([k, l]) => (
              <button key={k} onClick={() => setTab(k)} style={{
                flex: 1, padding: '12px 0', background: 'transparent', cursor: 'pointer',
                border: 0, borderBottom: tab === k ? '2px solid var(--accent-start)' : '2px solid transparent',
                color: tab === k ? 'var(--text-primary)' : 'var(--text-tertiary)',
                fontWeight: 600, fontSize: 13, letterSpacing: '0.04em',
              }}>{l}</button>
            ))}
          </div>
        </div>

        {tab === 'photos' && (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 4, padding: 4 }}>
            {Array.from({ length: 9 }).map((_, i) => (
              <Placeholder key={i} label={`vertigo #${i+1}`} style={{ aspectRatio: '1' }}/>
            ))}
          </div>
        )}
        {tab === 'reviews' && (
          <div style={{ padding: '14px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
            {[
              { u: '@solongo',   r: 5, t: 'Үзэмж шилдэг, cocktail-ийн меню урт. Live jazz баасан гарагт ⭐' },
              { u: '@bayar.dj',  r: 4, t: 'Үнэ нэлээд өндөр ч үйлчилгээ найрсаг.' },
              { u: '@odgerel',   r: 5, t: 'УБ-ын хамгийн дулаахан rooftop.' },
            ].map((rv, i) => (
              <div key={i} className="ns-glass" style={{ padding: 14 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <Avatar size={32} initial={rv.u[1].toUpperCase()}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 700, fontSize: 13 }}>{rv.u}</div>
                    <Stars value={rv.r} size={12}/>
                  </div>
                </div>
                <p style={{ margin: '8px 0 0', fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  {rv.t}
                </p>
              </div>
            ))}
          </div>
        )}
        {tab === 'events' && (
          <div style={{ padding: '14px 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[
              { d: '31', m: language === 'mn' ? 'тав' : 'May', t: 'Jazz night · trio',  by: 'House band' },
              { d: '07', m: language === 'mn' ? 'зур' : 'Jun', t: 'Cocktail tasting',   by: 'Mixology series' },
              { d: '14', m: language === 'mn' ? 'зур' : 'Jun', t: 'Vinyl Sunday',       by: 'DJ Ariunbold' },
            ].map((e, i) => (
              <div key={i} className="ns-glass" style={{ padding: 14, display: 'flex', gap: 14, alignItems: 'center' }}>
                <div style={{
                  width: 52, textAlign: 'center', padding: '8px 0',
                  borderRadius: 12, background: 'var(--bg-surface)',
                }}>
                  <div style={{ fontFamily: 'var(--ff-display)', fontSize: 22, fontWeight: 500 }}>{e.d}</div>
                  <div className="ns-mono">{e.m}</div>
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 700, fontSize: 14 }}>{e.t}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2 }}>{e.by}</div>
                </div>
                <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
              </div>
            ))}
          </div>
        )}
        <div style={{ height: 28 }}/>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 15 — CREATE POST
// ────────────────────────────────────────────────────────────
function ScreenCreate({ go, state, language }) {
  const [sel, setSel] = React.useState(0);
  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <div style={{
        flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '6px 12px 12px',
      }}>
        <button style={iconBtn} onClick={() => go('feed')}>
          <Icon name="close" size={22}/>
        </button>
        <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>
          {tr('lbl.newPost', language)}
        </div>
        <button onClick={() => go('feed')} style={{
          height: 36, padding: '0 18px', borderRadius: 9999,
          background: 'var(--accent-grad)', border: 0, color: '#1B0210',
          fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13,
          letterSpacing: '0.04em', textTransform: 'uppercase', cursor: 'pointer',
        }}>{tr('btn.post', language)}</button>
      </div>

      <div className="ns-screen-scroll">
        <div style={{ padding: '0 20px' }}>
          <div style={{ position: 'relative', borderRadius: 22, overflow: 'hidden' }}>
            <Placeholder label={tr('lbl.selectedPhoto', language)} style={{ aspectRatio: '1' }}/>
            <button style={{
              position: 'absolute', top: 12, right: 12,
              width: 32, height: 32, borderRadius: 16,
              background: 'rgba(11,1,24,0.6)', border: 0, cursor: 'pointer',
              color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon name="edit" size={14}/>
            </button>
          </div>
        </div>

        <div style={{ marginTop: 14, padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <span className="ns-mono">{tr('lbl.gallery', language)}</span>
            <button className="ns-btn-ghost" style={{ height: 28, padding: 0, fontSize: 12 }}>
              {tr('lbl.all', language)} <Icon name="chevron-down" size={12}/>
            </button>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 4 }}>
            <button onClick={() => {}} style={{
              aspectRatio: '1', borderRadius: 10,
              background: 'var(--bg-surface)', border: '1px solid var(--hairline)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
              color: 'var(--text-secondary)',
            }}>
              <Icon name="camera" size={22}/>
            </button>
            {Array.from({ length: 11 }).map((_, i) => (
              <button key={i} onClick={() => setSel(i)} style={{
                aspectRatio: '1', borderRadius: 10, padding: 0, border: 0,
                outline: sel === i ? '2px solid var(--accent-start)' : 'none',
                outlineOffset: 1, position: 'relative', cursor: 'pointer',
              }}>
                <Placeholder label={`#${i+1}`} style={{ aspectRatio: '1', borderRadius: 10 }}/>
                {sel === i && (
                  <span style={{
                    position: 'absolute', top: 6, right: 6,
                    width: 20, height: 20, borderRadius: 10,
                    background: 'var(--accent-grad)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: '#1B0210',
                  }}>
                    <Icon name="check" size={12} stroke="#1B0210" strokeWidth={2.5}/>
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>

        <div style={{ padding: '20px 20px 0' }}>
          <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>
            {tr('lbl.caption', language)}
          </label>
          <textarea className="ns-input" rows={3} placeholder={tr('ph.caption', language)}
            style={{ height: 'auto', paddingTop: 14, paddingBottom: 14, resize: 'none' }}/>
        </div>

        <div style={{ padding: '20px 20px 28px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {[
            { icon: 'pin',   lKey: 'lbl.addLocation', v: 'Vertigo Rooftop' },
            { icon: 'user',  lKey: 'lbl.tagPeople',   v: '@nara.ulaan +2' },
            { icon: 'music', lKey: 'lbl.addMusic',    v: '' },
          ].map((r, i, arr) => (
            <button key={r.lKey} style={{
              display: 'flex', alignItems: 'center', gap: 14,
              padding: '14px 0', background: 'transparent', border: 0, cursor: 'pointer',
              borderTop: '1px solid var(--hairline)',
              borderBottom: i === arr.length - 1 ? '1px solid var(--hairline)' : 'none',
              color: 'var(--text-primary)', textAlign: 'left',
            }}>
              <Icon name={r.icon} size={18} stroke="var(--text-secondary)"/>
              <span style={{ flex: 1, fontSize: 14 }}>{tr(r.lKey, language)}</span>
              {r.v && <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{r.v}</span>}
              <Icon name="chevron-right" size={16} stroke="var(--text-tertiary)"/>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenMap, ScreenBar, ScreenCreate });

// ─── TODAY'S EVENT card ───
function TodayEvent({ language }) {
  const [interested, setInterested] = React.useState(false);
  const [going,      setGoing]      = React.useState(false);
  const [shareOpen,  setShareOpen]  = React.useState(false);
  const [sentTo,     setSentTo]     = React.useState([]);
  const [copied,     setCopied]     = React.useState(false);

  const friends = [
    { initial: 'Н', name: 'Nara' },
    { initial: 'Б', name: 'Bayar' },
    { initial: 'С', name: 'Solongo' },
    { initial: 'О', name: 'Odgerel' },
    { initial: 'Э', name: 'Erden' },
  ];

  function toggleSend(name) { setSentTo(s => s.includes(name) ? s.filter(x => x !== name) : [...s, name]); }
  function copyLink() { setCopied(true); setTimeout(() => setCopied(false), 1400); }

  return (
    <div style={{
      marginTop: 16, position: 'relative', borderRadius: 22, overflow: 'hidden',
      border: '1px solid rgba(255,179,71,0.25)',
      background: 'linear-gradient(135deg, rgba(255,77,141,0.12) 0%, rgba(255,179,71,0.10) 100%), var(--bg-elevated)',
    }}>
      <div style={{
        position: 'absolute', top: -40, right: -40, width: 160, height: 160, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(255,77,141,0.28), transparent 65%)',
        filter: 'blur(20px)', pointerEvents: 'none',
      }}/>
      <div style={{ padding: '14px 16px 14px', position: 'relative' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 8px', borderRadius: 6,
            background: 'rgba(255,179,71,0.18)', color: 'var(--warning)',
            fontFamily: 'var(--ff-mono)', fontSize: 10, letterSpacing: '0.14em', fontWeight: 700,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: 'currentColor',
              boxShadow: '0 0 6px currentColor' }}/>
            {tr('lbl.todaysEvent', language)}
          </span>
          <span className="ns-mono" style={{ marginLeft: 'auto' }}>21:00 — 02:00</span>
        </div>

        <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginTop: 14 }}>
          <div style={{ width: 60, height: 60, flexShrink: 0, borderRadius: 14, overflow: 'hidden', border: '1px solid var(--hairline)' }}>
            <Placeholder label="event" style={{ aspectRatio: '1', borderRadius: 14 }}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h3 style={{ margin: 0, fontFamily: 'var(--ff-display)', fontStyle: 'italic',
              fontSize: 22, fontWeight: 500, letterSpacing: '-0.01em', lineHeight: 1.1 }}>
              Jazz trio · live
            </h3>
            <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 4,
              display: 'flex', alignItems: 'center', gap: 6 }}>
              <Icon name="music" size={12} stroke="currentColor"/>
              House band · ₮25,000 cover
            </div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 14,
          paddingTop: 12, borderTop: '1px solid var(--hairline)' }}>
          <div style={{ display: 'flex' }}>
            {['Н','Б','С','О'].map((c, i) => (
              <div key={i} style={{ marginLeft: i === 0 ? 0 : -8, borderRadius: '50%',
                border: '2px solid var(--bg-elevated)' }}>
                <Avatar size={24} initial={c}/>
              </div>
            ))}
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
            <span style={{ color: 'var(--text-primary)', fontWeight: 700 }}>87</span> {tr('lbl.going', language)} ·{' '}
            <span style={{ color: 'var(--text-primary)', fontWeight: 700 }}>142</span> {tr('lbl.interested', language)}
          </div>
        </div>

        <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
          <button onClick={() => setInterested(!interested)} style={{
            flex: 1, height: 44, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            padding: '0 14px', borderRadius: 9999,
            background: interested ? 'rgba(255,77,141,0.18)' : 'transparent',
            border: interested ? '1px solid rgba(255,77,141,0.4)' : '1px solid var(--hairline-2)',
            color: interested ? 'var(--accent-start)' : 'var(--text-primary)', cursor: 'pointer',
            fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13,
            letterSpacing: '0.04em', textTransform: 'uppercase', transition: 'all .15s ease',
          }}>
            <Icon name="star" size={16} filled={interested}
              stroke={interested ? 'var(--accent-start)' : 'currentColor'} strokeWidth={1.8}/>
            {tr('btn.interested', language)}
          </button>
          <button onClick={() => setGoing(!going)} style={{
            flex: 1, height: 44, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            padding: '0 14px', borderRadius: 9999,
            background: going ? 'var(--accent-grad)' : 'transparent',
            border: going ? 'none' : '1px solid var(--hairline-2)',
            color: going ? '#1B0210' : 'var(--text-primary)', cursor: 'pointer',
            fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13,
            letterSpacing: '0.04em', textTransform: 'uppercase',
            boxShadow: going ? '0 6px 20px rgba(255,77,141,0.32)' : 'none', transition: 'all .15s ease',
          }}>
            <Icon name="check" size={16} stroke={going ? '#1B0210' : 'currentColor'} strokeWidth={2.2}/>
            {going ? tr('btn.goingActive', language) : tr('btn.going', language)}
          </button>
          <button onClick={() => setShareOpen(s => !s)} style={{
            width: 44, height: 44, flexShrink: 0, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            borderRadius: 9999,
            background: shareOpen ? 'rgba(255,255,255,0.06)' : 'transparent',
            border: '1px solid var(--hairline-2)', color: 'var(--text-primary)', cursor: 'pointer',
          }}>
            <Icon name="share" size={18} stroke="currentColor" strokeWidth={1.8}/>
          </button>
        </div>

        {shareOpen && (
          <div style={{
            marginTop: 12, padding: 12, borderRadius: 16,
            background: 'rgba(255,255,255,0.03)', border: '1px solid var(--hairline)',
            animation: 'ns-share-in .22s ease both',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
              <span className="ns-mono" style={{ fontSize: 10, letterSpacing: '0.14em', color: 'var(--text-secondary)' }}>
                {tr('lbl.sendToFriends', language)}
              </span>
              <button onClick={() => setShareOpen(false)} style={{
                background: 'none', border: 'none', padding: 4,
                color: 'var(--text-secondary)', cursor: 'pointer',
              }}>
                <Icon name="close" size={14} stroke="currentColor" strokeWidth={1.8}/>
              </button>
            </div>
            <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 4 }}>
              {friends.map(f => {
                const sent = sentTo.includes(f.name);
                return (
                  <button key={f.name} onClick={() => toggleSend(f.name)} style={{
                    flexShrink: 0, width: 56, display: 'flex', flexDirection: 'column',
                    alignItems: 'center', gap: 6, padding: 0, background: 'none',
                    border: 'none', cursor: 'pointer', color: 'var(--text-primary)',
                  }}>
                    <div style={{ position: 'relative' }}>
                      <Avatar size={44} initial={f.initial}/>
                      {sent && (
                        <div style={{
                          position: 'absolute', inset: 0, borderRadius: '50%',
                          background: 'rgba(11,1,24,0.7)',
                          display: 'flex', alignItems: 'center', justifyContent: 'center',
                          border: '2px solid var(--accent-start)',
                        }}>
                          <Icon name="check" size={20} stroke="var(--accent-start)" strokeWidth={2.4}/>
                        </div>
                      )}
                    </div>
                    <span style={{ fontSize: 11, color: sent ? 'var(--accent-start)' : 'var(--text-secondary)' }}>
                      {sent ? tr('lbl.sent', language) : f.name}
                    </span>
                  </button>
                );
              })}
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6,
              marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--hairline)' }}>
              <button onClick={copyLink} style={{
                height: 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                borderRadius: 10,
                background: copied ? 'rgba(46,213,115,0.16)' : 'rgba(255,255,255,0.04)',
                border: '1px solid var(--hairline)',
                color: copied ? 'var(--success)' : 'var(--text-primary)',
                fontFamily: 'var(--ff-body)', fontSize: 11, fontWeight: 700,
                letterSpacing: '0.04em', textTransform: 'uppercase', cursor: 'pointer',
              }}>
                <Icon name={copied ? 'check' : 'globe'} size={14} stroke="currentColor" strokeWidth={1.8}/>
                {copied ? tr('lbl.copied', language) : tr('btn.copyLink', language)}
              </button>
              {['image', 'more'].map((ic, i) => (
                <button key={i} style={{
                  height: 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                  borderRadius: 10, background: 'rgba(255,255,255,0.04)',
                  border: '1px solid var(--hairline)', color: 'var(--text-primary)',
                  fontFamily: 'var(--ff-body)', fontSize: 11, fontWeight: 700,
                  letterSpacing: '0.04em', textTransform: 'uppercase', cursor: 'pointer',
                }}>
                  <Icon name={ic} size={14} stroke="currentColor" strokeWidth={1.8}/>
                  {i === 0 ? 'Story' : tr('btn.more', language)}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
