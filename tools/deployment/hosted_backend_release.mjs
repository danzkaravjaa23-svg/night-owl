// Builds a reviewable SQL artifact only. No network or database connection.
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const repairFiles=[
  'supabase/migrations/202610160001_social_discovery.sql',
  'supabase/migrations/202610160002_osm_catalog.sql',
  'supabase/migrations/202610200001_hosted_client_rpcs.sql',
];
export async function buildHostedRepair() {
  const bodies=[];
  const files=[];
  for(const file of repairFiles) {
    const source=await readFile(path.join(root,file),'utf8');
    if((source.match(/^begin;$/gm)??[]).length!==1 ||
        (source.match(/^commit;$/gm)??[]).length!==1 || !source.trimEnd().endsWith('commit;')) {
      throw new Error(`Expected one explicit outer transaction: ${file}`);
    }
    files.push({file,sha256:createHash('sha256').update(source).digest('hex')});
    bodies.push(`-- Source: ${file}\n${source.replace(/^begin;$/m,'').replace(/^commit;$/m,'')}`);
  }
  const sql=`-- Night Owl hosted backend repair. Production confirmation required.
-- Scoped public-table backup and catalog snapshot are not a complete DB backup.
-- No Auth accounts, Storage binaries, paid resources or endpoint changes.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
-- Prevent an unbacked relationship cleanup if source state changed since review.
lock table public.blocks,public.follows in share row exclusive mode;
do $$ begin
  if exists(select 1 from public.follows f join public.blocks b on
    (f.follower_id=b.blocker_id and f.following_id=b.blocked_id) or
    (f.follower_id=b.blocked_id and f.following_id=b.blocker_id)) then
    raise exception 'Blocked follow pairs require a fresh scoped backup and review';
  end if;
end $$;
${bodies.join('\n\n')}
commit;
`;
  return {sql,manifest:{files,sha256:createHash('sha256').update(sql).digest('hex')}};
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const {sql,manifest}=await buildHostedRepair();
  const output=path.join(root,'build/hosted-backend-repair');
  await mkdir(output,{recursive:true});
  await writeFile(path.join(output,'repair.sql'),sql);
  await writeFile(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  console.log(JSON.stringify({prepared:true,executed:false,output,...manifest}));
}
