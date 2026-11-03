import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../../../web/admin/index.html',import.meta.url),'utf8');
const source = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
function fixture(fetcher = async () => { throw new Error('Unexpected request'); }) {
 const nodes = new Map();
 const node = () => ({hidden:false,textContent:'',disabled:false,replaceChildren(){this.cleared=true;},querySelectorAll(){return [];}});
 const timers = [];
 const context = vm.createContext({URL,URLSearchParams,AbortController,console,Intl,Date,
  supabase:{createClient:()=>({auth:{}})},
  document:{getElementById:id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id);}},
  fetch:fetcher,setTimeout:(fn,ms)=>{timers.push({fn,ms});return timers.length;},clearTimeout:()=>{},
 });
 vm.runInContext(source.replace(/\nboot\(\);\s*$/,''),context);
 const api = vm.runInContext('({scope,current,assertCurrent,ticket,visible,safeImage,esc,avatar,validatePage,requireAdmin,moderate,request,legacyWrite,venuePayload,runAction,receiveSession,attachedPostPath,mediaSource,reviewObject,reviewMediaSource,reviewContent})',context);
 const owner = (id='owner-A',token='jwt-A') => vm.runInContext(`session={user:{id:${JSON.stringify(id)}},access_token:${JSON.stringify(token)}};generation++;actor=${JSON.stringify(id)};`,context);
 owner();
 return {api,context,owner,nodes,timers};
}
const ok = data => ({ok:true,status:200,json:async()=>data});
const receipt = (action,target,reportId=null) => {
 const reportAction=['resolve_report','dismiss_report','reopen_report'].includes(action);
 const linked=reportAction?target:reportId;
 return {audit_id:'50000000-0000-4000-8000-000000000001',action,target_id:target,
 target_type:reportAction?'report':action.endsWith('_user')?'user':action==='delete_post'?'post':'comment',
 report_id:linked,report_status:linked?action==='dismiss_report'?'reviewed':action==='reopen_report'?'pending':'resolved':null};
};
const fail = (code,status=400,message='private detail') => ({ok:false,status,json:async()=>({code,message})});
const deferred = () => { let resolve,reject; const promise = new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject}; };

test('all inline JavaScript parses and config generator contract remains exact',()=>{
 new vm.Script(source);
 assert.equal((source.match(/supabase\.createClient\(SUPABASE_URL, SUPABASE_ANON\)/g)||[]).length,1);
 assert.equal((source.match(/const SUPABASE_URL\s*=/g)||[]).length,1);
 assert.equal((source.match(/const SUPABASE_ANON\s*=/g)||[]).length,1);
 assert.doesNotMatch(html,/\son(?:error|click|submit)\s*=/i);
 assert.doesNotMatch(source,/sb\.from\(['"](?:profiles|posts|comments|reports)['"]\)/);
 assert.doesNotMatch(source,/is_admin\s*:\s*(?:true|false|promote)/);
});

test('avatar cannot break out into HTML or JavaScript and supports preset references',()=>{
 const {api}=fixture();
 assert.equal(api.safeImage('javascript:alert(1)'), '');
 assert.equal(api.safeImage('data:image/svg+xml,<svg onload=alert(1)>'), '');
 assert.equal(api.safeImage('https://user:password@example.test/a.png'), '');
 assert.equal(api.safeImage('nightowl://avatar/young-woman'),'/assets/assets/images/avatars/owl_young_woman.webp');
 assert.equal(api.safeImage('nightowl://avatar/unknown'), '');
 const rendered=api.avatar('https://images.test/\" onerror=\"alert(1)');
 assert.doesNotMatch(rendered,/"\s+onerror=/);
 assert.match(api.esc("'\"><img onerror=bad>"),/^&#39;&quot;&gt;&lt;img/);
});

test('active admin gate requires authoritative actor identity',async()=>{
 const f=fixture(async()=>ok({actor_id:'another-owner'}));
 await assert.rejects(f.api.requireAdmin(f.api.scope()),/Эрх шалгалтын хариу зөрүүтэй/);
});

test('action pins captured JWT and sends only the moderation RPC contract',async()=>{
 let request;
 const f=fixture(async(url,options)=>{request={url,options};return ok(receipt('ban_user','target-1','report-1'));});
 const result=await f.api.moderate(f.api.scope(),'ban_user','target-1','  Verified repeated spam  ','report-1');
 assert.equal(result.audit_id,'50000000-0000-4000-8000-000000000001');
 assert.match(request.url,/\/rest\/v1\/rpc\/admin_console_action$/);
 assert.equal(request.options.headers.Authorization,'Bearer jwt-A');
 assert.deepEqual(JSON.parse(request.options.body),{p_action:'ban_user',p_target_id:'target-1',p_reason:'Verified repeated spam',p_report_id:'report-1'});
});

test('short reasons and unlisted role-grant actions never issue requests',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});
 await assert.rejects(f.api.moderate(f.api.scope(),'ban_user','id','  a  '));
 await assert.rejects(f.api.moderate(f.api.scope(),'make_admin','id','valid reason'));
 await assert.rejects(f.api.moderate(f.api.scope(),'ban_user','id','a'.repeat(1001)));
 assert.equal(calls,0);
});

test('a captured owner cannot start a mutation after account change',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});const captured=f.api.scope();
 f.owner('owner-B','jwt-B');
 await assert.rejects(f.api.moderate(captured,'ban_user','target','reason'),error=>error.constructor.name==='StaleRequest');
 assert.equal(calls,0);
});

