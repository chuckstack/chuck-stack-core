

CREATE TABLE private.stk_trigger_mgt (
  uu UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by_uu uuid,
  updated TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by_uu uuid,
  is_include BOOLEAN NOT NULL DEFAULT false,
  is_exclude BOOLEAN NOT NULL DEFAULT false,
  table_name TEXT[],
  function_name_prefix INTEGER NOT NULL,
  function_name_root TEXT NOT NULL,
  function_event TEXT NOT NULL,
  CONSTRAINT stk_trigger_mgt_function_uidx UNIQUE (function_name_root)
);
COMMENT ON TABLE private.stk_trigger_mgt IS '`stk_trigger_mgt` is a table used to create triggers across mutiple tables. 

- Case when `is_include` and `is_exclude` are both false (default) then `table_name` is ignored and triggers are created on all tables in the `private` schema.
- Case when `is_include` = true then only create triggers for the tables in `table_name` array.
- Case when `is_exclude` = true then create the trigger for the `private` schema tables in `table_name` array.

Here is an example that will result in creating table triggers named stk_"table_name"_tgr_t10100 that call on a function named t10100_stk_change_log() for all tables:

```sql
insert into private.stk_trigger_mgt (function_name_prefix,function_name_root,function_event) values (10100,''stk_change_log'',''BEFORE INSERT OR UPDATE OR DELETE'');
select private.stk_trigger_create();
```

Here is an example that will result in creating table triggers named stk_"table_name"_tgr_t10100 that call on a function named t10100_stk_change_log() for all tables except stk_change_log:

```sql
insert into private.stk_trigger_mgt (function_name_prefix,function_name_root,function_event,is_exclude,table_name) values (10100,''stk_change_log'',''AFTER INSERT OR UPDATE OR DELETE'',true,ARRAY[''stk_change_log'']);
select private.stk_trigger_create();
```

Note that triggers will be created with the `t` prefix because psql does not like it when you create objects that begin with numbers.

Note that triggers are executed in alphabetical order. This is why we have a 0000-9999 number convention to easily create logical regions/sequences of execution.
';

CREATE OR REPLACE FUNCTION private.stk_trigger_create()
RETURNS void AS $$
DECLARE
    table_record_p RECORD;
    trigger_name_p TEXT;
    function_root_p RECORD;
    table_partition_child_v TEXT[];
BEGIN

    -- find all sub-partition tables so that we can exclude them - we only want to add triggers the primary tables
    -- Using inheritance approach here because we need to collect ALL partition children into an array
    -- for bulk exclusion. For single-table checks, using relispartition = true is simpler.
    SELECT coalesce(array_agg(child.relname::TEXT),ARRAY[]::text[])
    INTO table_partition_child_v
    FROM pg_inherits
        JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
        JOIN pg_class child ON pg_inherits.inhrelid = child.oid
        JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
        JOIN pg_namespace nmsp_child ON nmsp_child.oid = child.relnamespace
    WHERE parent.relkind = 'p';

    --RAISE NOTICE 'Partition sub-tables: %', table_partition_child_v;

    -- Loop through all records in stk_trigger_mgt
    FOR function_root_p IN (SELECT * FROM private.stk_trigger_mgt)
    LOOP
        -- Create triggers for tables based on include/exclude logic
        FOR table_record_p IN
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'private'
              AND table_type = 'BASE TABLE'
              AND (
                  (function_root_p.is_exclude = false AND function_root_p.is_include = false)
                  OR
                  (function_root_p.is_include = true AND table_name = ANY(function_root_p.table_name))
                  OR
                  (function_root_p.is_exclude = true AND table_name != ALL(function_root_p.table_name))
              )
              AND table_name != ALL(table_partition_child_v)
        LOOP
            -- Derive the trigger name from the table name and function prefix
            --trigger_name_p := table_record_p.table_name || '_tgr_t' || function_root_p.function_name_prefix::text;
            trigger_name_p := 't' || function_root_p.function_name_prefix::text || '_' || function_root_p.function_name_root::text;

            -- Check if the trigger already exists
            IF NOT EXISTS (
                SELECT 1
                FROM information_schema.triggers
                WHERE trigger_schema = 'private'
                  AND event_object_table = table_record_p.table_name
                  AND trigger_name = trigger_name_p
            ) THEN
                -- Create the trigger if it doesn't exist
                EXECUTE format(
                    'CREATE TRIGGER %I
                     %s ON private.%I
                     FOR EACH ROW EXECUTE FUNCTION private.t%s_%s()',
                    trigger_name_p,
                    function_root_p.function_event,
                    table_record_p.table_name,
                    function_root_p.function_name_prefix,
                    function_root_p.function_name_root
                );

                --RAISE NOTICE 'Created trigger % on table private.%', trigger_name_p, table_record_p.table_name;
            ELSE
                --RAISE NOTICE 'Trigger % already exists on table private.%', trigger_name_p, table_record_p.table_name;
            END IF;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;

COMMENT ON FUNCTION private.stk_trigger_create() IS 'Creates triggers for tables based on stk_trigger_mgt configuration';

select private.stk_trigger_create();

