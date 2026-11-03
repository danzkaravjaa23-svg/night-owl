// Execute the real Edge handler with SDK doubles, never a server or real account.
// Run: node --experimental-vm-modules --test tools/deployment/tests/delete_account_handler.test.mjs
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {test} from 'node:test';
import {createContext,SourceTextModule,SyntheticModule} from 'node:vm';
import {webcrypto} from 'node:crypto';

const source=await readFile(new URL('../../../supabase/functions/delete-account/index.ts',import.meta.url),'utf8');
const appleSource=await readFile(new URL('../../../supabase/functions/delete-account/apple_revocation.ts',import.meta.url),'utf8');
const caller='10000000-0000-0000-0000-000000000001';
const other='10000000-0000-0000-0000-000000000002';
const internalError='fixture-private-error-detail';
const buckets=['avatars','posts','stories','venues'];
const file=name=>({id:'fixture-object',name});

async function fixture(options={}) {
  const events=[];
  const clients=[];
  let handler;
  const env={SUPABASE_URL:'https://fixture.invalid',SUPABASE_ANON_KEY:'fixture-anon',
    SUPABASE_SERVICE_ROLE_KEY:'fixture-service',ACCOUNT_DELETION_ENABLED:options.disabled?'false':'true'};
  const removed=new Set();
  if(options.unsetEnabled)delete env.ACCOUNT_DELETION_ENABLED;
  if(options.missingCredential)delete env.SUPABASE_SERVICE_ROLE_KEY;
  const context=createContext({Request,Response,crypto:webcrypto,fetch,TextEncoder,TextDecoder,AbortSignal,btoa,atob,Uint8Array,Deno:{
    env:{get:name=>env[name]},serve:value=>{handler=value;},
  }});
  function createClient(url,key,config) {
    assert.equal(url,'https://fixture.invalid');
    if(key==='fixture-anon') {
      clients.push('user');
      return {auth:{getUser:async()=>{
        if(options.authThrows)throw new Error(internalError);
        const valid=config.global.headers.Authorization==='Bearer fixture-token' && !options.invalidUser;
        return {data:{user:valid?{id:Object.hasOwn(options,'userId')?options.userId:caller,identities:options.identities??[],app_metadata:options.metadata??{}}:null},
          error:valid && !options.authError?null:{message:internalError}};
      }}};
    }
    if(key!=='fixture-service')throw new Error(internalError);
    clients.push('admin');
    return {
      rpc:async(_name,params)=>({data:params.p_action==='storage_inventory'?{objects:[]}:{user_id:caller,state:params.p_action==='lookup'?null:params.p_action==='completed'?'completed':'running'},error:null}),
      auth:{admin:{deleteUser:async (userId,shouldSoftDelete)=>{
        assert.equal(shouldSoftDelete,false);
        events.push({kind:'auth_delete',userId});
        if(options.authDeleteThrows)throw new Error(internalError);
        return {data:Object.hasOwn(options,'authDeleteData')?options.authDeleteData:{user:{id:caller}},
          error:options.authDeleteFailure?{message:internalError}:null};
      }}},
      storage:{from:bucket=>{
        assert.ok(buckets.includes(bucket));
        return {
          list:async(prefix,config)=>{
            assert.ok(prefix===caller || prefix.startsWith(caller+'/'));
            assert.equal(config.limit,100);
            assert.deepEqual({...config.sortBy},{column:'name',order:'asc'});
            events.push({kind:'list',bucket,prefix,offset:config.offset});
            if(options.listFailure===bucket)return {data:null,error:{message:internalError}};
            if(Object.hasOwn(options,'listData'))return {data:options.listData,error:null};
            if(events.some(e=>e.kind==='remove')) {
              if(options.verifyListFailure===bucket)return {data:null,error:{message:internalError}};
              if(Object.hasOwn(options,'verifyListData'))return {data:options.verifyListData,error:null};
            }
            const entries=(options.entries?.[bucket+':'+prefix]??[])
              .filter(entry=>!removed.has(bucket+':'+prefix+'/'+entry.name))
              .filter(entry=>entry.id!=null || removed.size===0 ||
                Object.entries(options.entries??{}).some(([key,children])=>
                  (key===bucket+':'+prefix+'/'+entry.name || key.startsWith(bucket+':'+prefix+'/'+entry.name+'/')) &&
                  children.some(child=>child.id!=null && !removed.has(key+'/'+child.name))));
            return {data:entries.slice(config.offset,config.offset+config.limit),error:null};
          },
          remove:async paths=>{
            assert.ok(paths.length>0 && paths.length<=100);
            assert.ok(paths.every(path=>path.startsWith(caller+'/')));
            events.push({kind:'remove',bucket,paths:[...paths]});
            if(options.persistRemovals!==false && options.removeFailure!==bucket) {
              for(const path of paths)removed.add(bucket+':'+path);
              if(options.arrivingObject && !options.arrived) {
                options.entries['venues:'+caller]=[file('late-upload.jpg')];
                options.arrived=true;
              }
            }
            return {data:Object.hasOwn(options,'removeData')?options.removeData:paths.map(name=>({name})),
              error:options.removeFailure===bucket?{message:internalError}:null};
          },
        };
      }},
    };
  }
  const sdk=new SyntheticModule(['createClient'],function(){this.setExport('createClient',createClient);},{context});
  const appleModule=new SourceTextModule(stripTypeScriptTypes(appleSource),{context});
  await appleModule.link(()=>{throw new Error('Unexpected Apple dependency');});
  const module=new SourceTextModule(stripTypeScriptTypes(source),{context});
  await module.link(specifier=>{
    if(specifier==='./apple_revocation.ts')return appleModule;
    assert.equal(specifier,'https://esm.sh/@supabase/supabase-js@2.118.0');
    return sdk;
  });
  await module.evaluate();
  assert.equal(typeof handler,'function');
  return {events,clients,request:async({method='POST',authorization='Bearer fixture-token',body}={})=>{
    const headers={};
    if(authorization!==null)headers.Authorization=authorization;
    return handler(new Request('https://fixture.invalid/delete-account',{method,headers,
      body:body??(method==='POST'?JSON.stringify({confirmation:'DELETE'}):undefined)}));
  }};
}

