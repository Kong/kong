return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS rl_counters(
        key          text,
        namespace    text,
        window_start int,
        window_size  int,
        count        int,
        PRIMARY KEY(key, namespace, window_start, window_size)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('sync_key_idx')) IS NULL THEN
          CREATE INDEX sync_key_idx ON rl_counters(namespace, window_start);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS vitals_stats_hours(
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          PRIMARY KEY (at)
      );

      CREATE TABLE IF NOT EXISTS vitals_stats_seconds(
          node_id uuid,
          at integer,
          l2_hit integer default 0,
          l2_miss integer default 0,
          plat_min integer,
          plat_max integer,
          ulat_min integer,
          ulat_max integer,
          requests integer default 0,
          plat_count int default 0,
          plat_total int default 0,
          ulat_count int default 0,
          ulat_total int default 0,
          PRIMARY KEY (node_id, at)
      );



      CREATE TABLE vitals_stats_minutes
      (LIKE vitals_stats_seconds INCLUDING defaults INCLUDING constraints INCLUDING indexes);



      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp without time zone,
        last_report timestamp without time zone,
        hostname text
      );



      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_cluster(
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (code_class, duration, at)
      );



      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (route_id, code, duration, at)
      ) WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');

      CREATE INDEX IF NOT EXISTS vcbr_svc_ts_idx
      ON vitals_codes_by_route(service_id, duration, at);



      CREATE TABLE IF NOT EXISTS vitals_codes_by_consumer_route(
        consumer_id uuid,
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (consumer_id, route_id, code, duration, at)
      ) WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');



      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace(
        workspace_id uuid,
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (workspace_id, code_class, duration, at)
      );



      CREATE TABLE IF NOT EXISTS vitals_locks(
        key text,
        expiry timestamp with time zone,
        PRIMARY KEY(key)
      );
      INSERT INTO vitals_locks(key, expiry)
      VALUES ('delete_status_codes', NULL);



      CREATE TABLE IF NOT EXISTS workspaces (
        id  UUID                  PRIMARY KEY,
        name                      TEXT                      UNIQUE,
        comment                   TEXT,
        created_at                TIMESTAMP WITHOUT TIME ZONE DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        meta                      JSON                      DEFAULT '{}'::json,
        config                    JSON                      DEFAULT '{"portal":false}'::json
      );

      INSERT INTO workspaces(id, name)
      VALUES ('00000000-0000-0000-0000-000000000000', 'default');

      CREATE TABLE IF NOT EXISTS workspace_entities(
        workspace_id uuid,
        workspace_name text,
        entity_id text,
        entity_type text,
        unique_field_name text,
        unique_field_value text,
        PRIMARY KEY(workspace_id, entity_id, unique_field_name)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('workspace_entities_composite_idx')) IS NULL THEN
          CREATE INDEX workspace_entities_composite_idx on workspace_entities(workspace_id, entity_type, unique_field_name);
        END IF;
      END$$;


      CREATE TABLE IF NOT EXISTS workspace_entity_counters(
        workspace_id uuid REFERENCES workspaces (id) ON DELETE CASCADE,
        entity_type text,
        count int,
        PRIMARY KEY(workspace_id, entity_type)
      );


      CREATE TABLE IF NOT EXISTS rbac_users(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        user_token text UNIQUE NOT NULL,
        user_token_ident text UNIQUE NOT NULL,
        comment text,
        enabled boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_users_name_idx')) IS NULL THEN
          CREATE INDEX rbac_users_name_idx on rbac_users(name);
        END IF;
        IF (SELECT to_regclass('rbac_users_token_idx')) IS NULL THEN
          CREATE INDEX rbac_users_token_idx on rbac_users(user_token);
        END IF;
        IF (SELECT to_regclass('idx_rbac_token_ident')) IS NULL THEN
          CREATE INDEX idx_rbac_token_ident on rbac_users(user_token_ident);
        END IF;
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid NOT NULL,
        role_id uuid NOT NULL,
        PRIMARY KEY(user_id, role_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        is_default boolean default false
      );

      CREATE INDEX IF NOT EXISTS rbac_roles_name_idx on rbac_roles(name);
      CREATE INDEX IF NOT EXISTS rbac_role_default_idx on rbac_roles(is_default);

      CREATE TABLE IF NOT EXISTS rbac_role_entities(
        role_id uuid,
        entity_id text,
        entity_type text NOT NULL,
        actions smallint NOT NULL,
        negative boolean NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY(role_id, entity_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_role_endpoints(
        role_id uuid,
        workspace text NOT NULL,
        endpoint text NOT NULL,
        actions smallint NOT NULL,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        negative boolean NOT NULL,
        PRIMARY KEY(role_id, workspace, endpoint)
      );



      CREATE TABLE IF NOT EXISTS files(
        id uuid PRIMARY KEY,
        auth boolean NOT NULL,
        name text UNIQUE NOT NULL,
        type text NOT NULL,
        contents text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS portal_files_name_idx on files(name);



      CREATE TABLE IF NOT EXISTS consumer_statuses (
        id               int PRIMARY KEY,
        name             text NOT NULL,
        comment          text,
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE TABLE IF NOT EXISTS consumer_types (
        id               int PRIMARY KEY,
        name             text NOT NULL,
        comment          text,
        created_at       timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS consumer_statuses_names_idx
          ON consumer_statuses (name);

      CREATE INDEX IF NOT EXISTS consumer_types_name_idx
          ON consumer_types (name);

      INSERT INTO consumer_types(id, name, comment)
      VALUES (2, 'admin', 'Admin consumer.')
      ON CONFLICT DO NOTHING;

      ALTER TABLE consumers
        ADD COLUMN type int NOT NULL DEFAULT 0 REFERENCES consumer_types (id),
        ADD COLUMN email text,
        ADD COLUMN status integer REFERENCES consumer_statuses (id),
        ADD COLUMN meta text;

      ALTER TABLE consumers ADD CONSTRAINT consumers_email_type_key UNIQUE(email, type);

      CREATE INDEX IF NOT EXISTS consumers_type_idx
          ON consumers (type);

      CREATE INDEX IF NOT EXISTS consumers_status_idx
          ON consumers (status);



      CREATE TABLE IF NOT EXISTS credentials (
        id                uuid PRIMARY KEY,
        consumer_id       uuid REFERENCES consumers (id) ON DELETE CASCADE,
        consumer_type     integer REFERENCES consumer_types (id),
        plugin            text NOT NULL,
        credential_data   json,
        created_at        timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
      );

      CREATE INDEX IF NOT EXISTS credentials_consumer_type
        ON credentials (consumer_id);

      CREATE INDEX IF NOT EXISTS credentials_consumer_id_plugin
        ON credentials (consumer_id, plugin);



      CREATE TABLE IF NOT EXISTS consumers_rbac_users_map(
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        user_id uuid REFERENCES rbac_users (id) ON DELETE CASCADE,
        created_at timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
        PRIMARY KEY (consumer_id, user_id)
      );



     CREATE TABLE IF NOT EXISTS token_statuses(
        id integer PRIMARY KEY,
        name text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS token_statuses_name
      ON token_statuses (name);

      INSERT INTO token_statuses(id, name)
      VALUES (1, 'pending')
      ON CONFLICT DO NOTHING;

      INSERT INTO token_statuses(id, name)
      VALUES (2, 'consumed')
      ON CONFLICT DO NOTHING;

      INSERT INTO token_statuses(id, name)
      VALUES (3, 'invalidated')
      ON CONFLICT DO NOTHING;

      CREATE TABLE IF NOT EXISTS consumer_reset_secrets(
        id uuid PRIMARY KEY,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        secret text,
        status integer REFERENCES token_statuses (id),
        client_addr text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        updated_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_consumer_id
      ON consumer_reset_secrets(consumer_id);

      CREATE INDEX IF NOT EXISTS consumer_reset_secrets_status
      ON consumer_reset_secrets(status);



      CREATE TABLE IF NOT EXISTS audit_objects(
        id uuid PRIMARY KEY,
        request_id char(32),
        entity_key uuid,
        dao_name text NOT NULL,
        operation char(6) NOT NULL,
        entity text,
        rbac_user_id uuid,
        signature text,
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_objects_expire')) IS NULL THEN
              CREATE INDEX idx_audit_objects_expire on audit_objects(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_objects() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_objects WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_objects'
                 AND trigger_name = 'deleted_expired_audit_objects_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_objects_trigger
               AFTER INSERT on audit_objects
               EXECUTE PROCEDURE delete_expired_audit_objects();
          END IF;
      END;
      $$;

      CREATE TABLE IF NOT EXISTS audit_requests(
        request_id char(32) PRIMARY KEY,
        request_timestamp timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc'),
        client_ip text NOT NULL,
        path text NOT NULL,
        method text NOT NULL,
        payload text,
        status integer NOT NULL,
        rbac_user_id uuid,
        workspace uuid,
        signature text,
        expire timestamp without time zone
      );

      DO $$
      BEGIN
          IF (SELECT to_regclass('idx_audit_requests_expire')) IS NULL THEN
              CREATE INDEX idx_audit_requests_expire on audit_requests(expire);
          END IF;
      END$$;

      CREATE OR REPLACE FUNCTION delete_expired_audit_requests() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
          DELETE FROM audit_requests WHERE expire <= NOW();
          RETURN NEW;
      END;
      $$;

      DO $$
      BEGIN
          IF NOT EXISTS(
              SELECT FROM information_schema.triggers
               WHERE event_object_table = 'audit_requests'
                 AND trigger_name = 'deleted_expired_audit_requests_trigger')
          THEN
              CREATE TRIGGER delete_expired_audit_requests_trigger
               AFTER INSERT on audit_requests
               EXECUTE PROCEDURE delete_expired_audit_requests();
          END IF;
      END;
      $$;
    ]]
  },
  cassandra = {
    up = [[
      -- TODO
    ]],
  },
}
