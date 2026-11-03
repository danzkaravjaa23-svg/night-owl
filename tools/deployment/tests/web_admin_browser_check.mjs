// Offline UI evidence only: fresh browser profile, fictional rows, every remote
// request intercepted. Requires an installed Playwright and local Chrome binary.
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const output=path.join(root,'build/audit/2026-11-03/admin-refresh');await mkdir(output,{recursive:true});
const original=await readFile(path.join(root,'web/admin/index.html'),'utf8');
const backend=original.match(/const SUPABASE_URL\s*=\s*'([^']+)'/)[1];
const owner='10000000-0000-4000-8000-000000000001';
const author='20000000-0000-4000-8000-000000000001';
const post='30000000-0000-4000-8000-000000000001';
const report='40000000-0000-4000-8000-000000000001';
const fake=`<script>window.__fixtureAuth={session:{user:{id:'${owner}'},access_token:'fixture-token'},listener:null,switchTo(id){this.session=id?{user:{id},access_token:'fixture-next-token'}:null;this.listener('SIGNED_IN',this.session)}};window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:__fixtureAuth.session}}),onAuthStateChange:fn=>{__fixtureAuth.listener=fn},signInWithPassword:async()=>({data:{session:__fixtureAuth.session}}),signOut:async()=>{__fixtureAuth.switchTo(null);return {error:null}}}})};</script>`;
const html=original.replace(/<script src="https:\/\/cdn\.jsdelivr[^>]+><\/script>/,fake).replace('<body>','<body><div style="text-align:center;padding:8px;font-size:12px;color:#b6a4ff">ЖИШЭЭ ӨГӨГДӨЛ · ОФФЛАЙН UI ШАЛГАЛТ</div>');
const server=createServer(async(req,res)=>{
 try {
  const pathname=new URL(req.url,'http://fixture').pathname;
  if(pathname==='/'||pathname==='/admin/') {res.setHeader('Content-Type','text/html;charset=utf-8');res.end(html);return;}
  if(pathname.startsWith('/assets/assets/')) {
   const asset=path.resolve(root,pathname.slice('/assets/'.length));
   if(!asset.startsWith(path.join(root,'assets')+path.sep)) throw new Error('asset path');
   const bytes=await readFile(asset);res.setHeader('Content-Type',asset.endsWith('.webp')?'image/webp':'image/png');res.end(bytes);return;
  }
  res.statusCode=404;res.end();
 } catch(_){res.statusCode=404;res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const page=await browser.newPage({viewport:{width:1280,height:900},deviceScaleFactor:1});
const failures=[],outbound=[];let mutationCalls=0,denyAction=true;
page.on('pageerror',error=>failures.push(error.message));
await page.route('**/*',async route=>{
 const url=new URL(route.request().url());
 if(url.origin===origin) return route.continue();
 if(url.origin!==backend) {outbound.push(url.origin+url.pathname);return route.abort();}
 if(url.pathname.startsWith('/storage/v1/object/sign/posts/') && route.request().method()==='GET') return route.fulfill({contentType:'image/png',body:await readFile(path.join(root,'assets/images/tonight_city.png'))});
 let data;
 const body=route.request().postDataJSON();
 const name=url.pathname.split('/').at(-1);
 if(name==='admin_console_summary') data={actor_id:owner,users:126,posts:48,comments:83,venues:34,events:6,pending_reports:2,banned_users:3};
 else if(name==='admin_console_users') data={items:[{id:author,username:'saruul',full_name:'Жишээ хэрэглэгч',avatar_url:'nightowl://avatar/young-woman',is_admin:false,is_verified:false,is_banned:false,created_at:'2026-11-01T08:00:00Z'}],has_more:false};
 else if(name==='admin_console_reports') data={items:[{id:report,target_type:'post',target_id:post,target_author_id:author,target_excerpt:'Жишээ нийтлэлийн агуулга',reporter_username:'temuulen',reason:'spam',details:'Олон удаа давтсан сурталчилгаа байж болзошгүй.',status:'pending',created_at:'2026-11-03T00:00:00Z'}],has_more:false};
 else if(name==='admin_console_content') data={items:[{id:post,author_id:author,username:'saruul',body:'Хотын шинэ үдэш. Жишээ зурагтай нийтлэл.',media_url:body.p_kind==='post'?`${backend}/storage/v1/object/public/posts/${author}/photo.jpg`:null,created_at:'2026-11-02T12:00:00Z'}],has_more:false};
 else if(name==='admin_console_audit') data={items:[{id:'audit-fixture',actor_username:'admin',action:'resolve_report',target_type:'report',target_id:report,reason:'Агуулгыг шалгаж, зөрчил арилсныг баталгаажуулав.',created_at:'2026-11-03T01:00:00Z'}],has_more:false};
 else if(name==='admin_console_action') {
  mutationCalls++;
  if(denyAction) return route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({code:'40001',message:'Fixture conflict'})});
  data={audit_id:'50000000-0000-4000-8000-000000000001',action:body.p_action,target_type:'report',target_id:body.p_target_id,report_id:body.p_target_id,report_status:'resolved'};
 } else if(url.pathname.startsWith('/storage/v1/object/sign/posts/')) data={signedURL:`/object/sign/posts/${author}/photo.jpg?token=fixture-signed`};
 else {outbound.push(url.pathname);return route.abort();}
 return route.fulfill({contentType:'application/json',body:JSON.stringify(data)});
});
try {
 await page.goto(origin+'/admin/');await page.locator('#app').waitFor({state:'visible'});await page.getByText('Хүлээгдэж буй мэдэгдэл',{exact:true}).waitFor();
 await page.screenshot({path:path.join(output,'web-admin-dashboard-desktop.png'),fullPage:true});
 await page.locator('.nav-btn[data-id="reports"]').click();await page.getByText('Жишээ нийтлэлийн агуулга',{exact:true}).waitFor();
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(output,'web-admin-reports-mobile.png'),fullPage:true});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'mobile document must not overflow horizontally');
 await page.getByRole('button',{name:'Шийдвэрлэсэн болгох',exact:true}).click();
 await page.getByRole('textbox',{name:'Шийдвэрийн шалтгаан'}).fill('Шалгасан бодит үндэслэл');
 await page.screenshot({path:path.join(output,'web-admin-reason-mobile.png'),fullPage:true});
 await page.getByRole('button',{name:'Баталгаажуулах',exact:true}).click();
 await page.getByText('Энэ бүртгэлийн төлөв өөрчлөгдсөн байна. Шинэчлээд дахин шалгана уу.',{exact:true}).waitFor();
 assert.equal(await page.getByText('Жишээ нийтлэлийн агуулга',{exact:true}).count(),1);assert.equal(mutationCalls,1);
 await page.locator('.toast').waitFor({state:'hidden'});
 denyAction=false;
 await page.locator('.nav-btn[data-id="posts"]').click();
 const picture=page.getByAltText('Нийтэлсэн зураг');await picture.waitFor();await picture.evaluate(image=>image.decode());
 assert.equal(await picture.evaluate(image=>image.naturalWidth>0),true);
 await page.screenshot({path:path.join(output,'web-admin-posts-mobile.png'),fullPage:true});
 await page.locator('.nav-btn[data-id="users"]').click();await page.getByText('@saruul',{exact:true}).waitFor();
 await page.setViewportSize({width:320,height:780});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth),false,'320px user row must wrap');
 await page.screenshot({path:path.join(output,'web-admin-users-320.png'),fullPage:true});
 await page.evaluate(()=>__fixtureAuth.switchTo('different-owner'));
 await page.locator('#login').waitFor({state:'visible'});
 assert.equal(await page.locator('#view').textContent(),'');
 assert.equal(await page.getByText('@saruul',{exact:true}).count(),0);
 assert.deepEqual(failures,[]);assert.deepEqual(outbound,[]);
 console.log('PASS: dashboard, responsive 390/320px queues, reason dialog, rejection keeps row, private signed image decoded, account switch hides old data; no outbound requests.');
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
