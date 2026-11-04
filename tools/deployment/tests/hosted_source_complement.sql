-- PostgreSQL 17 metadata complement for both the source and a proposed target.
-- Read-only: no application, Auth, or Storage object rows are selected. The only
-- non-catalog rows are six configuration fields for the four named app buckets.
-- Private function definitions are metadata. Definitions carrying any function
-- setting other than search_path are withheld; custom setting values are never
-- emitted. Managed auth/storage/vault function bodies are not selected.
-- This is an inventory, not authorization to alter either database. Compare the
-- result with the separately verified project identities before any deployment.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '3s';

DO $bounds$
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'Metadata complement requires PostgreSQL 17 catalogs';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname IN ('public', 'admin_private', 'account_private')) > 1000
     OR (SELECT coalesce(sum(octet_length(p.prosrc)), 0)
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('admin_private', 'account_private')) > 2097152
     OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('public', 'admin_private', 'account_private')) > 1000
     OR (SELECT count(*) FROM pg_attribute a
         JOIN pg_class c ON c.oid = a.attrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('public', 'admin_private', 'account_private')
           AND a.attnum > 0 AND NOT a.attisdropped) > 10000
     OR (SELECT count(*) FROM pg_extension) > 100
     OR (SELECT count(*) FROM pg_publication) > 100
     OR (SELECT count(*) FROM pg_publication_rel) > 5000
     OR (SELECT count(*) FROM pg_publication_namespace) > 5000
     OR (SELECT count(*) FROM pg_publication_tables) > 5000
     OR (SELECT count(*) FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('public', 'admin_private', 'account_private', 'auth', 'storage')
           AND NOT t.tgisinternal) > 2000 THEN
    RAISE EXCEPTION 'Metadata complement exceeds its bounded inventory scope';
  END IF;
END;
$bounds$;

