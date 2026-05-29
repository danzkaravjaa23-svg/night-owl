/* screens-map.jsx
   13 Map · 14 Bar Profile · 15 Create Post
*/

const BARS = [
  { id: 'v0', name: 'Sugar Lounge',      rating: 4.9, reviews: 612, dist: '0.2 км', open: true,  tag: 'Lounge',  x: 44, y: 38, featured: true, today: 'Live R&B нөөр' },
  { id: 'v1', name: 'Vertigo Rooftop',   rating: 4.8, reviews: 312, dist: '0.4 км', open: true,  tag: 'Lounge',  x: 32, y: 28, today: 'Jazz trio · 21:00' },
  { id: 'v2', name: 'Mass Club',          rating: 4.6, reviews: 528, dist: '1.1 км', open: true,  tag: 'Club',    x: 58, y: 18, today: 'DJ Bayar · vinyl set' },
  { id: 'v3', name: 'Brewery Praha',      rating: 4.4, reviews: 187, dist: '0.8 км', open: true,  tag: 'Pub',     x: 22, y: 56 },
  { id: 'v4', name: 'Element Lounge',     rating: 4.7, reviews: 244, dist: '1.6 км', open: false, tag: 'Lounge',  x: 70, y: 50 },
  { id: 'v5', name: 'Choco Metropolis',   rating: 4.5, reviews: 401, dist: '2.0 км', open: true,  tag: 'Club',    x: 48, y: 72, today: 'House night · 22:30' },
  { id: 'v6', name: 'Hops & Rocks',       rating: 4.2, reviews: 96,  dist: '2.4 км', open: false, tag: 'Pub',     x: 80, y: 78 },
];

const PEOPLE = [
  { id: 'u1', name: 'Bayarmaa DJ',  user: '@bayar.dj',     initial: 'Б', bio: 'Resident · Mass Club · House/Techno', dist: '0.5 км', followers: '8.4K', ring: true,  here: 'Mass Club' },
  { id: 'u2', name: 'Nara U',        user: '@nara.ulaan',    initial: 'Н', bio: 'Live music · vinyl collector',          dist: '0.7 км', followers: '2.1K', ring: true,  here: 'Vertigo Rooftop' },
  { id: 'u3', name: 'Solongo',       user: '@solongo',       initial: 'С', bio: 'Cocktail tasting · mixology',          dist: '1.2 км', followers: '4.6K', ring: true,  here: 'Sugar Lounge' },
  { id: 'u4', name: 'Odgerel',       user: '@odgerel',       initial: 'О', bio: 'Pub culture · craft beer',            dist: '1.8 км', followers: '980' },
  { id: 'u5', name: 'Erden DJ',      user: '@erden_dj',      initial: 'Э', bio: 'Techno · UB underground',              dist: '2.1 км', followers: '5.2K', ring: true },
  { id: 'u6', name: 'Enkhjin',       user: '@enkh_94',       initial: 'Е', bio: 'Lounge, jazz, slow drinks',           dist: '2.6 км', followers: '1.4K' },
];

