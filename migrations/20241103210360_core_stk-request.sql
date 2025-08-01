

-- set session to show stk_superuser as the actor performing all the tasks
SET stk.session = '{\"psql_user\": \"stk_superuser\"}';

CREATE TYPE private.stk_request_type_enum AS ENUM (
    'NOTE',
    'DISCUSS',
    'NOTICE',
    'ACTION',
    'TODO',
    'CHECKLIST'
);
COMMENT ON TYPE private.stk_request_type_enum IS 'Enum used in code to automate and validate wf_request types.';

INSERT INTO private.enum_comment (enum_type, enum_value, comment, is_default) VALUES 
('stk_request_type_enum', 'NOTE', 'Action purpose with no automation or validation', true),
('stk_request_type_enum', 'ACTION', 'Action purpose with no automation or validation', false),
('stk_request_type_enum', 'CHECKLIST', 'Action purpose with no automation or validation', false)
;

CREATE TABLE private.stk_request_type (
  uu UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT GENERATED ALWAYS AS ('stk_request_type') STORED,
  created TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by_uu UUID NOT NULL, -- no FK by convention
  updated TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by_uu UUID NOT NULL, -- no FK by convention
  revoked TIMESTAMPTZ,
  is_revoked BOOLEAN GENERATED ALWAYS AS (revoked IS NOT NULL) STORED,
  is_default BOOLEAN NOT NULL DEFAULT false,
  type_enum private.stk_request_type_enum NOT NULL,
  record_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  search_key TEXT NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT
);
COMMENT ON TABLE private.stk_request_type IS 'Holds the types of stk_request records. To see a list of all stk_request_type_enum enums and their comments, select from api.enum_value where enum_name is stk_request_type_enum.';

CREATE VIEW api.stk_request_type AS SELECT * FROM private.stk_request_type;
COMMENT ON VIEW api.stk_request_type IS 'Holds the types of stk_request records.';

CREATE TABLE private.stk_request (
  uu UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT generated always AS ('stk_request') stored,
  stk_entity_uu UUID NOT NULL REFERENCES private.stk_entity(uu),
  created TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by_uu UUID NOT NULL, -- no FK by convention
  updated TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by_uu UUID NOT NULL, -- no FK by convention
  revoked TIMESTAMPTZ,
  is_revoked BOOLEAN GENERATED ALWAYS AS (revoked IS NOT NULL) STORED,
  table_name_uu_json JSONB NOT NULL DEFAULT '{"table_name": "","uu": ""}'::jsonb,
  is_template BOOLEAN NOT NULL DEFAULT false,
  is_valid BOOLEAN NOT NULL DEFAULT true,
  type_uu UUID NOT NULL REFERENCES private.stk_request_type(uu),
  processed TIMESTAMPTZ,
  is_processed BOOLEAN GENERATED ALWAYS AS (processed IS NOT NULL) STORED,
  record_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  search_key TEXT NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT
);
COMMENT ON TABLE private.stk_request IS 'Holds wf_request records';

CREATE VIEW api.stk_request AS SELECT * FROM private.stk_request;
COMMENT ON VIEW api.stk_request IS 'Holds wf_request records';

select private.stk_trigger_create();
select private.stk_table_type_create('stk_request_type');