async function genericFailure(response) {
  assert.equal(response.status,500);
  const payload=await response.json();
  assert.equal(payload.error,'Account deletion failed');
  assert.equal(JSON.stringify(payload).includes(internalError),false);
}

test('OPTIONS does not authenticate or delete',async()=>{
  const f=await fixture();
  const response=await f.request({method:'OPTIONS',authorization:null});
  assert.equal(response.status,200);
  assert.equal(response.headers.get('Access-Control-Allow-Methods'),'POST, OPTIONS');
  assert.deepEqual(f.clients,[]);
  assert.deepEqual(f.events,[]);
});
for(const method of ['GET','PUT','DELETE'])test(method+' cannot delete',async()=>{
  const f=await fixture();
  assert.equal((await f.request({method})).status,405);
  assert.deepEqual(f.clients,[]);
  assert.deepEqual(f.events,[]);
});
test('missing Authorization has no privileged calls',async()=>{
  const f=await fixture();
  assert.equal((await f.request({authorization:null})).status,401);
  assert.deepEqual(f.clients,[]);
  assert.deepEqual(f.events,[]);
});
for(const authorization of ['Basic fixture-token','Bearer','Bearer token extra']) {
  test('invalid authorization scheme is rejected without SDK calls: '+authorization,async()=>{
    const f=await fixture();
    assert.equal((await f.request({authorization})).status,401);
    assert.deepEqual(f.clients,[]);
    assert.deepEqual(f.events,[]);
  });
}
for(const userId of [null,'',caller+'/../'+other]) {
  test('a malformed Auth user id cannot become a storage prefix: '+JSON.stringify(userId),async()=>{
    const f=await fixture({userId});
    assert.equal((await f.request()).status,401);
    assert.equal(f.clients.includes('admin'),false);
    assert.deepEqual(f.events,[]);
  });
}
test('invalid user cannot create a privileged client',async()=>{
  const f=await fixture({invalidUser:true});
  assert.equal((await f.request()).status,401);
  assert.deepEqual(f.clients,['user']);
  assert.deepEqual(f.events,[]);
});
test('authentication exception is generic and does not delete',async()=>{
  const f=await fixture({authThrows:true});
  await genericFailure(await f.request());
  assert.deepEqual(f.events,[]);
});
test('nested paginated files stay caller-scoped; body cannot target someone else',async()=>{
  const entries={['posts:'+caller]:[{id:null,name:'nested'}],
    ['posts:'+caller+'/nested']:Array.from({length:234},(_,i)=>file('photo-'+i+'.jpg'))};
  const f=await fixture({entries});
  const response=await f.request({body:JSON.stringify({confirmation:'DELETE',user_id:other,bucket:'other-users'})});
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{ok:true,user_id:caller});
  assert.deepEqual(f.events.filter(e=>e.kind==='remove').map(e=>e.paths.length),[100,100,34]);
  assert.equal(f.events.filter(e=>e.kind==='remove').flatMap(e=>e.paths).length,234);
  assert.deepEqual(f.events.at(-1),{kind:'auth_delete',userId:caller});
  assert.deepEqual(f.events.filter(e=>e.kind==='list' && e.prefix===caller).map(e=>e.bucket),[...buckets,...buckets]);
});
test('empty media still deletes only the authenticated user',async()=>{
  const f=await fixture();
  assert.equal((await f.request()).status,200);
  assert.equal(f.events.filter(e=>e.kind==='remove').length,0);
  assert.deepEqual(f.events.at(-1),{kind:'auth_delete',userId:caller});
});
test('listing failure keeps Auth account and hides internal errors',async()=>{
  const f=await fixture({listFailure:'avatars'});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
});
for(const listData of [null,{},'not a list',Array.from({length:101},(_,i)=>file('photo-'+i))]) {
  test('malformed storage listing is not interpreted as empty: '+(Array.isArray(listData)?'oversized page':JSON.stringify(listData)),async()=>{
    const f=await fixture({listData});
    const response=await f.request();
    assert.equal(response.status,500);
    assert.equal((await response.json()).code,'deletion_failed');
    assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
  });
}
for(const entry of [null,{id:'file',name:42},{id:0,name:'photo.jpg'},{id:'',name:'photo.jpg'}]) {
  test('malformed storage object is rejected before cleanup: '+JSON.stringify(entry),async()=>{
    const f=await fixture({listData:[entry]});
    await genericFailure(await f.request());
    assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
  });
}
test('duplicate listing entries cannot create an incomplete cleanup plan',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('same.jpg'),file('same.jpg')]}});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
});
test('remove failure stops before Auth deletion and hides internal errors',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},removeFailure:'avatars'});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
});
test('a later listing failure cannot remove earlier bucket media',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},listFailure:'posts'});
  await genericFailure(await f.request());
  assert.equal(f.events.filter(e=>e.kind==='remove').length,0);
  assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
});
test('Auth failure is generic; prior media cleanup is not rolled back',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},authDeleteFailure:true});
  await genericFailure(await f.request());
  // This observes a remaining cross-service failure risk, not atomicity.
  assert.equal(f.events.filter(e=>e.kind==='remove').length,1);
  assert.deepEqual(f.events.at(-1),{kind:'auth_delete',userId:caller});
});
test('thrown Auth deletion error is generic',async()=>{
  const f=await fixture({authDeleteThrows:true});
  await genericFailure(await f.request());
});
test('too-deep folders stop before media removal and Auth deletion',async()=>{
  const entries={};
  let prefix=caller;
  for(let depth=0;depth<9;depth++) {
    entries['avatars:'+prefix]=[{id:null,name:'nested'}];
    prefix+='/nested';
  }
  const f=await fixture({entries});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
});
test('empty folders also have a bounded enumeration budget before cleanup',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:Array.from({length:30001},(_,i)=>({id:null,name:'folder-'+i}))}});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
});
test('20001 flat objects exceed the cleanup cap before removal',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:Array.from({length:20001},(_,i)=>file('photo-'+i+'.jpg'))}});
  await genericFailure(await f.request());
  assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
});
test('exactly 20000 objects are chunked within the cleanup cap',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:Array.from({length:20000},(_,i)=>file('photo-'+i+'.jpg'))}});
  assert.equal((await f.request()).status,200);
  assert.equal(f.events.filter(e=>e.kind==='remove').length,200);
  assert.deepEqual(f.events.at(-1),{kind:'auth_delete',userId:caller});
});
test('missing server credential fails without cleanup',async()=>{
  const f=await fixture({missingCredential:true});
  await genericFailure(await f.request());
  assert.deepEqual(f.events,[]);
});