test('late mutation completion is discarded after account change',async()=>{
 const response=deferred();let authorization;
 const f=fixture(async(_url,options)=>{authorization=options.headers.Authorization;return response.promise;});
 const pending=f.api.moderate(f.api.scope(),'delete_post','target','checked content');
 f.owner('owner-B','jwt-B');
 response.resolve(ok(receipt('delete_post','target')));
 await assert.rejects(pending,error=>error.constructor.name==='StaleRequest');
 assert.equal(authorization,'Bearer jwt-A');
});

test('session change during JSON parsing is also discarded',async()=>{
 const body=deferred();const f=fixture(async()=>({ok:true,status:200,json:()=>body.promise}));
 const pending=f.api.requireAdmin(f.api.scope()); await Promise.resolve();
 f.owner('owner-B','jwt-B');body.resolve({actor_id:'owner-A'});
 await assert.rejects(pending,error=>error.constructor.name==='StaleRequest');
});

test('server denial hides private UI immediately and never echoes raw errors',async()=>{
 const f=fixture(async()=>fail('42501',403,'email-or-token-should-not-leak'));
 await assert.rejects(f.api.requireAdmin(f.api.scope()));
 assert.equal(f.nodes.get('app').hidden,true);
 assert.equal(f.nodes.get('view').cleared,true);
 assert.match(f.nodes.get('loginErr').textContent,/идэвхтэй админ эрх алга/);
 assert.doesNotMatch(f.nodes.get('loginErr').textContent,/email-or-token/);
});

test('missing migration and conflict are explicit errors, never empty pages',async()=>{
 for(const [code,pattern] of [['PGRST202',/migration/],['40001',/төлөв өөрчлөгдсөн/]]){
  const f=fixture(async()=>fail(code));
  await assert.rejects(f.api.requireAdmin(f.api.scope()),pattern);
 }
 const f=fixture();
 assert.throws(()=>f.api.validatePage(null));
 assert.throws(()=>f.api.validatePage({items:[],has_more:'false'}));
 assert.deepEqual(f.api.validatePage({items:[],has_more:false}),{items:[],has_more:false});
});

test('uncertain action timeout tells admin to refresh and check audit before retry',async()=>{
 const f=fixture(async(_url,{signal})=>new Promise((_resolve,reject)=>signal.addEventListener('abort',()=>reject(new Error('timeout')))));
 const pending=f.api.moderate(f.api.scope(),'delete_comment','id','valid reason');
 assert.equal(f.timers[0].ms,20000);f.timers[0].fn();
 await assert.rejects(pending,/Үйлдэл хийгдсэн байж болно.*үйлдлийн түүх/);
});

test('action response without matching audit receipt cannot report success',async()=>{
 for(const data of [null,{}, {audit_id:'audit',action:'delete_post',target_id:'another'}]) {
  const f=fixture(async()=>ok(data));
  await assert.rejects(f.api.moderate(f.api.scope(),'delete_post','target','valid reason'),/баталгаатай|Баталгаатай/);
 }
});

test('new query invalidates stale queue render tickets',()=>{
 const f=fixture();const captured=f.api.ticket();assert.equal(f.api.visible(captured),true);
 vm.runInContext('queryGeneration++;',f.context);assert.equal(f.api.visible(captured),false);
});

