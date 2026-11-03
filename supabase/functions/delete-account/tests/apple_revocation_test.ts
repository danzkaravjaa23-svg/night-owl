// Actual WebCrypto signatures; all Apple HTTP requests are isolated doubles.
import {AppleRevoker, AppleRevocationFailure, digest} from "../apple_revocation.ts";
function assert(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
const encode = (value: unknown) => btoa(JSON.stringify(value)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const b64 = (value: Uint8Array) => btoa(String.fromCharCode(...value)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const decode = (value: string) => Uint8Array.from(atob(value.replace(/-/g,"+").replace(/_/g,"/").padEnd(Math.ceil(value.length/4)*4,"=")),c=>c.charCodeAt(0));
const subject = "fixture.apple.subject";
const audience = "com.nightowl.ub.nightOwlUb";
const now = Date.parse("2026-11-03T07:00:00Z");
const seconds = now/1000;
const rsa = await crypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]);
const secondRsa = await crypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]);
const signing = await crypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8",signing.privateKey));
const config = {clientId:audience,teamId:"TEAM123456",keyId:"KEY1234567",privateKey:`-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`};
async function jwt(extra: Record<string,unknown> = {}, kid="fixture-key", key=rsa.privateKey, header: Record<string,unknown> = {}) {
  const input=encode({alg:"RS256",kid,...header})+"."+encode({iss:"https://appleid.apple.com",aud:audience,sub:subject,iat:seconds,exp:seconds+300,...extra});
  return input+"."+b64(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(input))));
}
async function fixture(options: {exchangeSubject?:string;revokeStatus?:number;missingRefresh?:boolean;largeKeys?:boolean;malformedKeys?:boolean}={}) {
  const nonceHash=await digest("fixture-server-nonce");
  const idToken=await jwt({nonce:nonceHash});
  const exchanges: string[]=[];
  let clock=now;
  let currentRsa=rsa;
  let kid="fixture-key";
  const fetcher: typeof fetch=async (input,init) => {
    const url=String(input);
    assert(init?.redirect==="error","Apple redirects must never be followed");
    assert(!!init.signal,"Apple fetch must be timeout-bounded");
    exchanges.push(url);
    if(url.endsWith("/keys")) {
      if(options.largeKeys)return new Response("x".repeat(65537));
      if(options.malformedKeys)return Response.json({keys:[{kid,kty:"EC",alg:"ES256",use:"sig"}]});
      return Response.json({keys:[{...await crypto.subtle.exportKey("jwk",currentRsa.publicKey),kid,alg:"RS256",use:"sig"}]});
    }
    const form=new URLSearchParams(String(init?.body));
    assert(form.get("client_id")===audience,"Audience must be fixed server config");
    const secret=form.get("client_secret")!.split(".");
    const claims=JSON.parse(new TextDecoder().decode(decode(secret[1])));
    assert(claims.iss===config.teamId && claims.sub===audience && claims.aud==="https://appleid.apple.com","Client secret claims invalid");
    assert(claims.exp-claims.iat===300,"Client secret must be short-lived");
    assert(await crypto.subtle.verify({name:"ECDSA",hash:"SHA-256"},signing.publicKey,decode(secret[2]),new TextEncoder().encode(secret[0]+"."+secret[1])),"Client secret is not a valid ES256 signature");
    if(url.endsWith("/token")) {
      assert(form.get("grant_type")==="authorization_code" && form.get("code")==="fixture-code","Incorrect code exchange");
      return Response.json({id_token:await jwt({sub:options.exchangeSubject??subject}),...(options.missingRefresh?{}:{refresh_token:"fixture-sensitive-refresh-token"})});
    }
    assert(url==="https://appleid.apple.com/auth/revoke","Unexpected remote endpoint");
    assert(form.get("token_type_hint")==="refresh_token" && form.get("token")==="fixture-sensitive-refresh-token","Wrong revocation token");
    return new Response(null,{status:options.revokeStatus??200});
  };
  return {revoker:new AppleRevoker(fetcher,()=>clock),exchanges,idToken,nonceHash,
    rotate(){clock+=31000;currentRsa=secondRsa;kid="rotated-key";},
    advance(){clock+=16*60000;},
  };
}
async function rejects(run:()=>Promise<void>) {
  let rejected=false;
  try {await run();}catch{rejected=true;}
  assert(rejected,"Invalid Apple proof unexpectedly accepted");
}
Deno.test("Apple revocation validates fresh owner+nonce and real ES256 client secret before empty-200 success",async()=>{
  const f=await fixture();
  await f.revoker.revoke(config,{code:"fixture-code",identityToken:f.idToken,subject,nonceHash:f.nonceHash});
  assert(f.exchanges.join(",")==="https://appleid.apple.com/auth/keys,https://appleid.apple.com/auth/token,https://appleid.apple.com/auth/revoke","Unexpected Apple call sequence");
});
for(const [name,claim] of Object.entries({
  issuer:{iss:"https://attacker.invalid"},audience:{aud:"other.app"},subject:{sub:"another.apple.account"},nonce:{nonce:"wrong-nonce"},
  expired:{exp:seconds},future:{iat:seconds+61},stale:{iat:seconds-601},missingExpiry:{exp:null},arrayAudience:{aud:[audience]},
})) Deno.test(`Apple proof rejects ${name} before code exchange or revocation`,async()=>{
  const f=await fixture();
  await rejects(()=>f.revoker.revoke(config,{code:"fixture-code",identityToken:"",subject,nonceHash:f.nonceHash}));
  const token=await jwt({nonce:f.nonceHash,...claim});
  await rejects(()=>f.revoker.revoke(config,{code:"fixture-code",identityToken:token,subject,nonceHash:f.nonceHash}));
  assert(!f.exchanges.some(url=>url.endsWith("/token")||url.endsWith("/revoke")),"Invalid identity reached destructive provider step");
});
Deno.test("Valid owner nonce token paired with another account authorization code never revokes either account",async()=>{
  const f=await fixture({exchangeSubject:"another.apple.account"});
  await rejects(()=>f.revoker.revoke(config,{code:"fixture-code",identityToken:f.idToken,subject,nonceHash:f.nonceHash}));
  assert(!f.exchanges.some(url=>url.endsWith("/revoke")),"Mismatched exchanged subject reached revocation");
});
Deno.test("Invalid signature/algorithm/critical headers cannot reach code exchange",async()=>{
  const f=await fixture();
  const wrong=await jwt({nonce:f.nonceHash},"fixture-key",secondRsa.privateKey);
  await rejects(()=>f.revoker.verifyIdentity(wrong,audience,subject,f.nonceHash));
  for(const header of [{alg:"none"},{crit:["unsupported"]}])await rejects(()=>f.revoker.verifyIdentity(awaitedToken(header),audience,subject));
  function awaitedToken(header:Record<string,unknown>){return encode({kid:"fixture-key",...header})+"."+encode({})+".eA";}
});
Deno.test("Bounded JWKS cache supports rotation and never refetches per bogus key",async()=>{
  const f=await fixture();
  await f.revoker.verifyIdentity(f.idToken,audience,subject,f.nonceHash);
  await f.revoker.verifyIdentity(f.idToken,audience,subject,f.nonceHash);
  await rejects(()=>f.revoker.verifyIdentity(encode({alg:"RS256",kid:"bogus"})+"."+encode({})+".eA",audience,subject));
  assert(f.exchanges.length===1,"Cache or unknown-key throttle failed");
  f.rotate();
  const rotated=await jwt({nonce:f.nonceHash},"rotated-key",secondRsa.privateKey);
  await f.revoker.verifyIdentity(rotated,audience,subject,f.nonceHash);
  assert(Number(f.exchanges.length)===2,"Signing-key rotation did not refresh");
});
for(const options of [{largeKeys:true},{malformedKeys:true},{missingRefresh:true},{revokeStatus:400}])Deno.test(`Apple malformed/failing response cannot report revocation success ${JSON.stringify(options)}`,async()=>{
  const f=await fixture(options);
  await rejects(()=>f.revoker.revoke(config,{code:"fixture-code",identityToken:f.idToken,subject,nonceHash:f.nonceHash}));
});
Deno.test("Missing signing setup fails with a safe actionable code",async()=>{
  const f=await fixture();
  try {await f.revoker.revoke({...config,privateKey:""},{code:"fixture-code",identityToken:f.idToken,subject,nonceHash:f.nonceHash});throw new Error("Expected rejection");}
  catch(error){assert(error instanceof AppleRevocationFailure && error.code==="apple_not_configured","Unsafe or incorrect configuration error");}
});