test('deletion is disabled unless explicitly enabled on the server',async()=>{
  const f=await fixture({disabled:true});
  const response=await f.request();
  assert.equal(response.status,503);
  assert.equal((await response.json()).code,'deletion_unavailable');
  assert.deepEqual(f.clients,[]);
  assert.deepEqual(f.events,[]);
});
test('a missing enable flag also blocks all destructive calls',async()=>{
  const f=await fixture({unsetEnabled:true});
  assert.equal((await f.request()).status,503);
  assert.deepEqual(f.clients,[]);
  assert.deepEqual(f.events,[]);
});
for(const body of ['{}','{"confirmation":true}','{"confirmation":"delete"}','not JSON','']) {
  test('missing or malformed explicit confirmation has no destructive calls: '+JSON.stringify(body),async()=>{
    const f=await fixture();
    const response=await f.request({body});
    assert.equal(response.status,400);
    assert.equal((await response.json()).code,'confirmation_required');
    assert.equal(f.clients.includes('admin'),false);
    assert.deepEqual(f.events,[]);
  });
}
for(const options of [{identities:[{provider:'apple'}]}, {metadata:{providers:['google','apple']}},
    {metadata:{provider:'apple'}}]) {
  test('an Apple-linked account is blocked before cleanup until grant revocation exists: '+JSON.stringify(options),async()=>{
    const f=await fixture(options);
    const response=await f.request();
    assert.equal(response.status,409);
    assert.equal((await response.json()).code,'apple_revocation_required');
    assert.equal(f.clients.includes('admin'),false);
    assert.deepEqual(f.events,[]);
  });
}
test('a getUser error cannot authorize deletion even if a user object exists',async()=>{
  const f=await fixture({authError:true});
  assert.equal((await f.request()).status,401);
  assert.equal(f.clients.includes('admin'),false);
  assert.deepEqual(f.events,[]);
});
test('every bucket is enumerated before the first destructive request',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('avatar.jpg')],['posts:'+caller]:[file('post.jpg')]}});
  assert.equal((await f.request()).status,200);
  const firstRemove=f.events.findIndex(e=>e.kind==='remove');
  assert.deepEqual(f.events.slice(0,firstRemove).filter(e=>e.kind==='list').map(e=>e.bucket),buckets);
  assert.deepEqual(f.events.slice(firstRemove).filter(e=>e.kind==='list').map(e=>e.bucket),buckets);
  assert.equal(f.events.at(-1).kind,'auth_delete');
});
for(const name of ['..','../'+other+'/photo.jpg','nested/photo.jpg','']) {
  test('unexpected storage entry names cannot leave the caller prefix: '+JSON.stringify(name),async()=>{
    const f=await fixture({entries:{['avatars:'+caller]:[file(name)]}});
    await genericFailure(await f.request());
    assert.equal(f.events.some(e=>e.kind==='auth_delete' || e.kind==='remove'),false);
  });
}
test('a cleanup attempt failure is marked potentially incomplete, not rolled back',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('avatar.jpg')]},removeFailure:'avatars'});
  const response=await f.request();
  assert.equal(response.status,500);
  const payload=await response.json();
  assert.equal(payload.code,'deletion_incomplete');
  assert.equal(payload.cleanup_started,true);
});
test('a deliberate retry resumes remaining media after a transient cleanup failure',async()=>{
  const options={entries:{['avatars:'+caller]:[file('avatar.jpg')],['posts:'+caller]:[file('post.jpg')]},
    removeFailure:'posts',persistRemovals:true};
  const f=await fixture(options);
  await genericFailure(await f.request());
  options.removeFailure=null;
  assert.equal((await f.request()).status,200);
  assert.equal(f.events.filter(e=>e.kind==='remove' && e.bucket==='avatars').length,1);
  assert.equal(f.events.filter(e=>e.kind==='auth_delete').length,1);
});