WITH
app_relations AS MATERIALIZED (
  SELECT c.*, n.nspname
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('public', 'admin_private', 'account_private')
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
),
app_functions AS MATERIALIZED (
  SELECT p.*, n.nspname,
    ARRAY(SELECT split_part(setting, '=', 1)
          FROM unnest(p.proconfig) AS setting ORDER BY 1) AS setting_names,
    NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) AS setting
                WHERE split_part(setting, '=', 1) <> 'search_path') AS safe_settings,
    (SELECT e.extname FROM pg_depend d JOIN pg_extension e ON e.oid = d.refobjid
     WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
       AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e') AS extension_name
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'admin_private', 'account_private')
),
function_inventory AS (
  SELECT nspname AS schema_name, proname AS name, prokind AS kind,
    pg_get_function_identity_arguments(oid) AS identity_arguments,
    pg_get_function_arguments(oid) AS arguments,
    pg_get_function_result(oid) AS result,
    pg_get_userbyid(proowner) AS owner, prosecdef AS security_definer,
    proacl::text[] AS acl, extension_name, setting_names,
    ARRAY(SELECT substring(setting FROM length('search_path=') + 1)
          FROM unnest(proconfig) AS setting
          WHERE split_part(setting, '=', 1) = 'search_path') AS search_path,
    CASE WHEN nspname IN ('admin_private', 'account_private')
                   AND safe_settings AND prokind IN ('f', 'p', 'w')
         THEN pg_get_functiondef(oid) END AS private_definition,
    CASE WHEN nspname = 'public' THEN 'public definitions are in the main capture'
         WHEN NOT safe_settings THEN 'withheld: non-search_path function setting'
         WHEN prokind NOT IN ('f', 'p', 'w') THEN 'unsupported routine kind'
         ELSE NULL END AS definition_note
  FROM app_functions
),
collations AS (
  SELECT c.nspname AS schema_name, c.relname AS relation_name,
    a.attnum AS column_position, a.attname AS column_name,
    format_type(a.atttypid, a.atttypmod) AS column_type,
    cn.nspname AS collation_schema, co.collname AS collation_name,
    co.collprovider AS provider, co.collisdeterministic AS deterministic,
    co.collencoding AS encoding, co.collcollate AS lc_collate,
    co.collctype AS lc_ctype, co.colllocale AS locale,
    co.collicurules AS icu_rules, co.collversion AS recorded_version
  FROM app_relations c JOIN pg_attribute a ON a.attrelid = c.oid
  JOIN pg_collation co ON co.oid = a.attcollation
  JOIN pg_namespace cn ON cn.oid = co.collnamespace
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
replica_identities AS (
  SELECT c.nspname AS schema_name, c.relname AS relation_name,
    c.relkind AS kind, c.relpersistence AS persistence,
    c.relreplident AS replica_identity,
    (SELECT i.relname FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid
     WHERE x.indrelid = c.oid AND x.indisreplident) AS identity_index,
    (SELECT i.relname FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid
     WHERE x.indrelid = c.oid AND x.indisprimary) AS primary_key_index
  FROM app_relations c WHERE c.relkind IN ('r', 'p')
),
triggers AS (
  SELECT n.nspname AS schema_name, c.relname AS relation_name,
    t.tgname AS name, t.tgenabled AS enabled,
    fn.nspname AS function_schema, p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS function_identity_arguments
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace fn ON fn.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'admin_private', 'account_private', 'auth', 'storage')
    AND NOT t.tgisinternal
)
SELECT jsonb_build_object(
  'format', 'night-owl-hosted-metadata-complement-v1',
  'scope', 'catalog metadata and four named bucket configurations; no user or object rows',
  'captured_at', transaction_timestamp(),
  'postgres_version', current_setting('server_version'),
  'database', (
    SELECT jsonb_build_object(
      'name', d.datname, 'encoding', pg_encoding_to_char(d.encoding),
      'locale_provider', d.datlocprovider, 'lc_collate', d.datcollate,
      'lc_ctype', d.datctype, 'locale', d.datlocale,
      'icu_rules', d.daticurules, 'recorded_collation_version', d.datcollversion)
    FROM pg_database d WHERE d.datname = current_database()),
  'extensions', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.name), '[]'::jsonb)
    FROM (SELECT e.extname AS name, e.extversion AS version, n.nspname AS schema_name
          FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace) x),
  'trigram_opclasses', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.schema_name, x.name), '[]'::jsonb)
    FROM (SELECT n.nspname AS schema_name, o.opcname AS name, am.amname AS access_method,
                 format_type(o.opcintype, NULL) AS input_type, o.opcdefault AS is_default,
                 e.extname AS extension_name
          FROM pg_opclass o JOIN pg_namespace n ON n.oid = o.opcnamespace
          JOIN pg_am am ON am.oid = o.opcmethod
          LEFT JOIN pg_depend dep ON dep.classid = 'pg_opclass'::regclass
            AND dep.objid = o.oid AND dep.refclassid = 'pg_extension'::regclass AND dep.deptype = 'e'
          LEFT JOIN pg_extension e ON e.oid = dep.refobjid
          WHERE o.opcname IN ('gin_trgm_ops', 'gist_trgm_ops')) x),
  'column_collations', (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.schema_name, c.relation_name, c.column_position), '[]'::jsonb) FROM collations c),
  'app_replica_identity', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.schema_name, r.relation_name), '[]'::jsonb) FROM replica_identities r),
  'app_buckets', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id), '[]'::jsonb)
    FROM (SELECT b.id, b.name, b.public, b.file_size_limit, b.allowed_mime_types, b.type::text AS type
          FROM storage.buckets b WHERE b.id IN ('avatars', 'posts', 'stories', 'venues')) x),
  'publications', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.name), '[]'::jsonb)
    FROM (SELECT p.pubname AS name, pg_get_userbyid(p.pubowner) AS owner,
                 p.puballtables AS all_tables, p.pubinsert AS publish_insert,
                 p.pubupdate AS publish_update, p.pubdelete AS publish_delete,
                 p.pubtruncate AS publish_truncate, p.pubviaroot AS publish_via_partition_root
          FROM pg_publication p) x),
  'publication_explicit_tables', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.publication, x.schema_name, x.table_name), '[]'::jsonb)
    FROM (SELECT p.pubname AS publication, n.nspname AS schema_name, c.relname AS table_name,
                 pr.prattrs::smallint[] AS column_positions,
                 pg_get_expr(pr.prqual, pr.prrelid) AS row_filter
          FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid
          JOIN pg_class c ON c.oid = pr.prrelid JOIN pg_namespace n ON n.oid = c.relnamespace) x),
  'publication_schemas', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.publication, x.schema_name), '[]'::jsonb)
    FROM (SELECT p.pubname AS publication, n.nspname AS schema_name
          FROM pg_publication_namespace pn JOIN pg_publication p ON p.oid = pn.pnpubid
          JOIN pg_namespace n ON n.oid = pn.pnnspid) x),
  'publication_effective_tables', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.publication, x.schema_name, x.table_name), '[]'::jsonb)
    FROM (SELECT pubname AS publication, schemaname AS schema_name,
                 tablename AS table_name, attnames AS columns, rowfilter AS row_filter
          FROM pg_publication_tables) x),
  'function_counts', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.schema_name), '[]'::jsonb)
    FROM (SELECT nspname AS schema_name, count(*) AS total,
                 count(*) FILTER (WHERE extension_name IS NULL) AS non_extension
          FROM app_functions GROUP BY nspname) x),
  'functions', (SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.schema_name, f.name, f.identity_arguments), '[]'::jsonb) FROM function_inventory f),
  'trigger_counts', (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.schema_name), '[]'::jsonb)
    FROM (SELECT schema_name, count(*) AS total FROM triggers GROUP BY schema_name) x),
  'triggers', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.schema_name, t.relation_name, t.name), '[]'::jsonb) FROM triggers t)
) AS metadata;

COMMIT;