// ────────────────────────────────────────────────────────────
// 13 — MAP  (Places / People toggle, vertical list, Sugar Lounge first)
// ────────────────────────────────────────────────────────────
function ScreenMap({ go, state }) {
  const [mode, setMode]     = React.useState('places'); // places | people
  const [filter, setFilter] = React.useState('all');
  const visible = mode !== 'places' ? [] :
    (filter === 'all' ? BARS : BARS.filter(b =>
      filter === 'open' ? b.open : b.tag.toLowerCase() === filter));

  return (
    <div className="ns-screen" style={{ background: 'var(--bg-base)' }}>
      <PhoneStatus/>

      {/* MAP TOP HALF — fixed area so the list sheet has room below */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 380,
        background: `
          radial-gradient(circle at 30% 25%, rgba(123,47,247,0.15), transparent 35%),
          radial-gradient(circle at 70% 70%, rgba(255,77,141,0.12), transparent 38%),
          linear-gradient(180deg, #08021C 0%, #0B0118 100%)
        `,
        overflow: 'hidden',
      }}>
        <MapStreets/>
        {state !== 'loading' && state !== 'error' && state !== 'empty' && mode === 'places' && visible.map(b => (
          <button key={b.id} onClick={() => go('bar')} style={{
            position: 'absolute',
            left: `${b.x}%`, top: `${b.y}%`,
            transform: 'translate(-50%, -100%)',
            background: 'transparent', border: 0, cursor: 'pointer',
            zIndex: 5,
          }}>
            <MapPin label={b.name.split(' ')[0]} hot={b.featured || b.rating >= 4.8} open={b.open}/>
          </button>
        ))}
        {state !== 'loading' && state !== 'error' && mode === 'people' && PEOPLE.filter(p => p.here).map((p, i) => (
          <button key={p.id} onClick={() => go('creator')} style={{
            position: 'absolute',
            left: `${30 + i * 18}%`, top: `${28 + i * 14}%`,
            transform: 'translate(-50%, -100%)',
            background: 'transparent', border: 0, cursor: 'pointer',
            zIndex: 5,
          }}>
            <PersonPin name={p.user} initial={p.initial}/>
          </button>
        ))}
        {/* user location */}
        <div style={{
          position: 'absolute', left: '50%', top: '65%',
          transform: 'translate(-50%, -50%)',
        }}>
          <div style={{
            width: 60, height: 60, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(92,123,255,0.4), transparent 70%)',
            position: 'absolute', inset: -20,
          }}/>
          <div style={{
            width: 18, height: 18, borderRadius: '50%',
            background: '#5C7BFF',
            border: '3px solid #fff',
            boxShadow: '0 0 0 1px rgba(0,0,0,0.4), 0 0 12px rgba(92,123,255,0.6)',
          }}/>
        </div>
      </div>

      {/* search + filters (overlaid on map) */}
      <div style={{
        position: 'relative', zIndex: 10,
        padding: '6px 16px 0',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '10px 14px', borderRadius: 9999,
          background: 'rgba(26,11,46,0.85)', backdropFilter: 'blur(16px)',
          border: '1px solid rgba(255,255,255,0.08)',
        }}>
          <Icon name="search" size={18} stroke="rgba(255,255,255,0.7)"/>
          <input placeholder={mode === 'places' ? 'Bar, lounge хайх' : 'Хүн хайх'}
            style={{
              flex: 1, background: 'transparent', border: 0, outline: 0,
              color: '#fff', fontSize: 14,
            }}/>
          <span style={{ fontFamily: 'var(--ff-mono)', fontSize: 10, letterSpacing: '0.14em',
                color: 'rgba(255,255,255,0.5)' }}>UB</span>
        </div>

        {/* Places / People segmented toggle */}
        <div style={{
          display: 'flex', marginTop: 12, padding: 4,
          background: 'rgba(11,1,24,0.6)', backdropFilter: 'blur(12px)',
          borderRadius: 9999,
          border: '1px solid rgba(255,255,255,0.06)',
          width: 'fit-content',
        }}>
          {[
            { k: 'places', l: 'Газар', icon: 'pin' },
            { k: 'people', l: 'Хүмүүс', icon: 'user' },
          ].map(seg => {
            const on = mode === seg.k;
            return (
              <button key={seg.k} onClick={() => setMode(seg.k)} style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '8px 16px', borderRadius: 9999,
                background: on ? 'var(--accent-grad)' : 'transparent',
                border: 0, cursor: 'pointer',
                color: on ? '#1B0210' : 'rgba(255,255,255,0.85)',
                fontFamily: 'var(--ff-body)', fontWeight: on ? 700 : 500,
                fontSize: 13, letterSpacing: '0.02em',
              }}>
                <Icon name={seg.icon} size={14} stroke={on ? '#1B0210' : 'currentColor'} strokeWidth={2}/>
                {seg.l}
              </button>
            );
          })}
        </div>

        {mode === 'places' && (
          <div style={{
            display: 'flex', gap: 8, overflowX: 'auto', padding: '12px 0 0',
            scrollbarWidth: 'none',
          }}>
            {[
              { k: 'all',     l: 'Бүгд' },
              { k: 'open',    l: 'Нээлттэй' },
              { k: 'club',    l: 'Club' },
              { k: 'lounge',  l: 'Lounge' },
              { k: 'pub',     l: 'Pub' },
              { k: 'music',   l: 'Live music' },
            ].map(f => (
              <span key={f.k} className={`ns-chip ${filter === f.k ? 'is-on' : ''}`}
                    onClick={() => setFilter(f.k)}
                    style={{ flexShrink: 0, background: filter === f.k ? '' : 'rgba(26,11,46,0.85)',
                      color: filter === f.k ? '#1B0210' : 'rgba(255,255,255,0.85)',
                      borderColor: filter === f.k ? 'transparent' : 'rgba(255,255,255,0.08)' }}>
                {f.l}
              </span>
            ))}
          </div>
        )}
      </div>

      <div style={{ flex: 1 }}/>

      {/* bottom sheet — tall vertical list */}
      <div style={{
        position: 'relative', zIndex: 10,
        background: 'var(--bg-elevated)',
        borderRadius: '24px 24px 0 0',
        border: '1px solid var(--hairline)', borderBottom: 0,
        paddingTop: 10,
        boxShadow: '0 -16px 40px rgba(0,0,0,0.5)',
        height: 440,
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{
          width: 36, height: 4, borderRadius: 4,
          background: 'rgba(255,255,255,0.18)', margin: '0 auto 12px',
          flexShrink: 0,
        }}/>
        <div style={{ padding: '0 20px 12px', display: 'flex', justifyContent: 'space-between',
              alignItems: 'baseline', flexShrink: 0 }}>
          <div className="ns-mono">
            {mode === 'places' ? `ОЙРХОН ГАЗАР · ${visible.length}` : `ОЙРХОН ХҮМҮҮС · ${PEOPLE.length}`}
          </div>
          <button className="ns-btn-ghost" style={{ height: 24, padding: 0, fontSize: 12 }}>
            Эрэмбэлэх <Icon name="chevron-down" size={12} stroke="var(--text-secondary)"/>
          </button>
        </div>

        {state === 'loading' ? (
          <div style={{ padding: '0 20px 22px', display: 'flex', flexDirection: 'column', gap: 10 }}>
            {[1,2,3].map(i => <Skel key={i} w="100%" h={72} r={14}/>)}
          </div>
        ) : state === 'empty' || (mode === 'places' && visible.length === 0) ? (
          <div style={{ padding: '24px 20px 28px', textAlign: 'center',
                color: 'var(--text-tertiary)', fontSize: 13 }}>
            {mode === 'places' ? 'Ойролцоо газар олдсонгүй.' : 'Ойролцоо хүн олдсонгүй.'}
          </div>
        ) : mode === 'places' ? (
          <div className="ns-screen-scroll" style={{ padding: '0 16px 16px' }}>
            {visible.map(b => <PlaceRow key={b.id} b={b} go={go}/>)}
          </div>
        ) : (
          <div className="ns-screen-scroll" style={{ padding: '0 16px 16px' }}>
            {PEOPLE.map(p => <PersonRow key={p.id} p={p} go={go}/>)}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Place row (vertical card) ───
function PlaceRow({ b, go }) {
  return (
    <button onClick={() => go('bar')} style={{
      width: '100%',
      display: 'flex', gap: 12, alignItems: 'stretch',
      padding: 10, marginBottom: 8,
      background: b.featured ? 'var(--accent-grad-soft)' : 'transparent',
      border: b.featured ? '1px solid rgba(255,77,141,0.22)' : '1px solid var(--hairline)',
      borderRadius: 16, cursor: 'pointer',
      color: 'var(--text-primary)', textAlign: 'left',
    }}>
      <div style={{ width: 86, height: 86, flexShrink: 0, borderRadius: 12, overflow: 'hidden' }}>
        <Placeholder label={b.name} style={{ aspectRatio: '1', borderRadius: 12 }}/>
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6, justifyContent: 'space-between' }}>
            <div style={{ minWidth: 0 }}>
              {b.featured && (
                <div className="ns-mono" style={{
                  color: 'var(--accent-start)', marginBottom: 3,
                }}>★ FEATURED</div>
              )}
              <div style={{ fontWeight: 700, fontSize: 14, lineHeight: 1.2,
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {b.name}
              </div>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 6, marginTop: 3,
                fontSize: 11, color: 'var(--text-secondary)',
              }}>
                <Stars value={b.rating} size={11}/>
                <span style={{ fontWeight: 600 }}>{b.rating}</span>
                <span style={{ opacity: 0.5 }}>·</span>
                <span>{b.tag}</span>
                <span style={{ opacity: 0.5 }}>·</span>
                <span>{b.dist}</span>
              </div>
            </div>
            <StatusBadge open={b.open}/>
          </div>
        </div>
        {b.today && (
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 8px', borderRadius: 8, alignSelf: 'flex-start',
            background: 'rgba(255,179,71,0.12)',
            border: '1px solid rgba(255,179,71,0.2)',
            color: 'var(--warning)', fontSize: 11, fontWeight: 600, marginTop: 6,
          }}>
            <Icon name="ticket" size={11} stroke="currentColor"/>
            ӨНӨӨ · {b.today}
          </div>
        )}
      </div>
    </button>
  );
}

