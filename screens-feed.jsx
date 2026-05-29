/* screens-feed.jsx
   09 Feed (3 variations) · 10 Post Detail · 11 Creator + Paid · 12 QPay
*/

// shared sample content — real-ish UB venues
const FEED_POSTS = [
  { id: 'p1', user: '@nara.ulaan',   venue: 'Vertigo Rooftop',    location: 'Сүхбаатар дүүрэг',
    likes: 1284, caption: 'Live jazz, шар будааны бороо. Энэ долоо хоногийн хамгийн дулаахан үдэш.', tag: 'live music', initial: 'Н' },
  { id: 'p2', user: '@bayar.dj',     venue: 'Mass Club',          location: 'Чингэлтэй дүүрэг',
    likes: 3420, caption: 'Шинэ set, шинэ толгой. Бямба гарагт уулзъя 🎧', tag: 'dj set', initial: 'Б' },
  { id: 'p3', user: '@odgerel',      venue: 'Brewery Praha',      location: 'Баянгол дүүрэг',
    likes: 642,  caption: 'Хар шар, ширэм халуун. Хүйтнээс зугтахын аргагүй.', tag: 'pub', initial: 'О' },
  { id: 'p4', user: '@solongo',      venue: 'Element Lounge',     location: 'Хан-Уул дүүрэг',
    likes: 988,  caption: 'Cocktail tasting шөнө — гүн ягаан, дижитал гэрэл.', tag: 'cocktail', initial: 'С' },
];

// ────────────────────────────────────────────────────────────
// 09 — FEED (with three visual variants via tweak)
// ────────────────────────────────────────────────────────────
function ScreenFeed({ go, state, variant = 'editorial', accent }) {
  return (
    <div className="ns-screen">
      {/* top bar */}
      <PhoneStatus/>
      <FeedTopBar go={go}/>

      {state === 'loading' ? (
        <div className="ns-screen-scroll" style={{ padding: '0 20px' }}>
          {[1, 2].map(i => (
            <div key={i} style={{ padding: '12px 0 20px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
                <Skel w={36} h={36} r={18}/>
                <div style={{ flex: 1 }}>
                  <Skel w="50%" h={11}/>
                  <div style={{ height: 6 }}/>
                  <Skel w="30%" h={9}/>
                </div>
              </div>
              <Skel w="100%" h={360} r={20}/>
              <div style={{ height: 12 }}/>
              <Skel w="80%" h={13}/>
            </div>
          ))}
        </div>
      ) : state === 'empty' ? (
        <EmptyState
          icon="sparkles"
          title="Тэжээл хоосон байна"
          body="Хэн нэгнийг дага эсвэл эхний зургаа оруулаад тэжээлээ дүүргэж эхэл."
          action={
            <button className="ns-btn-primary" onClick={() => go('post')}>
              <Icon name="plus" size={18} stroke="#1B0210" strokeWidth={2.2}/>
              Зураг оруулах
            </button>
          }
        />
      ) : state === 'error' ? (
        <ErrorState onRetry={() => go('feed')}/>
      ) : variant === 'magazine' ? (
        <FeedMagazine go={go}/>
      ) : variant === 'minimal' ? (
        <FeedMinimal go={go}/>
      ) : (
        <FeedEditorial go={go}/>
      )}
    </div>
  );
}

function FeedTopBar({ go }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 20px 12px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <OwlMark size={36} glow={false} slotId="feed-logo"/>
        <div>
          <div style={{ fontFamily: 'var(--ff-display)', fontSize: 22, lineHeight: 1, fontWeight: 800 }}>
            Шөнийн<span style={{ fontStyle: 'italic' }} className="ns-grad-text"> шувуухай</span>
          </div>
          <div className="ns-mono" style={{ marginTop: 2 }}>UB · ШӨНӨ 21:42</div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 4 }}>
        <button onClick={() => go('notifications')} style={iconBtn}>
          <Icon name="heart" size={22} stroke="var(--text-primary)"/>
        </button>
        <button onClick={() => go('dm-list')} style={iconBtn}>
          <Icon name="send" size={22} stroke="var(--text-primary)"/>
        </button>
      </div>
    </div>
  );
}