test('duplicate confirmation clicks produce one mutation and one refresh',async()=>{
 const reason=deferred();let requests=0,refreshes=0;
 const f=fixture(async()=>{requests++;return ok(receipt('ban_user','target'));});
 f.context.askReason=()=>reason.promise;f.context.refreshed=()=>refreshes++;
 vm.runInContext('reasonDialog=askReason;toast=()=>{};navigate=async()=>refreshed();',f.context);
 const t=f.api.ticket(),button={disabled:false,isConnected:true};
 const first=f.api.runAction(t,'ban_user','target','label',null,button);
 await f.api.runAction(t,'ban_user','target','label',null,button);
 assert.equal(button.disabled,true);assert.equal(requests,0);
 reason.resolve('confirmed spam');await first;
 assert.equal(requests,1);assert.equal(refreshes,1);assert.equal(button.disabled,false);
});

test('account change while reason dialog is open prevents mutation',async()=>{
 const reason=deferred();let requests=0;
 const f=fixture(async()=>{requests++;return ok({});});f.context.askReason=()=>reason.promise;
 vm.runInContext('reasonDialog=askReason;',f.context);
 const pending=f.api.runAction(f.api.ticket(),'ban_user','target','label',null,{disabled:false,isConnected:false});
 f.owner('owner-B','jwt-B');reason.resolve('confirmed reason');await pending;
 assert.equal(requests,0);
});

test('server action failure does not optimistically remove or reload rows',async()=>{
 let refreshes=0,message='';const f=fixture(async()=>fail('40001'));
 f.context.refreshed=()=>refreshes++;f.context.notified=text=>message=text;
 vm.runInContext('reasonDialog=async()=>"checked reason";navigate=async()=>refreshed();toast=notified;',f.context);
 await f.api.runAction(f.api.ticket(),'resolve_report','report','label',null,{disabled:false,isConnected:true});
 assert.equal(refreshes,0);assert.match(message,/төлөв өөрчлөгдсөн/);
});

test('legacy venue writes require active gate and exact affected row',async()=>{
 let calls=0;const f=fixture(async()=>++calls===1?ok({actor_id:'owner-A'}):ok([]));
 await assert.rejects(f.api.legacyWrite(f.api.scope(),'venues','id',{name:'Name'},'PATCH'),/Өөрчлөлт баталгаажаагүй/);
 assert.equal(calls,2);
});

test('venue coordinates preserve zero and reject malformed or incomplete pairs',()=>{
 const f=fixture();const form=values=>({elements:Object.fromEntries(Object.entries({name:'Cafe',type:'cafe',district:'',lat:'0',lng:'0',cover:'',description:'',...values}).map(([key,value])=>[key,{value}]))});
 const data=f.api.venuePayload(form({}));assert.equal(data.lat,0);assert.equal(data.lng,0);
 for(const values of [{lat:'abc'},{lat:'91'},{lng:'181'},{lng:''},{cover:'javascript:alert(1)'}]) assert.throws(()=>f.api.venuePayload(form(values)));
});

test('auth event immediately hides data and defers API verification outside callback',()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});
 f.api.receiveSession({user:{id:'owner-B'},access_token:'jwt-B'});
 assert.equal(calls,0);assert.equal(f.nodes.get('view').cleared,true);assert.equal(f.nodes.get('app').hidden,true);
 assert.equal(f.timers.length,1);assert.equal(f.timers[0].ms,0);
});


test('private attached post media signs exact path with captured JWT and 300 second expiry',async()=>{
 let sent;const f=fixture(async(url,options)=>{sent={url,options};return ok({signedURL:'/object/sign/posts/author/photo.jpg?token=fixture-signed-token'});});
 const backend=vm.runInContext('SUPABASE_URL',f.context);
 const url=await f.api.mediaSource(f.api.scope(),{author_id:'author',media_url:`${backend}/storage/v1/object/public/posts/author/photo.jpg`});
 assert.equal(sent.url,`${backend}/storage/v1/object/sign/posts/author/photo.jpg`);
 assert.equal(sent.options.headers.Authorization,'Bearer jwt-A');
 assert.deepEqual(JSON.parse(sent.options.body),{expiresIn:300});
 assert.equal(new URL(url).pathname,'/storage/v1/object/sign/posts/author/photo.jpg');
});

