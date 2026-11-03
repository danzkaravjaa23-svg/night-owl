// Production Edge entry + real pinned Supabase SDK + actual Apple signatures.
// Supabase is a loopback double, Apple HTTP is intercepted before any network.
import {digest} from "../apple_revocation.ts";
const owner="10000000-0000-0000-0000-000000000001";
const subject="fixture.apple.subject";
const nativeId="com.nightowl.ub.nightOwlUb";
const webId="com.nightowl.ub.web";
function assert(value:unknown,message:string):asserts value{if(!value)throw new Error(message);}
const json=(body:unknown,status=200)=>Response.json(body,{status});
const b64=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const encode=(data:unknown)=>b64(new TextEncoder().encode(JSON.stringify(data)));
Deno.test("owner-bound prepare/delete/receipt recovery protocol without real accounts",async(t)=>{
  const rsa=await crypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]);
  const signing=await crypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
  const pem=`-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8",signing.privateKey))))}\n-----END PRIVATE KEY-----`;
  let job:Record<string,unknown>={state:null};
  let linked=true,authDeleted=false,failAuth=false,failCompletion=false,exchangeSubject=subject,lateSubject=false;
  let authReads=0;
  let lastSignIn="2026-10-22T00:00:00Z";
  const files=new Set<string>();
  const calls:string[]=[];
  const appleCalls:string[]=[];
  async function token(sub=subject,audience=nativeId,nonce?:string){
    const now=Math.floor(Date.now()/1000);
    const input=encode({alg:"RS256",kid:"protocol-key"})+"."+encode({iss:"https://appleid.apple.com",aud:audience,sub,iat:now,exp:now+300,...(nonce?{nonce}:{} )});
    return input+"."+b64(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",rsa.privateKey,new TextEncoder().encode(input))));
  }
  const server=Deno.serve({hostname:"127.0.0.1",port:0,onListen(){}},async(req)=>{
    const path=new URL(req.url).pathname;calls.push(req.method+" "+path);
    if(path==="/auth/v1/user"){
      authReads++;
      if(authDeleted||req.headers.get("Authorization")!=="Bearer fixture-owner")return json({message:"Invalid account"},401);
      return json({id:owner,aud:"authenticated",created_at:"2026-10-22T00:00:00Z",last_sign_in_at:lastSignIn,identities:linked?[{provider:"apple",identity_data:{sub:lateSubject&&authReads>1?"late-linked-subject":subject}}]:[],app_metadata:linked?{providers:["apple"]}:{}});
    }
    assert(req.headers.get("Authorization")==="Bearer fixture-service","Privileged key must be server-only");
    if(path==="/rest/v1/rpc/account_erasure_control"){
      const body=await req.json();
      if(body.p_action==="lookup")return json(job);
      if(body.p_action==="prepare"){
        const revoked=body.p_nonce_hash===null&&job.apple_subject===body.p_subject?job.apple_revoked_at:null;
        job={...job,user_id:owner,state:job.state??"prepared",receipt_hash:body.p_receipt_hash,nonce_hash:body.p_nonce_hash,apple_subject:body.p_subject,apple_audience:body.p_audience,apple_revoked_at:revoked,nonce_expires_at:new Date(Date.now()+300000).toISOString()};
        return json(job);
      }
      if(body.p_receipt_hash!==job.receipt_hash||(body.p_user&&body.p_user!==job.user_id))return json({code:"P0002",message:"Receipt missing"},404);
      if(body.p_action==="claim"){
        if(job.state==="running")return json({code:"55P03",message:"Running"},409);
        job.state="running";
      }
      if(body.p_action==="apple_revoked")job.apple_revoked_at=new Date().toISOString();
      if(body.p_action==="storage_inventory")return json({objects:[...files].map(name=>({bucket_id:"posts",name}))});
      if(body.p_action==="storage_cleared")job.storage_cleared_at=new Date().toISOString();
      if(body.p_action==="cleanup")job.database_cleared_at=new Date().toISOString();
      if(body.p_action==="completed"){
        if(failCompletion){failCompletion=false;return json({code:"500",message:"fixture-private-journal-error"},503);}
        job.state="completed";
      }
      if(body.p_action==="failed")job.state="failed";
      if(body.p_action==="reconcile"&&authDeleted&&job.storage_cleared_at&&job.database_cleared_at)job.state="completed";
      return json(job);
    }
    if(path.startsWith("/storage/v1/object/list/")){
      const bucket=path.split("/").at(-1);const body=await req.json();
      if(bucket!=="posts")return json([]);
      return json([...files].filter(name=>name.startsWith(body.prefix+"/")).slice(body.offset,body.offset+100).map(name=>({id:"fixture-object",name:name.slice(body.prefix.length+1)})));
    }
    if(path.startsWith("/storage/v1/object/")&&req.method==="DELETE"){
      const body=await req.json();for(const name of body.prefixes){assert(files.has(name),"Cleanup escaped metadata-proven ownership");files.delete(name);}return json([]);
    }
    if(path===`/auth/v1/admin/users/${owner}`&&req.method==="DELETE"){
      if(failAuth)return json({message:"fixture-private-auth-error"},503);
      authDeleted=true;return json({id:owner,aud:"authenticated",created_at:"2026-10-22T00:00:00Z"});
    }
    return json({message:"Unexpected local path"},404);
  });
  const originalFetch=globalThis.fetch;
  globalThis.fetch=async(input,init)=>{
    const url=input instanceof Request?input.url:String(input);
    if(!url.startsWith("https://appleid.apple.com/"))return originalFetch(input,init);
    appleCalls.push(url);
    if(url.endsWith("/keys"))return json({keys:[{...await crypto.subtle.exportKey("jwk",rsa.publicKey),kid:"protocol-key",alg:"RS256",use:"sig"}]});
    const form=new URLSearchParams(String(init?.body));
    if(url.endsWith("/token")){
      assert(form.get("code")==="fixture-authorization-code","Unexpected Apple code");
      return json({id_token:await token(exchangeSubject,form.get("client_id")!),refresh_token:"fixture-sensitive-refresh"});
    }
    assert(url.endsWith("/revoke")&&form.get("token")==="fixture-sensitive-refresh","Unexpected revocation");return new Response(null,{status:200});
  };
  for(const [name,value]of Object.entries({SUPABASE_URL:`http://127.0.0.1:${server.addr.port}`,SUPABASE_ANON_KEY:"fixture-anon",SUPABASE_SERVICE_ROLE_KEY:"fixture-service",ACCOUNT_DELETION_ENABLED:"true",APPLE_CLIENT_ID:nativeId,APPLE_WEB_CLIENT_ID:webId,APPLE_WEB_REDIRECT_URI:"https://fixture.test/apple-return",APPLE_TEAM_ID:"TEAM123456",APPLE_KEY_ID:"KEY1234567",APPLE_PRIVATE_KEY:pem}))Deno.env.set(name,value);
  let handler:((req:Request)=>Promise<Response>)|undefined;
  const descriptor=Object.getOwnPropertyDescriptor(Deno,"serve")!;
  try{
    Object.defineProperty(Deno,"serve",{configurable:descriptor.configurable,enumerable:descriptor.enumerable,writable:true,value:(value:typeof handler)=>{handler=value;return {};}});
    await import("../index.ts");
    Object.defineProperty(Deno,"serve",descriptor);
    const invoke=(body:Record<string,unknown>,authorization:string|null="Bearer fixture-owner")=>handler!(new Request("http://127.0.0.1/delete-account",{method:"POST",headers:authorization?{Authorization:authorization}:{},body:JSON.stringify({confirmation:"DELETE",...body})}));
    const reset=()=>{job={state:null};linked=true;authDeleted=false;failAuth=false;failCompletion=false;exchangeSubject=subject;lateSubject=false;authReads=0;lastSignIn="2026-10-22T00:00:00Z";files.clear();calls.length=0;appleCalls.length=0;};
    const prepare=async(platform="native")=>{
      const response=await invoke({action:"prepare",client_platform:platform});assert(response.status===200,"Preparation failed");return await response.json();
    };
    const deletion=async(prepared:Record<string,unknown>,platform="native",sub=subject)=>invoke({action:"delete",client_platform:platform,receipt_token:prepared.receipt_token,apple_code:"fixture-authorization-code",apple_identity_token:await token(sub,platform==="web"?webId:nativeId,await digest(prepared.nonce as string))});
    await t.step("prepare returns a nonce but writes no media/Auth deletion and stores hashes only",async()=>{
      reset();const p=await prepare();assert(p.user_id===owner&&p.apple_required===true,"Incorrect prepare response");
      assert(job.receipt_hash===await digest(p.receipt_token)&&job.nonce_hash===await digest(p.nonce),"Raw receipt/nonce persisted or hashes differ");
      assert(!calls.some(call=>call.startsWith("DELETE"))&&appleCalls.length===0,"Preparation became destructive");
    });
    await t.step("native reauthorization revokes correct Apple identity then erases caller and legacy owned path",async()=>{
      reset();files.add(owner+"/post.jpg");files.add("legacy/owned-photo.jpg");const p=await prepare();const r=await deletion(p);
      assert(r.status===200&&(await r.json()).user_id===owner,"Native erasure failed");assert(files.size===0&&authDeleted&&job.apple_revoked_at,"Erasure/checkpoint incomplete");
      assert(appleCalls.some(url=>url.endsWith("/revoke")),"Apple authorization was not revoked");
    });
    await t.step("web Services ID uses the configured redirect and same owner-bound proof",async()=>{
      reset();const p=await prepare("web");assert(p.client_id===webId&&p.redirect_uri==="https://fixture.test/apple-return","Web options must come from server");
      assert((await deletion(p,"web")).status===200,"Web erasure failed");
    });
    await t.step("another Apple account token cannot authorize deleting or revoking either identity",async()=>{
      reset();const p=await prepare();assert((await deletion(p,"native","another-apple-subject")).status===409,"Mismatched subject accepted");
      assert(!authDeleted&&!appleCalls.some(url=>url.endsWith("/revoke"))&&!calls.some(call=>call.startsWith("DELETE")),"Invalid Apple proof reached deletion");
    });
    await t.step("owner identity token cannot be combined with another account code",async()=>{
      reset();const p=await prepare();exchangeSubject="other-code-owner";assert((await deletion(p)).status===409,"Mixed code/token accepted");
      assert(!authDeleted&&!appleCalls.some(url=>url.endsWith("/revoke")),"Wrong code revoked another account");
    });
    await t.step("expired server nonce cannot reach Apple exchange or any erasure",async()=>{
      reset();const p=await prepare();job.nonce_expires_at=new Date(Date.now()-1).toISOString();assert((await deletion(p)).status===409,"Expired challenge accepted");assert(!calls.some(call=>call.startsWith("DELETE")),"Expired challenge reached deletion");
    });
    await t.step("confirmed Apple revoke survives later Auth failure and retry skips a new authorization",async()=>{
      reset();const p=await prepare();failAuth=true;assert((await deletion(p)).status===500,"Synthetic Auth failure missing");assert(job.apple_revoked_at&&!authDeleted,"Revocation checkpoint lost");
      failAuth=false;const revokeCount=appleCalls.filter(url=>url.endsWith("/revoke")).length;const retry=await prepare();assert(retry.apple_required===false,"Retry incorrectly requires Apple grant again");
      const result=await invoke({action:"delete",receipt_token:retry.receipt_token});assert(result.status===200&&authDeleted,"Retry failed");assert(appleCalls.filter(url=>url.endsWith("/revoke")).length===revokeCount,"Retry revoked twice");
    });
    await t.step("receipt-only status reconciles lost completion after Auth deletion",async()=>{
      reset();linked=false;const p=await prepare();failCompletion=true;const result=await invoke({action:"delete",receipt_token:p.receipt_token});assert(result.status===500&&authDeleted,"Completion failure fixture missing");
      const recovered=await invoke({action:"status",receipt_token:p.receipt_token},null);assert(recovered.status===200&&(await recovered.json()).user_id===owner,"Receipt recovery failed after Auth became unavailable");
      const again=await invoke({action:"status",receipt_token:p.receipt_token},null);assert(again.status===200,"Recovery not idempotent");
    });
    await t.step("a later sign-in cannot reuse a checkpoint for an earlier Apple authorization",async()=>{
      reset();const p=await prepare();failAuth=true;assert((await deletion(p)).status===500,"Auth failure missing");
      await new Promise(resolve=>setTimeout(resolve,2));lastSignIn=new Date().toISOString();
      const fresh=await prepare();assert(fresh.apple_required===true&&job.apple_revoked_at==null,"New authorization reused stale revoked grant checkpoint");
    });
    await t.step("a receipt can inspect state but never begin deletion without a valid caller JWT",async()=>{
      reset();linked=false;const p=await prepare();assert((await invoke({action:"delete",receipt_token:p.receipt_token},null)).status===401,"Receipt bypassed initiating authentication");
      assert((await invoke({action:"status",receipt_token:p.receipt_token},null)).status===202&&!authDeleted,"Prepared status became deletion");
      assert((await invoke({action:"status",receipt_token:"z".repeat(43)},null)).status===404,"Unknown receipt disclosed state");
    });
    await t.step("new Apple identity linked through Auth before final erasure aborts hard deletion",async()=>{
      reset();const p=await prepare();authReads=0;lateSubject=true;assert((await deletion(p)).status===409&&!authDeleted,"Late linked grant escaped final Auth identity check");
      assert(job.apple_revoked_at,"Original revocation checkpoint should remain recoverable");
    });
    await t.step("oversized request is rejected before Auth/admin calls",async()=>{
      reset();const response=await invoke({action:"prepare",padding:"x".repeat(32769)});assert(response.status===400&&calls.length===0,"Unbounded request reached privileged work");
    });
  }finally{Object.defineProperty(Deno,"serve",descriptor);globalThis.fetch=originalFetch;await server.shutdown();}
});