// ─── Person row ───
function PersonRow({ p, go }) {
  return (
    <button onClick={() => go('creator')} style={{
      width: '100%',
      display: 'flex', gap: 12, alignItems: 'center',
      padding: 10, marginBottom: 4,
      background: 'transparent', border: 0,
      borderBottom: '1px solid var(--hairline)',
      borderRadius: '20%', cursor: 'pointer',
      color: 'var(--text-primary)', textAlign: 'left',
    }}>
      <Avatar size={50} initial={p.initial} ring={p.ring}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 14, letterSpacing: '0.01em' }}>{p.name}</div>
        <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
              letterSpacing: '0.02em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {p.user} · {p.bio}
        </div>
        {p.here ? (
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 4, marginTop: 4,
            fontSize: 11, color: 'var(--success)', fontWeight: 600,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: 'currentColor',
              boxShadow: '0 0 6px currentColor' }}/>
            Одоо {p.here}-д
          </div>
        ) : (
          <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 4 }}>
            {p.dist} · {p.followers} дагагч
          </div>
        )}
      </div>
      <span style={{
        padding: '7px 14px', borderRadius: 9999,
        background: 'var(--accent-grad)', border: 0,
        color: '#1B0210', fontSize: 12, fontWeight: 700,
        letterSpacing: '0.03em',
      }}>Дагах</span>
    </button>
  );
}