test('private media cannot sign another owner, bucket or encoded traversal path',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});const backend=vm.runInContext('SUPABASE_URL',f.context);
 for(const suffix of ['/posts/other/photo.jpg','/stories/author/photo.jpg','/posts/author/%2Fsecret.jpg','/posts/author/%252e%252e']) {
  await assert.rejects(f.api.mediaSource(f.api.scope(),{author_id:'author',media_url:`${backend}/storage/v1/object/public${suffix}`}));
 }
 assert.equal(calls,0);
});

test('signing response must remain on exact backend and attached object path',async()=>{
 for(const signedURL of ['https://evil.test/object/sign/posts/author/photo.jpg?token=bad','/object/sign/posts/author/other.jpg?token=bad','/object/sign/posts/author/photo.jpg']) {
  const f=fixture(async()=>ok({signedURL}));const backend=vm.runInContext('SUPABASE_URL',f.context);
  await assert.rejects(f.api.mediaSource(f.api.scope(),{author_id:'author',media_url:`${backend}/storage/v1/object/public/posts/author/photo.jpg`}),/холбоос тохирохгүй/);
 }
});

test('media denial remains explicit preview failure without revoking verified admin UI',async()=>{
 const f=fixture(async()=>fail('42501',403));const backend=vm.runInContext('SUPABASE_URL',f.context);const before=f.api.scope();
 await assert.rejects(f.api.mediaSource(before,{author_id:'author',media_url:`${backend}/storage/v1/object/public/posts/author/photo.jpg`}),/Медиа харах эрх/);
 assert.equal(f.api.current(before),true);
});

test('external safe media never receives admin JWT or storage signing request',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});
 assert.equal(await f.api.mediaSource(f.api.scope(),{author_id:'author',media_url:'https://images.test/photo.jpg'}),'https://images.test/photo.jpg');
 assert.equal(calls,0);
});

test('late signed media result cannot paint after account change',async()=>{
 const response=deferred();const f=fixture(async()=>response.promise);const backend=vm.runInContext('SUPABASE_URL',f.context);
 const pending=f.api.mediaSource(f.api.scope(),{author_id:'author',media_url:`${backend}/storage/v1/object/public/posts/author/photo.jpg`});
 f.owner('owner-B','jwt-B');response.resolve(ok({signedURL:'/object/sign/posts/author/photo.jpg?token=fixture'}));
 await assert.rejects(pending,error=>error.constructor.name==='StaleRequest');
});


test('linked report closure requires exact type, report, status and UUID audit receipt',async()=>{
 const valid=receipt('delete_post','post-1','report-1');
 for(const altered of [{target_type:'comment'},{report_id:'other-report'},{report_status:'pending'},{report_status:null},{audit_id:'not-a-uuid'}]) {
  const f=fixture(async()=>ok({...valid,...altered}));
  await assert.rejects(f.api.moderate(f.api.scope(),'delete_post','post-1','checked content','report-1'),/Баталгаатай хариу/);
 }
});

test('report-only receipts confirm resolve, dismiss and reopen statuses',async()=>{
 for(const action of ['resolve_report','dismiss_report','reopen_report']) {
  const f=fixture(async()=>ok(receipt(action,'report-1')));
  assert.equal((await f.api.moderate(f.api.scope(),action,'report-1','checked reason')).report_id,'report-1');
 }
 const f=fixture(async()=>ok({...receipt('ban_user','target'),report_id:'unexpected',report_status:'resolved'}));
 await assert.rejects(f.api.moderate(f.api.scope(),'ban_user','target','checked reason'),/Баталгаатай хариу/);
});

test('missing authentication CDN leaves a clear error and disabled login',()=>{
 const nodes={loginErr:{hidden:true,textContent:''},loginBtn:{disabled:false}};
 const context=vm.createContext({document:{getElementById:id=>nodes[id]}});
 assert.throws(()=>vm.runInContext(source,context),/Admin authentication dependency unavailable/);
 assert.equal(nodes.loginErr.hidden,false);assert.equal(nodes.loginBtn.disabled,true);
 assert.match(nodes.loginErr.textContent,/Нэвтрэх сан ачаалсангүй/);
});