for(const removeData of [null,{},'not a deletion result']) {
  test('malformed successful remove response stops before Auth deletion: '+JSON.stringify(removeData),async()=>{
    const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},removeData});
    const response=await f.request();
    assert.equal(response.status,500);
    assert.equal((await response.json()).code,'deletion_incomplete');
    assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
  });
}
for(const authDeleteData of [null,{}, {user:null}, {user:{}}, {user:{id:other}}]) {
  test('Auth deletion must confirm the caller before reporting success: '+JSON.stringify(authDeleteData),async()=>{
    const f=await fixture({authDeleteData});
    const response=await f.request();
    assert.equal(response.status,500);
    assert.equal((await response.json()).code,'deletion_incomplete');
  });
}
test('successful Storage no-op cannot erase Auth while media remains',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},
    persistRemovals:false,removeData:[]});
  const response=await f.request();
  assert.equal(response.status,500);
  assert.equal((await response.json()).code,'deletion_incomplete');
  assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
});
test('an upload observed after cleanup blocks Auth deletion',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},arrivingObject:true});
  const response=await f.request();
  assert.equal(response.status,500);
  assert.equal((await response.json()).code,'deletion_incomplete');
  assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
});

for(const options of [{verifyListFailure:'venues'},{verifyListData:null},{verifyListData:{}}]) {
  test('failed final Storage verification cannot erase Auth: '+JSON.stringify(options),async()=>{
    const f=await fixture({...options,entries:{['avatars:'+caller]:[file('photo.jpg')]}});
    const response=await f.request();
    assert.equal(response.status,500);
    assert.equal((await response.json()).code,'deletion_incomplete');
    assert.equal(f.events.some(e=>e.kind==='auth_delete'),false);
  });
}
test('an idempotent remove response is accepted only after empty-prefix verification',async()=>{
  const f=await fixture({entries:{['avatars:'+caller]:[file('photo.jpg')]},removeData:[]});
  assert.equal((await f.request()).status,200);
  assert.equal(f.events.at(-1).kind,'auth_delete');
});