// ─── PersonPin (for map dots in people mode) ───
function PersonPin({ name, initial }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
      <span style={{
        padding: '3px 8px', borderRadius: 9999,
        background: 'rgba(11,1,24,0.75)', backdropFilter: 'blur(8px)',
        border: '1px solid rgba(255,255,255,0.08)',
        fontSize: 10, fontWeight: 700, color: '#fff', whiteSpace: 'nowrap',
      }}>{name}</span>
      <span style={{ position: 'relative' }}>
        <span style={{
          position: 'absolute', inset: -6, borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(92,123,255,0.4), transparent 65%)',
          filter: 'blur(2px)',
        }}/>
        <span style={{
          width: 34, height: 34, borderRadius: '50%',
          padding: 2, background: 'var(--accent-grad)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative',
        }}>
          <span style={{
            width: '100%', height: '100%', borderRadius: '50%',
            background: '#0B0118',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontWeight: 700, fontSize: 13,
          }}>{initial}</span>
        </span>
      </span>
    </div>
  );
}

// abstract street network — never use complex SVG; this is geometric grid
function MapStreets() {
  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="none"
         style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: 0.5 }}>
      <defs>
        <linearGradient id="street-g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="rgba(255,255,255,0.08)"/>
          <stop offset="1" stopColor="rgba(255,255,255,0.02)"/>
        </linearGradient>
      </defs>
      {/* major roads */}
      <line x1="0" y1="32" x2="100" y2="38" stroke="rgba(255,255,255,0.16)" strokeWidth="1.2"/>
      <line x1="0" y1="62" x2="100" y2="58" stroke="rgba(255,255,255,0.16)" strokeWidth="1.2"/>
      <line x1="20" y1="0" x2="22" y2="100" stroke="rgba(255,255,255,0.14)" strokeWidth="1"/>
      <line x1="46" y1="0" x2="48" y2="100" stroke="rgba(255,255,255,0.16)" strokeWidth="1.2"/>
      <line x1="74" y1="0" x2="72" y2="100" stroke="rgba(255,255,255,0.14)" strokeWidth="1"/>
      {/* minor */}
      {[12, 22, 42, 52, 78, 88].map((y, i) =>
        <line key={i} x1="0" y1={y} x2="100" y2={y + (i%2?1:-1)*0.5} stroke="rgba(255,255,255,0.06)" strokeWidth="0.5"/>
      )}
      {[8, 32, 60, 84, 92].map((x, i) =>
        <line key={i} x1={x} y1="0" x2={x + (i%2?-1:1)} y2="100" stroke="rgba(255,255,255,0.06)" strokeWidth="0.5"/>
      )}
      {/* river */}
      <path d="M 0 78 C 20 76, 30 84, 50 80 S 80 88, 100 82 L 100 100 L 0 100 Z"
            fill="rgba(123,47,247,0.06)"/>
    </svg>
  );
}