test('non-JSON HTTP authorization denial still clears privileged UI before parsing',async()=>{
 for(const status of [401,403]) {
  let parsed=false;
  const f=fixture(async()=>({ok:false,status,json:async()=>{parsed=true;throw new SyntaxError('HTML proxy response');}}));
  await assert.rejects(f.api.requireAdmin(f.api.scope()));
  assert.equal(parsed,false);assert.equal(f.nodes.get('app').hidden,true);assert.equal(f.nodes.get('view').cleared,true);
 }
});

const reviewItem = () => ({id:'30000000-0000-4000-8000-000000000001',kind:'story',review_version:'40000000-0000-4000-8000-000000000001'});
const reviewReceipt = item => ({target_id:item.id,target_type:item.kind,review_version:item.review_version,status:'approved',audit_id:'50000000-0000-4000-8000-000000000001',created_at:'2026-11-03T08:00:00Z'});
test('review pins selected content version and validates the audit receipt',async()=>{
 let request;const item=reviewItem();const f=fixture(async(url,options)=>{request={url,options};return ok(reviewReceipt(item));});
 await f.api.reviewContent(f.api.scope(),item,'approved','Reviewed complete video');
 assert.match(request.url,/\/rpc\/admin_console_review$/);
 assert.equal(request.options.headers.Authorization,'Bearer jwt-A');
 assert.deepEqual(JSON.parse(request.options.body),{p_kind:'story',p_target_id:item.id,p_version:item.review_version,p_decision:'approved',p_reason:'Reviewed complete video'});
});
test('review cannot accept a changed version, wrong target or malformed audit',async()=>{
 for(const patch of [{review_version:'other'},{target_id:'other'},{status:'pending'},{audit_id:'prefix-50000000-0000-4000-8000-000000000001'},{created_at:'invalid'}]){
  const item=reviewItem();const f=fixture(async()=>ok({...reviewReceipt(item),...patch}));
  await assert.rejects(f.api.reviewContent(f.api.scope(),item,'approved','Reviewed all content'),/Баталгаатай/);
 }
});
test('review rejects unsupported target kinds, short reasons and invalid decisions without request',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;return ok({});});
 for(const [item,decision,reason] of [[{...reviewItem(),kind:'message'},'approved','Reviewed'],[{...reviewItem(),kind:'all'},'approved','Reviewed'],[reviewItem(),'make_admin','Reviewed'],[reviewItem(),'approved','x']])await assert.rejects(f.api.reviewContent(f.api.scope(),item,decision,reason));
 assert.equal(calls,0);
});
test('new review signing supports all private buckets and rejects path escapes',async()=>{
 const backend='https://jbbdnpsvstwxtgtjoeru.supabase.co';
 for(const bucket of ['posts','stories','avatars','venues']){
  let request;const f=fixture(async(url,options)=>{request={url,options};return ok({signedURL:`/object/sign/${bucket}/author/photo.jpg?token=fixture`});});
  assert.equal(await f.api.reviewMediaSource(f.api.scope(),`${backend}/storage/v1/object/public/${bucket}/author/photo.jpg`),`${backend}/storage/v1/object/sign/${bucket}/author/photo.jpg?token=fixture`);
  assert.equal(request.options.headers.Authorization,'Bearer jwt-A');
 }
 for(const tail of ['/avatars/author/%2e%2e/file.jpg','/stories/author/%2Fother.jpg','/other/author/photo.jpg','/venues/author/photo.jpg?token=unexpected']){
  const f=fixture();await assert.rejects(f.api.reviewMediaSource(f.api.scope(),`${backend}/storage/v1/object/public${tail}`));
 }
});
test('external review media gets no admin token and late signed media is discarded',async()=>{
 let calls=0;const f=fixture(async()=>{calls++;throw Error('Unexpected');});
 assert.equal(await f.api.reviewMediaSource(f.api.scope(),'https://images.test/photo.jpg'),'https://images.test/photo.jpg');assert.equal(calls,0);
 const response=deferred();const g=fixture(async()=>response.promise);const pending=g.api.reviewMediaSource(g.api.scope(),'https://jbbdnpsvstwxtgtjoeru.supabase.co/storage/v1/object/public/avatars/author/p.jpg');
 g.owner('other-owner','other-token');response.resolve(ok({signedURL:'/object/sign/avatars/author/p.jpg?token=fixture'}));
 await assert.rejects(pending,e=>e.constructor.name==='StaleRequest');
});
