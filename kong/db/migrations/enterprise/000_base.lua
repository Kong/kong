return {
  postgres = {
    up = [[
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


      CREATE TABLE IF NOT EXISTS rbac_users(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        user_token text UNIQUE NOT NULL,
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
      END$$;

      CREATE TABLE IF NOT EXISTS rbac_user_roles(
        user_id uuid,
        role_id uuid,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY(user_id, role_id)
      );

      CREATE TABLE IF NOT EXISTS rbac_roles(
        id uuid PRIMARY KEY,
        name text UNIQUE NOT NULL,
        is_default boolean default false,
        comment text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('rbac_roles_name_idx')) IS NULL THEN
          CREATE INDEX rbac_roles_name_idx on rbac_roles(name);
        END IF;
      END$$;

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

      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_cluster(
        code_class int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (code_class, duration, at)
      );

      CREATE TABLE IF NOT EXISTS vitals_codes_by_service(
        service_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (service_id, code, duration, at)
      )WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');

      CREATE TABLE IF NOT EXISTS vitals_codes_by_route(
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (route_id, code, duration, at)
      )WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');

      CREATE TABLE IF NOT EXISTS vitals_codes_by_consumer_route(
        consumer_id uuid,
        service_id uuid,
        route_id uuid,
        code int,
        at timestamp with time zone,
        duration int,
        count int,
        PRIMARY KEY (consumer_id, route_id, code, duration, at)
      )
      WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.01');

      CREATE TABLE IF NOT EXISTS vitals_code_classes_by_workspace (
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

      CREATE TABLE IF NOT EXISTS vitals_node_meta(
        node_id uuid PRIMARY KEY,
        first_report timestamp without time zone,
        last_report timestamp without time zone,
        hostname text
      );


      CREATE TABLE IF NOT EXISTS vitals_stats_minutes (
        node_id                 UUID                        NOT NULL,
        at                      INTEGER                     NOT NULL,
        l2_hit                  INTEGER                     DEFAULT 0,
        l2_miss                 INTEGER                     DEFAULT 0,
        plat_min                INTEGER,
        plat_max                INTEGER,
        ulat_min                INTEGER,
        ulat_max                INTEGER,
        requests                INTEGER                     DEFAULT 0,
        plat_count              INTEGER                     DEFAULT 0,
        plat_total              INTEGER                     DEFAULT 0,
        ulat_count              INTEGER                     DEFAULT 0,
        ulat_total              INTEGER                     DEFAULT 0,
        PRIMARY KEY (node_id, at)
      );


      CREATE TABLE IF NOT EXISTS vitals_stats_seconds (
        node_id                 UUID                        NOT NULL,
        at                      INTEGER                     NOT NULL,
        l2_hit                  INTEGER                     DEFAULT 0,
        l2_miss                 INTEGER                     DEFAULT 0,
        plat_min                INTEGER,
        plat_max                INTEGER,
        ulat_min                INTEGER,
        ulat_max                INTEGER,
        requests                INTEGER                     DEFAULT 0,
        plat_count              INTEGER                     DEFAULT 0,
        plat_total              INTEGER                     DEFAULT 0,
        ulat_count              INTEGER                     DEFAULT 0,
        ulat_total              INTEGER                     DEFAULT 0,

        PRIMARY KEY (node_id, at)
      );

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

    ]]
  },

  cassandra = {
    up = [[
      -- TODO


    ]],
  },
}