function MapPin({ label, hot, open }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
      <span style={{
        padding: '4px 8px', borderRadius: 9999,
        background: 'rgba(11,1,24,0.75)', backdropFilter: 'blur(8px)',
        border: '1px solid var(--hairline)',
        fontSize: 10, fontWeight: 700, letterSpacing: '0.04em',
        color: open ? '#fff' : 'var(--text-tertiary)',
        whiteSpace: 'nowrap',
      }}>{label}</span>
      <span style={{ position: 'relative' }}>
        <span style={{
          position: 'absolute', inset: -8, borderRadius: '50%',
          background: hot ? 'radial-gradient(circle, rgba(255,77,141,0.5), transparent 65%)' : 'transparent',
          filter: 'blur(4px)',
        }}/>
        <span style={{
          width: 26, height: 26, borderRadius: '50%',
          background: hot ? 'var(--accent-grad)' :
                     open ? 'rgba(255,255,255,0.85)' : 'rgba(110,94,138,0.6)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          color: '#1B0210', position: 'relative',
          boxShadow: '0 4px 12px rgba(0,0,0,0.5), inset 0 -2px 0 rgba(0,0,0,0.15)',
        }}>
          <Icon name="music" size={12} stroke="#1B0210" strokeWidth={2.2}/>
        </span>
        <span style={{
          position: 'absolute', left: '50%', bottom: -4, transform: 'translateX(-50%)',
          width: 6, height: 6, borderRadius: '50%',
          background: 'rgba(0,0,0,0.5)', filter: 'blur(2px)',
        }}/>
      </span>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 14 — BAR / VENUE PROFILE
// ────────────────────────────────────────────────────────────
function ScreenBar({ go, state }) {
  const [tab, setTab] = React.useState('photos');
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
        {/* hero carousel */}
        <div style={{ position: 'relative', height: 280 }}>
          <Placeholder label="Vertigo Rooftop · hero" style={{ aspectRatio: 'auto', height: '100%' }}/>
          <div style={{
            position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, rgba(11,1,24,0.4) 0%, transparent 30%, rgba(11,1,24,0.95))',
          }}/>
          {/* carousel dots */}
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

        {/* main */}
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

          {/* TODAY'S EVENT — prominent card with Interested / Going */}
          <TodayEvent/>

          {/* info card */}
          <div className="ns-glass" style={{ marginTop: 16, padding: 16 }}>
            {[
              { icon: 'pin',   l: 'Хаяг',  v: 'Сүхбаатарын талбай 5, 14-р давхар' },
              { icon: 'phone', l: 'Утас',  v: '+976 7700 1234' },
              { icon: 'globe', l: 'Цаг',   v: 'Пүр-Бямба · 18:00 — 02:00' },
            ].map((r, i, arr) => (
              <div key={r.l} style={{
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
                  <div className="ns-mono">{r.l}</div>
                  <div style={{ fontSize: 13, marginTop: 2 }}>{r.v}</div>
                </div>
              </div>
            ))}
          </div>

          {/* actions */}
          <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
            <button className="ns-btn-primary" style={{ flex: 1, height: 46 }}>
              <Icon name="compass" size={16} stroke="#1B0210" strokeWidth={2}/>
              Чиглэл авах
            </button>
            <button className="ns-btn-secondary" style={{ flex: 1, height: 46 }}>
              Дагах
            </button>
          </div>

          {/* tabs */}
          <div style={{
            display: 'flex', marginTop: 20,
            borderBottom: '1px solid var(--hairline)',
          }}>
            {[['photos', 'Зураг'], ['reviews', 'Үнэлгээ'], ['events', 'Эвент']].map(([k, l]) => (
              <button key={k} onClick={() => setTab(k)} style={{
                flex: 1, padding: '12px 0', background: 'transparent', cursor: 'pointer',
                border: 0, borderBottom: tab === k ? '2px solid var(--accent-start)' : '2px solid transparent',
                color: tab === k ? 'var(--text-primary)' : 'var(--text-tertiary)',
                fontWeight: 600, fontSize: 13, letterSpacing: '0.04em',
              }}>{l}</button>
            ))}
          </div>
        </div>

        {/* tab content */}
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
              { d: '31',  m: 'тав',   t: 'Jazz night · trio',     by: 'House band' },
              { d: '07',  m: 'зур',   t: 'Cocktail tasting',      by: 'Mixology series' },
              { d: '14',  m: 'зур',   t: 'Vinyl Sunday',          by: 'DJ Ariunbold' },
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
function ScreenCreate({ go, state }) {
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
          Шинэ нийтлэл
        </div>
        <button onClick={() => go('feed')} style={{
          height: 36, padding: '0 18px', borderRadius: 9999,
          background: 'var(--accent-grad)', border: 0, color: '#1B0210',
          fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13, letterSpacing: '0.04em',
          textTransform: 'uppercase', cursor: 'pointer',
        }}>Нийтлэх</button>
      </div>

      <div className="ns-screen-scroll">
        {/* selected preview */}
        <div style={{ padding: '0 20px' }}>
          <div style={{ position: 'relative', borderRadius: 22, overflow: 'hidden' }}>
            <Placeholder label="Сонгосон зураг" style={{ aspectRatio: '1' }}/>
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

        {/* gallery picker */}
        <div style={{ marginTop: 14, padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
            <span className="ns-mono">ГАЛЕРЕЙ</span>
            <button className="ns-btn-ghost" style={{ height: 28, padding: 0, fontSize: 12 }}>
              Бүгд <Icon name="chevron-down" size={12}/>
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

        {/* caption */}
        <div style={{ padding: '20px 20px 0' }}>
          <label className="ns-mono" style={{ marginBottom: 8, display: 'block' }}>ТАЙЛБАР</label>
          <textarea className="ns-input" rows={3} placeholder="Энэ шөнө юу болов?..."
            style={{ height: 'auto', paddingTop: 14, paddingBottom: 14, resize: 'none' }}/>
        </div>

        {/* meta rows */}
        <div style={{ padding: '20px 20px 28px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {[
            { icon: 'pin',  l: 'Байршил нэмэх',  v: 'Vertigo Rooftop' },
            { icon: 'user', l: 'Хүмүүс таглах', v: '@nara.ulaan +2' },
            { icon: 'music', l: 'Дуу нэмэх',     v: '' },
          ].map((r, i, arr) => (
            <button key={r.l} style={{
              display: 'flex', alignItems: 'center', gap: 14,
              padding: '14px 0', background: 'transparent', border: 0, cursor: 'pointer',
              borderTop: '1px solid var(--hairline)',
              borderBottom: i === arr.length - 1 ? '1px solid var(--hairline)' : 'none',
              color: 'var(--text-primary)', textAlign: 'left',
            }}>
              <Icon name={r.icon} size={18} stroke="var(--text-secondary)"/>
              <span style={{ flex: 1, fontSize: 14 }}>{r.l}</span>
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

// ─── TODAY'S EVENT card (on bar profile) ───
function TodayEvent() {
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

  function toggleSend(name) {
    setSentTo(s => s.includes(name) ? s.filter(x => x !== name) : [...s, name]);
  }
  function copyLink() {
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  }

  return (
    <div style={{
      marginTop: 16,
      position: 'relative',
      borderRadius: 22,
      overflow: 'hidden',
      border: '1px solid rgba(255,179,71,0.25)',
      background: `
        linear-gradient(135deg, rgba(255,77,141,0.12) 0%, rgba(255,179,71,0.10) 100%),
        var(--bg-elevated)
      `,
    }}>
      {/* glow accent */}
      <div style={{
        position: 'absolute', top: -40, right: -40,
        width: 160, height: 160, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(255,77,141,0.28), transparent 65%)',
        filter: 'blur(20px)',
        pointerEvents: 'none',
      }}/>

      <div style={{ padding: '14px 16px 14px', position: 'relative' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            padding: '4px 8px', borderRadius: 6,
            background: 'rgba(255,179,71,0.18)',
            color: 'var(--warning)',
            fontFamily: 'var(--ff-mono)', fontSize: 10,
            letterSpacing: '0.14em', fontWeight: 700,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: 'currentColor',
              boxShadow: '0 0 6px currentColor' }}/>
            ӨНӨӨДРИЙН ЭВЕНТ
          </span>
          <span className="ns-mono" style={{ marginLeft: 'auto' }}>21:00 — 02:00</span>
        </div>

        <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginTop: 14 }}>
          <div style={{
            width: 60, height: 60, flexShrink: 0,
            borderRadius: 14, overflow: 'hidden',
            border: '1px solid var(--hairline)',
          }}>
            <Placeholder label="event" style={{ aspectRatio: '1', borderRadius: 14 }}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h3 style={{
              margin: 0, fontFamily: 'var(--ff-display)', fontStyle: 'italic',
              fontSize: 22, fontWeight: 500, letterSpacing: '-0.01em', lineHeight: 1.1,
            }}>
              Jazz trio · live
            </h3>
            <div style={{
              fontSize: 12, color: 'var(--text-secondary)', marginTop: 4,
              display: 'flex', alignItems: 'center', gap: 6,
            }}>
              <Icon name="music" size={12} stroke="currentColor"/>
              House band · ₮25,000 cover
            </div>
          </div>
        </div>

        {/* attendees */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 12,
          marginTop: 14, paddingTop: 12,
          borderTop: '1px solid var(--hairline)',
        }}>
          <div style={{ display: 'flex' }}>
            {['Н', 'Б', 'С', 'О'].map((c, i) => (
              <div key={i} style={{
                marginLeft: i === 0 ? 0 : -8,
                borderRadius: '50%',
                border: '2px solid var(--bg-elevated)',
              }}>
                <Avatar size={24} initial={c}/>
              </div>
            ))}
          </div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
            <span style={{ color: 'var(--text-primary)', fontWeight: 700 }}>87</span> ирэх ·{' '}
            <span style={{ color: 'var(--text-primary)', fontWeight: 700 }}>142</span> сонирхсон
          </div>
        </div>

        {/* CTA buttons — Interested + Going + Share */}
        <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
          <button onClick={() => setInterested(!interested)} style={{
            flex: 1, height: 44,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            padding: '0 14px',
            borderRadius: 9999,
            background: interested ? 'rgba(255,77,141,0.18)' : 'transparent',
            border: interested ? '1px solid rgba(255,77,141,0.4)' : '1px solid var(--hairline-2)',
            color: interested ? 'var(--accent-start)' : 'var(--text-primary)',
            cursor: 'pointer',
            fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13,
            letterSpacing: '0.04em', textTransform: 'uppercase',
            transition: 'all .15s ease',
          }}>
            <Icon name="star" size={16} filled={interested}
              stroke={interested ? 'var(--accent-start)' : 'currentColor'} strokeWidth={1.8}/>
            Сонирхолтой
          </button>
          <button onClick={() => setGoing(!going)} style={{
            flex: 1, height: 44,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
            padding: '0 14px',
            borderRadius: 9999,
            background: going ? 'var(--accent-grad)' : 'transparent',
            border: going ? 'none' : '1px solid var(--hairline-2)',
            color: going ? '#1B0210' : 'var(--text-primary)',
            cursor: 'pointer',
            fontFamily: 'var(--ff-body)', fontWeight: 700, fontSize: 13,
            letterSpacing: '0.04em', textTransform: 'uppercase',
            boxShadow: going ? '0 6px 20px rgba(255,77,141,0.32)' : 'none',
            transition: 'all .15s ease',
          }}>
            <Icon name="check" size={16}
              stroke={going ? '#1B0210' : 'currentColor'} strokeWidth={2.2}/>
            {going ? 'Очно' : 'Очих'}
          </button>
          <button onClick={() => setShareOpen(s => !s)} aria-label="Найзууддаа хуваалцах" style={{
            width: 44, height: 44, flexShrink: 0,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            borderRadius: 9999,
            background: shareOpen ? 'rgba(255,255,255,0.06)' : 'transparent',
            border: '1px solid var(--hairline-2)',
            color: 'var(--text-primary)',
            cursor: 'pointer',
            transition: 'all .15s ease',
          }}>
            <Icon name="share" size={18} stroke="currentColor" strokeWidth={1.8}/>
          </button>
        </div>

        {/* Share sheet — friends + link */}
        {shareOpen && (
          <div style={{
            marginTop: 12, padding: 12,
            borderRadius: 16,
            background: 'rgba(255,255,255,0.03)',
            border: '1px solid var(--hairline)',
            animation: 'ns-share-in .22s ease both',
          }}>
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              marginBottom: 10,
            }}>
              <span className="ns-mono" style={{ fontSize: 10, letterSpacing: '0.14em', color: 'var(--text-secondary)' }}>
                НАЙЗУУДДАА ИЛГЭЭХ
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
                    flexShrink: 0, width: 56,
                    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
                    padding: 0, background: 'none', border: 'none', cursor: 'pointer',
                    color: 'var(--text-primary)',
                  }}>
                    <div style={{ position: 'relative' }}>
                      <Avatar size={44} initial={f.initial}/>
                      {sent && (
                        <div style={{
                          position: 'absolute', inset: 0,
                          borderRadius: '50%',
                          background: 'rgba(11,1,24,0.7)',
                          display: 'flex', alignItems: 'center', justifyContent: 'center',
                          border: '2px solid var(--accent-start)',
                        }}>
                          <Icon name="check" size={20} stroke="var(--accent-start)" strokeWidth={2.4}/>
                        </div>
                      )}
                    </div>
                    <span style={{ fontSize: 11, color: sent ? 'var(--accent-start)' : 'var(--text-secondary)' }}>
                      {sent ? 'Илгээв' : f.name}
                    </span>
                  </button>
                );
              })}
            </div>

            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6,
              marginTop: 12, paddingTop: 12,
              borderTop: '1px solid var(--hairline)',
            }}>
              <button onClick={copyLink} style={{
                height: 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                borderRadius: 10,
                background: copied ? 'rgba(46,213,115,0.16)' : 'rgba(255,255,255,0.04)',
                border: '1px solid var(--hairline)',
                color: copied ? 'var(--success)' : 'var(--text-primary)',
                fontFamily: 'var(--ff-body)', fontSize: 11, fontWeight: 700,
                letterSpacing: '0.04em', textTransform: 'uppercase',
                cursor: 'pointer', transition: 'all .15s ease',
              }}>
                <Icon name={copied ? 'check' : 'globe'} size={14} stroke="currentColor" strokeWidth={1.8}/>
                {copied ? 'Хуулав' : 'Линк'}
              </button>
              <button style={{
                height: 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                borderRadius: 10,
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid var(--hairline)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--ff-body)', fontSize: 11, fontWeight: 700,
                letterSpacing: '0.04em', textTransform: 'uppercase',
                cursor: 'pointer',
              }}>
                <Icon name="image" size={14} stroke="currentColor" strokeWidth={1.8}/>
                Story
              </button>
              <button style={{
                height: 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                borderRadius: 10,
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid var(--hairline)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--ff-body)', fontSize: 11, fontWeight: 700,
                letterSpacing: '0.04em', textTransform: 'uppercase',
                cursor: 'pointer',
              }}>
                <Icon name="more" size={14} stroke="currentColor" strokeWidth={1.8}/>
                Бусад
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