// ─── Variation A: EDITORIAL — large cards, big serif italic tags
function FeedEditorial({ go }) {
  return (
    <div className="ns-screen-scroll" style={{ paddingBottom: 16 }}>
      {FEED_POSTS.map((p, i) => (
        <article key={p.id} style={{
          padding: '12px 20px 28px',
          borderBottom: i < FEED_POSTS.length - 1 ? '1px solid var(--hairline)' : 'none',
        }}>
          {/* header */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
            <Avatar size={40} initial={p.initial} ring/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 700, fontSize: 14 }}>{p.user}</div>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 4,
                fontSize: 11, color: 'var(--text-secondary)', marginTop: 2,
              }}>
                <Icon name="pin" size={11} stroke="var(--text-secondary)"/>
                <span onClick={() => go('bar')} style={{ cursor: 'pointer', color: 'var(--text-primary)', fontWeight: 600 }}>
                  {p.venue}
                </span>
                <span style={{ opacity: 0.5 }}>· {p.location}</span>
              </div>
            </div>
            <button style={iconBtn}>
              <Icon name="more" size={20} stroke="var(--text-secondary)"/>
            </button>
          </div>

          {/* image */}
          <div style={{ position: 'relative', borderRadius: 22, overflow: 'hidden' }}>
            <Placeholder label={`${p.venue} · зураг`} style={{ aspectRatio: '4 / 5' }}/>
            <span style={{
              position: 'absolute', top: 14, left: 14,
              padding: '6px 12px', borderRadius: 9999,
              background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(12px)',
              border: '1px solid var(--hairline)',
              fontFamily: 'var(--ff-display)', fontStyle: 'italic',
              fontSize: 14, color: 'var(--text-primary)',
            }}>
              {p.tag}
            </span>
          </div>

          {/* actions */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginTop: 14 }}>
            <button style={iconBtn} onClick={() => go('post-detail')}>
              <Icon name="heart" size={24}/>
            </button>
            <button style={iconBtn} onClick={() => go('post-detail')}>
              <Icon name="comment" size={24}/>
            </button>
            <button style={iconBtn}>
              <Icon name="send" size={24}/>
            </button>
            <div style={{ flex: 1 }}/>
            <button style={iconBtn}>
              <Icon name="bookmark" size={24}/>
            </button>
          </div>

          {/* meta + caption */}
          <div style={{ marginTop: 8, fontSize: 13, fontWeight: 700 }}>
            {p.likes.toLocaleString('en-US')} лайк
          </div>
          <p style={{ margin: '6px 0 0', fontSize: 14, lineHeight: 1.5, color: 'var(--text-primary)' }}>
            <span style={{ fontWeight: 700 }}>{p.user}</span>{' '}
            <span style={{ color: 'var(--text-secondary)' }}>{p.caption}</span>
          </p>
          <div onClick={() => go('post-detail')} style={{
            marginTop: 6, fontSize: 13, color: 'var(--text-tertiary)', cursor: 'pointer',
          }}>
            Бүх {Math.floor(p.likes / 50)} коммент үзэх
          </div>
        </article>
      ))}
    </div>
  );
}

