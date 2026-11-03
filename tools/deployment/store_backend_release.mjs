// Prepares files only. Never connects to a database, deploys, enables deletion,
// invokes Auth/Storage, creates a job, grants admin identity or schedules a task.
import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const hash=value=>createHash('sha256').update(value).digest('hex');
export const migrations=[
 'supabase/migrations/202611030008_account_erasure.sql',
 'supabase/migrations/202611030009_ugc_review.sql',
];
const checks={
 pre:['tools/deployment/tests/store_backend_preflight.sql',
   'tools/deployment/tests/admin_console_preflight.sql',
   'tools/deployment/tests/admin_console_postflight.sql',
   'tools/deployment/tests/interaction_boundaries_postflight.sql'],
 erasure:'tools/deployment/tests/account_erasure_postflight.sql',
 ugc:'tools/deployment/tests/ugc_review_postflight.sql',
};
export function transactionBody(source,file,readOnly=false){
 const begin=readOnly?/^begin read only;$/gm:/^begin;$/gm;
 if((source.match(begin)??[]).length!==1||(source.match(/^commit;$/gm)??[]).length!==1
   ||!source.trimEnd().endsWith('commit;'))throw new Error(`Expected one explicit transaction: ${file}`);
 return source.replace(begin,'').replace(/^commit;$/m,'').trim();
}

export function validateStorageOrigin(value){
 if(typeof value!=='string')throw new Error('Explicit storageOrigin is required');
 let uri;try{uri=new URL(value);}catch{throw new Error('Invalid Storage origin');}
 const loopback=['localhost','127.0.0.1'].includes(uri.hostname);
 if(value!==uri.origin||uri.username||uri.password||uri.search||uri.hash||
   !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(uri.hostname)||
   !(uri.protocol==='https:'||(uri.protocol==='http:'&&loopback)))throw new Error('Storage origin must be an exact HTTPS origin (HTTP loopback only for isolated tests)');
 return uri.origin;
}

export async function buildStoreBackendRelease({storageOrigin}={}){
 storageOrigin=validateStorageOrigin(storageOrigin);
 const sources=[];
 const read=async file=>{const source=await readFile(path.join(root,file),'utf8');
   sources.push({file,sha256:hash(source),bytes:Buffer.byteLength(source)});return source;};
 const pre=[];
 for(const file of checks.pre)pre.push(`-- Source: ${file}\n${transactionBody(await read(file),file,true)}`);
 const changes=[];
 for(const file of migrations)changes.push(`-- Source: ${file}\n${transactionBody(await read(file),file)}`);
 const erasure=await read(checks.erasure);
 if(!erasure.trimEnd().endsWith('as account_erasure_postflight;'))throw new Error('Unexpected erasure metadata query shape');
 const erasureAssertion=`do $verify_erasure$ declare proof jsonb; k text; begin
 select account_erasure_postflight::jsonb into proof from (${erasure.trimEnd().slice(0,-1)}) metadata;
 foreach k in array array['control_exists','control_security_definer','control_search_path','control_body_matches',
   'service_execute','anon_execute_denied','authenticated_execute_denied','public_execute_denied','private_schema_hidden',
   'journal_rls','journal_direct_access_denied','social_active_body_matches','write_guard_body_matches','storage_write_guard'] loop
   if proof->k is distinct from 'true'::jsonb then raise exception 'Erasure postflight failed: %',k; end if;
 end loop;
 if proof->'unguarded_public_tables' is distinct from '[]'::jsonb then raise exception 'Erasure write guard missing from public tables'; end if;
end $verify_erasure$;`;
 const ugc=transactionBody(await read(checks.ugc),checks.ugc,true);
 const postflight=`-- Read-only invariants. Never selects a job, profile or report row.\nbegin read only;\n${erasureAssertion}\n${ugc}\ncommit;\n`;
 const sql=`-- Night Owl first-install 008+009 release. Review manifest and runbook first.
-- Any assertion/DDL error aborts the whole transaction. Run ROLLBACK after an error.
-- No account deletion is performed or enabled. Existing UGC is grandfathered.
-- The four media buckets become private; deploy the compatible client together.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
set local app.ugc_storage_origin='${storageOrigin.replaceAll("'","''")}';
${pre.join('\n\n')}
${changes.join('\n\n')}
${erasureAssertion}
${ugc}
-- Install must not create a job or turn client roles into RLS bypass roles.
do $$ begin
 if exists(select 1 from account_private.erasure_jobs) then raise exception 'Installation unexpectedly created an erasure job'; end if;
 if exists(select 1 from pg_roles where rolname in ('anon','authenticated') and (rolsuper or rolbypassrls)) then raise exception 'Client roles must not bypass RLS'; end if;
end $$;
commit;
`;
 if((sql.match(/^begin;$/gm)??[]).length!==1||(sql.match(/^commit;$/gm)??[]).length!==1)throw new Error('Bundle transaction boundary mismatch');
 return {sql,postflight,manifest:{prepared:true,executed:false,scope:'First coordinated 008+009 install only',storage_origin:storageOrigin,sources,
   bundle_sha256:hash(sql),postflight_sha256:hash(postflight),
   transaction:{atomic:true,assertions_before_commit:true,lock_timeout:'5s',statement_timeout:'60s'},
   required_before_execution:['Fresh complete metadata export and reviewed recovery reference',
     'Passing exact-bundle tests and disposable hosted acceptance; component tests are not production parity',
     'Review selected reported-message context access for existing active admins',
     'Compatible pending-status, immutable media and private-media client deployment ready'],
   access_change:{actors:'Existing active, non-erasing admin profiles; no new admin identities',
     expands:['Manual public-content review queue','Snapshot of only the specifically reported DM/group message'],
     excludes:['Whole private conversations','New admin accounts','Public media bucket access','Client access to erasure journal']},
   effect_on_existing_data:'Adds moderation metadata (existing content approved); makes four app buckets private; no Auth/application/Storage object deletion',
   activation_not_included:['Edge deployment','ACCOUNT_DELETION_ENABLED','Apple configuration','Scheduled pruning/monitoring','Production client publication'],
   rollback:'Failure before COMMIT rolls back all DDL/metadata changes. After successful commit, keep private buckets and use a forward fix with compatible client; do not restore permissive policies or old client.',
   limits:['No hosted database was contacted','No full production schema parity claimed','Unknown commit outcome requires postflight before retry']}};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length<3||process.argv.length>4)throw new Error('Usage: node tools/deployment/store_backend_release.mjs <storage-origin> [output-directory]');
 const output=path.resolve(process.argv[3]??path.join(root,'build/store-backend-release'));
 const result=await buildStoreBackendRelease({storageOrigin:process.argv[2]});await mkdir(output,{recursive:true});
 await writeFile(path.join(output,'install-008-009.sql'),result.sql);
 await writeFile(path.join(output,'postflight.sql'),result.postflight);
 await writeFile(path.join(output,'manifest.json'),JSON.stringify(result.manifest,null,2)+'\n');
 console.log(JSON.stringify({prepared:true,executed:false,output,bundle_sha256:result.manifest.bundle_sha256,sources:result.manifest.sources.length}));
}