// ─── Variation B: MAGAZINE — story rail + mixed grid
function FeedMagazine({ go }) {
  return (
    <div className="ns-screen-scroll" style={{ paddingBottom: 16 }}>
      {/* story rail */}
      <div style={{
        display: 'flex', gap: 14, overflowX: 'auto', padding: '0 20px 14px',
        borderBottom: '1px solid var(--hairline)',
      }}>
        {FEED_POSTS.concat(FEED_POSTS.slice(0, 2)).map((p, i) => (
          <div key={i} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, flexShrink: 0,
          }}>
            <Avatar size={62} initial={p.initial} ring/>
            <span style={{ fontSize: 10, color: 'var(--text-secondary)', maxWidth: 64,
              textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {p.user.replace('@', '')}
            </span>
          </div>
        ))}
      </div>

      {/* hero post */}
      <article style={{ padding: '16px 20px 20px' }}>
        <div style={{
          position: 'relative', borderRadius: 22, overflow: 'hidden', marginBottom: 12,
        }}>
          <Placeholder label="Vertigo Rooftop · hero" style={{ aspectRatio: '4 / 5' }}/>
          <div style={{
            position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, transparent 50%, rgba(11,1,24,0.92))',
          }}/>
          <div style={{
            position: 'absolute', left: 18, right: 18, bottom: 18,
          }}>
            <div className="ns-mono" style={{ color: '#FFB347', marginBottom: 6 }}>FEATURED · ӨНӨӨ ШӨНӨ</div>
            <h2 style={{
              margin: 0, fontFamily: 'var(--ff-display)', fontStyle: 'italic',
              fontSize: 28, fontWeight: 500, letterSpacing: '-0.01em', lineHeight: 1.05,
            }}>Vertigo дээр джаз</h2>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 10 }}>
              <Avatar size={22} initial="Н"/>
              <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>@nara.ulaan · 1,284 лайк</span>
            </div>
          </div>
        </div>
      </article>

      {/* 2-col grid */}
      <div style={{ padding: '0 20px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        {FEED_POSTS.slice(1).map(p => (
          <article key={p.id} onClick={() => go('post-detail')} style={{ cursor: 'pointer' }}>
            <div style={{ borderRadius: 16, overflow: 'hidden', position: 'relative' }}>
              <Placeholder label={p.venue} style={{ aspectRatio: '3 / 4' }}/>
              <span style={{
                position: 'absolute', top: 10, left: 10,
                padding: '4px 8px', borderRadius: 9999,
                background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(10px)',
                border: '1px solid var(--hairline)',
                fontSize: 10, fontFamily: 'var(--ff-mono)', letterSpacing: '0.1em',
                color: '#fff', textTransform: 'uppercase',
              }}>{p.tag}</span>
            </div>
            <div style={{ marginTop: 8, fontSize: 12, fontWeight: 700 }}>{p.venue}</div>
            <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>
              {p.user} · {p.likes.toLocaleString('en-US')} ♥
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}

// ─── Variation C: MINIMAL — text forward, sparse imagery
function FeedMinimal({ go }) {
  return (
    <div className="ns-screen-scroll" style={{ paddingBottom: 16 }}>
      <div style={{ padding: '8px 24px 16px' }}>
        <div className="ns-mono" style={{ marginBottom: 6 }}>ӨНӨӨ · 5/28</div>
        <h2 style={{
          margin: 0, fontFamily: 'var(--ff-display)', fontWeight: 500,
          fontSize: 26, letterSpacing: '-0.01em', lineHeight: 1.1,
        }}>4 шинэ <span style={{ fontStyle: 'italic' }} className="ns-grad-text">шөнө</span></h2>
      </div>

      {FEED_POSTS.map((p, i) => (
        <article key={p.id} onClick={() => go('post-detail')}
          style={{
            padding: '20px 24px',
            borderTop: '1px solid var(--hairline)',
            cursor: 'pointer',
          }}>
          <div style={{ display: 'flex', gap: 14 }}>
            <div style={{ flexShrink: 0 }}>
              <Avatar size={44} initial={p.initial} ring/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span style={{ fontWeight: 700, fontSize: 14 }}>{p.user}</span>
                <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>{i+1}ц өмнө</span>
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
                    display: 'flex', alignItems: 'center', gap: 4 }}>
                <Icon name="pin" size={11} stroke="var(--text-secondary)"/>
                <span>{p.venue}</span>
              </div>
              <p style={{ margin: '10px 0 0', fontSize: 14, lineHeight: 1.5 }}>{p.caption}</p>

              {/* small inline image */}
              <div style={{ marginTop: 12, borderRadius: 14, overflow: 'hidden' }}>
                <Placeholder label={p.tag} style={{ aspectRatio: '16 / 9' }}/>
              </div>

              <div style={{ display: 'flex', gap: 16, marginTop: 12, color: 'var(--text-tertiary)', fontSize: 12 }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="heart" size={14} stroke="var(--text-tertiary)"/> {p.likes.toLocaleString('en-US')}
                </span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="comment" size={14} stroke="var(--text-tertiary)"/> {Math.floor(p.likes/50)}
                </span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <Icon name="send" size={14} stroke="var(--text-tertiary)"/> хуваалцах
                </span>
              </div>
            </div>
          </div>
        </article>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 10 — POST DETAIL
// ────────────────────────────────────────────────────────────
function ScreenPostDetail({ go, state }) {
  const [liked, setLiked] = React.useState(false);
  const [burst, setBurst] = React.useState(false);
  const post = FEED_POSTS[0];

  const tapLike = () => {
    setLiked(true);
    setBurst(true);
    setTimeout(() => setBurst(false), 700);
  };

  if (state === 'loading') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DetailHeader go={go}/>
        <div className="ns-screen-scroll" style={{ padding: 20 }}>
          <Skel w="100%" h={400} r={20}/>
        </div>
      </div>
    );
  }
  if (state === 'error') {
    return (
      <div className="ns-screen">
        <PhoneStatus/>
        <DetailHeader go={go}/>
        <ErrorState onRetry={() => go('post-detail')}/>
      </div>
    );
  }

  const comments = state === 'empty' ? [] : [
    { u: '@bayar.dj',  c: 'Хорхой хүрлээ 🔥', t: '2ц' },
    { u: '@odgerel',   c: 'Хаана байгаа юм бэ?', t: '1ц' },
    { u: '@solongo',   c: 'Маргааш очно.', t: '32м' },
    { u: '@enkh_94',   c: 'Сонгодог.', t: '15м' },
  ];

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <DetailHeader go={go}/>

      <div className="ns-screen-scroll">
        {/* author row */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '4px 20px 14px' }}>
          <Avatar size={42} initial={post.initial} ring/>
          <div style={{ flex: 1 }}>
            <div style={{ fontWeight: 700, fontSize: 14 }}>{post.user}</div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 2 }}>
              <span onClick={() => go('bar')} style={{ color: 'var(--accent-start)', fontWeight: 600, cursor: 'pointer' }}>
                {post.venue}
              </span>
              <span> · {post.location}</span>
            </div>
          </div>
          <button className="ns-btn-secondary" style={{ height: 34, padding: '0 14px', fontSize: 12 }}>
            Дагах
          </button>
        </div>

        {/* image */}
        <div style={{ position: 'relative', margin: '0 20px', borderRadius: 22, overflow: 'hidden' }}
             onDoubleClick={tapLike}>
          <Placeholder label="Vertigo · live джаз" style={{ aspectRatio: '4 / 5' }}/>
          <HeartBurst visible={burst}/>
        </div>

        {/* actions */}
        <div style={{ display: 'flex', gap: 14, padding: '14px 20px 4px', alignItems: 'center' }}>
          <button style={iconBtn} onClick={tapLike}>
            <Icon name="heart" size={26}
                  filled={liked}
                  stroke={liked ? '#FF4D8D' : 'var(--text-primary)'}/>
          </button>
          <button style={iconBtn}><Icon name="comment" size={26}/></button>
          <button style={iconBtn}><Icon name="send" size={26}/></button>
          <div style={{ flex: 1 }}/>
          <button style={iconBtn}><Icon name="bookmark" size={26}/></button>
        </div>

        <div style={{ padding: '0 20px', fontSize: 13, fontWeight: 700 }}>
          {(post.likes + (liked ? 1 : 0)).toLocaleString('en-US')} лайк
        </div>
        <p style={{ margin: '6px 20px 0', fontSize: 14, lineHeight: 1.5 }}>
          <span style={{ fontWeight: 700 }}>{post.user}</span>{' '}
          <span style={{ color: 'var(--text-secondary)' }}>{post.caption}</span>
          {' '}
          <span style={{ color: 'var(--accent-start)' }}>#vertigo #jazz #ub_nightlife</span>
        </p>

        {/* location chip */}
        <div style={{ padding: '14px 20px 8px' }}>
          <button onClick={() => go('bar')} style={{
            display: 'inline-flex', alignItems: 'center', gap: 8,
            padding: '8px 14px 8px 8px', borderRadius: 9999,
            background: 'var(--bg-surface)', border: '1px solid var(--hairline)',
            cursor: 'pointer', color: 'var(--text-primary)',
          }}>
            <span style={{
              width: 28, height: 28, borderRadius: '50%',
              background: 'var(--accent-grad)',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              color: '#1B0210',
            }}><Icon name="pin" size={14} stroke="#1B0210" strokeWidth={2}/></span>
            <span style={{ fontSize: 13, fontWeight: 600 }}>{post.venue}</span>
            <Icon name="chevron-right" size={14} stroke="var(--text-tertiary)"/>
          </button>
        </div>

        {/* comments */}
        <div style={{ borderTop: '1px solid var(--hairline)', padding: '14px 20px 8px', marginTop: 8 }}>
          <div className="ns-mono" style={{ marginBottom: 10 }}>КОММЕНТ · {comments.length}</div>
          {comments.length === 0 ? (
            <div style={{ padding: '32px 0', textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
              Хамгийн түрүүнд коммент бичээрэй.
            </div>
          ) : comments.map((cm, i) => (
            <div key={i} style={{ display: 'flex', gap: 10, marginBottom: 14 }}>
              <Avatar size={32} initial={cm.u[1].toUpperCase()}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13 }}>
                  <span style={{ fontWeight: 700 }}>{cm.u}</span>{' '}
                  <span style={{ color: 'var(--text-secondary)' }}>{cm.c}</span>
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>
                  {cm.t} · Хариулах · ♥ 2
                </div>
              </div>
              <button style={{ background: 'transparent', border: 0, cursor: 'pointer', color: 'var(--text-tertiary)' }}>
                <Icon name="heart" size={14}/>
              </button>
            </div>
          ))}
        </div>
        <div style={{ height: 80 }}/>
      </div>

      {/* comment input */}
      <div style={{
        flexShrink: 0,
        borderTop: '1px solid var(--hairline)',
        padding: '12px 16px 18px',
        display: 'flex', alignItems: 'center', gap: 10,
        background: 'rgba(11,1,24,0.92)', backdropFilter: 'blur(12px)',
      }}>
        <Avatar size={32} initial="М"/>
        <input className="ns-input" placeholder="Коммент бичих..."
               style={{ height: 40, flex: 1, fontSize: 13 }}/>
        <button style={{
          width: 40, height: 40, borderRadius: '50%',
          border: 0, background: 'var(--accent-grad)', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#1B0210',
        }}>
          <Icon name="send" size={16} stroke="#1B0210" strokeWidth={2}/>
        </button>
      </div>
    </div>
  );
}

function DetailHeader({ go }) {
  return (
    <div style={{
      flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 16px 12px',
    }}>
      <button style={iconBtn} onClick={() => go('feed')}>
        <Icon name="arrow-left" size={22}/>
      </button>
      <div style={{ fontFamily: 'var(--ff-display)', fontSize: 18, fontWeight: 500 }}>Нийтлэл</div>
      <button style={iconBtn}><Icon name="more" size={22}/></button>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// 11 — CREATOR PROFILE + LOCKED CONTENT
// ────────────────────────────────────────────────────────────
function ScreenCreator({ go, state }) {
  const [tab, setTab] = React.useState('posts');
  const [following, setFollowing] = React.useState(false);

  return (
    <div className="ns-screen">
      <PhoneStatus/>
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5,
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '52px 12px 0' }}>
        <button style={iconBtn} onClick={() => go('feed')}>
          <span style={{
            width: 36, height: 36, borderRadius: 18,
            background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(12px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="arrow-left" size={20}/>
          </span>
        </button>
        <button style={iconBtn}>
          <span style={{
            width: 36, height: 36, borderRadius: 18,
            background: 'rgba(11,1,24,0.55)', backdropFilter: 'blur(12px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="more" size={20}/>
          </span>
        </button>
      </div>

      <div className="ns-screen-scroll">
        {/* cover */}
        <div style={{ position: 'relative', height: 200, overflow: 'hidden' }}>
          <Placeholder label="creator · cover" style={{ aspectRatio: 'auto', height: '100%' }}/>
          <div style={{
            position: 'absolute', inset: 0,
            background: 'linear-gradient(180deg, transparent 40%, rgba(11,1,24,0.95))',
          }}/>
        </div>

        {/* profile head */}
        <div style={{ padding: '0 20px', marginTop: -50, position: 'relative' }}>
          <Avatar size={94} initial="Б" ring/>
          <div style={{ marginTop: 12 }}>
            <h2 style={{
              margin: 0, fontFamily: 'var(--ff-display)', fontWeight: 500,
              fontSize: 26, letterSpacing: '-0.01em',
            }}>Bayarmaa <span className="ns-grad-text" style={{ fontStyle: 'italic' }}>DJ</span></h2>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 4 }}>
              @bayar.dj · UB · House / Techno
            </div>
            <p style={{ margin: '12px 0 0', fontSize: 13, lineHeight: 1.55, color: 'var(--text-secondary)' }}>
              Mass Club resident DJ. Шинэ set жил бүр 12.<br/>
              Bookings — DM.
            </p>
          </div>

          {/* stats */}
          <div style={{
            display: 'flex', gap: 22, marginTop: 16, padding: '14px 0',
            borderTop: '1px solid var(--hairline)',
            borderBottom: '1px solid var(--hairline)',
          }}>
            {[['Пост', '142'], ['Дагагч', '8.4K'], ['Дагаж буй', '231']].map(([l, v]) => (
              <div key={l}>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 20, fontWeight: 500 }}>{v}</div>
                <div className="ns-mono" style={{ marginTop: 2 }}>{l}</div>
              </div>
            ))}
          </div>

          {/* buttons */}
          <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
            <button
              className={following ? 'ns-btn-secondary' : 'ns-btn-primary'}
              style={{ flex: 1, height: 44 }}
              onClick={() => setFollowing(!following)}>
              {following ? 'Дагаж байна' : 'Дагах'}
            </button>
            <button className="ns-btn-secondary" style={{ width: 44, height: 44, padding: 0 }}>
              <Icon name="send" size={18}/>
            </button>
          </div>

          {/* tabs */}
          <div style={{
            display: 'flex', gap: 0, marginTop: 22,
            borderBottom: '1px solid var(--hairline)',
          }}>
            {[['posts', 'Пост'], ['locked', 'Түгжээтэй']].map(([k, l]) => (
              <button key={k} onClick={() => setTab(k)} style={{
                flex: 1, padding: '14px 0', background: 'transparent', cursor: 'pointer',
                border: 0, borderBottom: tab === k ? '2px solid var(--accent-start)' : '2px solid transparent',
                color: tab === k ? 'var(--text-primary)' : 'var(--text-tertiary)',
                fontWeight: 600, fontSize: 13, letterSpacing: '0.04em',
              }}>{l}</button>
            ))}
          </div>
        </div>

        {/* grid */}
        {tab === 'posts' ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 2, marginTop: 2 }}>
            {Array.from({ length: 9 }).map((_, i) => (
              <Placeholder key={i} label={`#${i+1}`} style={{ aspectRatio: '1' }}/>
            ))}
          </div>
        ) : (
          <div style={{ padding: 20, display: 'flex', flexDirection: 'column', gap: 14 }}>
            {[
              { title: 'Exclusive DJ set · Vol. 12', price: 5000, dur: '52 мин' },
              { title: 'Backstage · Mass NYE',      price: 8000, dur: '24 мин' },
              { title: 'Б-сэтгэгдэл · 1 цаг',         price: 3000, dur: '1ц 04м' },
            ].map((it, i) => (
              <div key={i} style={{
                position: 'relative', borderRadius: 18, overflow: 'hidden',
                border: '1px solid var(--hairline)',
              }}>
                <Placeholder label="locked content"
                  style={{ aspectRatio: '16 / 9', filter: 'blur(8px) brightness(0.6)' }}/>
                <div style={{
                  position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
                  alignItems: 'center', justifyContent: 'center', gap: 10,
                  background: 'radial-gradient(circle, rgba(11,1,24,0.4), rgba(11,1,24,0.85))',
                }}>
                  <span style={{
                    width: 44, height: 44, borderRadius: 22,
                    background: 'var(--accent-grad)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: '#1B0210',
                    boxShadow: '0 4px 16px rgba(255,77,141,0.4)',
                  }}>
                    <Icon name="lock" size={20} stroke="#1B0210" strokeWidth={2}/>
                  </span>
                  <div style={{ textAlign: 'center', padding: '0 16px' }}>
                    <div style={{ fontFamily: 'var(--ff-display)', fontSize: 17, fontWeight: 500 }}>{it.title}</div>
                    <div className="ns-mono" style={{ marginTop: 6 }}>{it.dur} · ₮{it.price.toLocaleString('en-US')}</div>
                  </div>
                  <button className="ns-btn-primary" style={{ height: 40, fontSize: 12 }} onClick={() => go('qpay')}>
                    Контент үзэх
                  </button>
                </div>
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
// 12 — QPAY PAYMENT SHEET
// ────────────────────────────────────────────────────────────
function ScreenQPay({ go, state }) {
  const banks = [
    { id: 'b1', name: 'Bank A' },
    { id: 'b2', name: 'Bank B' },
    { id: 'b3', name: 'Bank C' },
    { id: 'b4', name: 'Bank D' },
    { id: 'b5', name: 'Bank E' },
    { id: 'b6', name: 'Bank F' },
  ];

  const isLoading = state === 'loading';
  const isSuccess = state === 'empty'; // reusing empty as the success path here
  const isError = state === 'error';

  return (
    <div className="ns-screen" style={{ background: 'rgba(11,1,24,0.4)' }}>
      {/* faded creator behind */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(circle at 30% 20%, rgba(255,77,141,0.18), transparent 50%), var(--bg-base)',
      }}/>
      <PhoneStatus/>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
        {/* sheet */}
        <div style={{
          background: 'var(--bg-elevated)',
          borderRadius: '28px 28px 0 0',
          padding: '14px 24px 36px',
          boxShadow: '0 -24px 60px rgba(0,0,0,0.6)',
          border: '1px solid var(--hairline)', borderBottom: 0,
          animation: 'ns-slide-in-up .35s ease-out forwards',
        }}>
          <div style={{
            width: 36, height: 4, borderRadius: 4,
            background: 'rgba(255,255,255,0.18)', margin: '0 auto 18px',
          }}/>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div className="ns-mono">QPAY · ТӨЛБӨР</div>
              <h2 style={{ margin: '4px 0 0', fontFamily: 'var(--ff-display)', fontSize: 22, fontWeight: 500 }}>
                Exclusive DJ set · Vol. 12
              </h2>
            </div>
            <button style={iconBtn} onClick={() => go('creator')}>
              <Icon name="close" size={20}/>
            </button>
          </div>

          {isLoading ? (
            <div style={{ padding: '40px 0', display: 'flex', flexDirection: 'column',
                  alignItems: 'center', gap: 14 }}>
              <div className="ns-spin"/>
              <div style={{ fontSize: 14, color: 'var(--text-secondary)' }}>
                Төлбөр баталгаажихыг хүлээж байна...
              </div>
              <div className="ns-mono">QPay · #2024-05-28-4821</div>
            </div>
          ) : isSuccess ? (
            <div style={{ padding: '40px 0', display: 'flex', flexDirection: 'column',
                  alignItems: 'center', gap: 14, textAlign: 'center' }}>
              <span style={{
                width: 72, height: 72, borderRadius: '50%',
                background: 'rgba(61,214,140,0.15)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                color: 'var(--success)',
                filter: 'drop-shadow(0 0 16px rgba(61,214,140,0.4))',
              }}>
                <Icon name="check" size={32} strokeWidth={2.5}/>
              </span>
              <div>
                <div style={{ fontFamily: 'var(--ff-display)', fontSize: 22, fontWeight: 500 }}>
                  Контент нээгдлээ
                </div>
                <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 4 }}>
                  ₮5,000 төлсөн · #2024-05-28-4821
                </div>
              </div>
              <button className="ns-btn-primary" onClick={() => go('creator')}>Үзэж эхлэх</button>
            </div>
          ) : isError ? (
            <div style={{ padding: '32px 0', display: 'flex', flexDirection: 'column',
                  alignItems: 'center', gap: 14, textAlign: 'center' }}>
              <span style={{
                width: 64, height: 64, borderRadius: '50%',
                background: 'rgba(255,84,112,0.12)', color: 'var(--error)',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              }}><Icon name="alert" size={28}/></span>
              <div style={{ fontFamily: 'var(--ff-display)', fontSize: 20 }}>
                Төлбөр амжилтгүй
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                Дансанд хүрэлцэхгүй эсвэл сүлжээ салсан.
              </div>
              <button className="ns-btn-primary" onClick={() => go('qpay')}>
                Дахин оролдох
              </button>
            </div>
          ) : (
            <>
              {/* amount */}
              <div style={{ textAlign: 'center', padding: '20px 0 8px' }}>
                <div style={{
                  fontFamily: 'var(--ff-display)', fontSize: 56, fontWeight: 500,
                  letterSpacing: '-0.03em', lineHeight: 1,
                }}>
                  <span style={{ fontSize: 28, color: 'var(--text-secondary)', verticalAlign: 'top', marginRight: 4 }}>₮</span>
                  <span className="ns-grad-text">5,000</span>
                </div>
              </div>

              {/* QR */}
              <div style={{
                margin: '14px auto 18px', width: 200, height: 200,
                background: '#fff', borderRadius: 18, padding: 14, position: 'relative',
              }}>
                <QRPattern/>
                <div style={{
                  position: 'absolute', top: '50%', left: '50%',
                  transform: 'translate(-50%, -50%)',
                  width: 44, height: 44, borderRadius: 10,
                  background: 'var(--bg-elevated)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: '3px solid #fff',
                }}>
                  <LogoSlot id="qpay-logo" label="QPay" width={32} height={32} radius={6}/>
                </div>
              </div>

              <div className="ns-mono" style={{ textAlign: 'center', marginBottom: 14 }}>
                ЭСВЭЛ ДАНСАА СОНГО
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
                {banks.map(b => (
                  <button key={b.id} style={{
                    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
                    padding: '12px 6px', borderRadius: 14,
                    background: 'var(--bg-surface)', border: '1px solid var(--hairline)',
                    cursor: 'pointer', color: 'var(--text-primary)',
                  }} onClick={() => go('qpay', { state: 'loading' })}>
                    <LogoSlot id={`bank-${b.id}`} label={b.name} width={36} height={36} radius={10}/>
                    <span style={{ fontSize: 10, color: 'var(--text-tertiary)' }}>Bank slot</span>
                  </button>
                ))}
              </div>

              <div style={{
                marginTop: 16, padding: 12, borderRadius: 12,
                background: 'rgba(255,179,71,0.08)', border: '1px solid rgba(255,179,71,0.16)',
                display: 'flex', gap: 10, alignItems: 'flex-start',
                fontSize: 11, color: 'var(--text-secondary)', lineHeight: 1.5,
              }}>
                <Icon name="shield" size={16} stroke="var(--warning)"/>
                <span>Төлбөр аюулгүйгээр QPay-ээр шилжих. Логог дараа нь солих.</span>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// 13×13 QR-like pattern
function QRPattern() {
  const size = 13;
  const cells = React.useMemo(() => {
    const arr = [];
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      // corner anchors
      const corner = (x < 3 && y < 3) || (x > size-4 && y < 3) || (x < 3 && y > size-4);
      arr.push({ x, y, on: corner ? true : Math.random() > 0.5 });
    }
    return arr;
  }, []);
  return (
    <svg viewBox={`0 0 ${size} ${size}`} width="100%" height="100%">
      {cells.map((c, i) => c.on && (
        <rect key={i} x={c.x} y={c.y} width={1} height={1} fill="#0B0118"/>
      ))}
      {/* anchor squares */}
      {[[0,0], [size-3, 0], [0, size-3]].map(([ax, ay], i) => (
        <g key={i}>
          <rect x={ax} y={ay} width={3} height={3} fill="#0B0118"/>
          <rect x={ax+0.5} y={ay+0.5} width={2} height={2} fill="#fff"/>
          <rect x={ax+1} y={ay+1} width={1} height={1} fill="#0B0118"/>
        </g>
      ))}
    </svg>
  );
}

Object.assign(window, { ScreenFeed, ScreenPostDetail, ScreenCreator, ScreenQPay });
