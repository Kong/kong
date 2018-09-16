return {
  postgres = {
    -- TODO
    up = [[

    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS cluster_events(
        channel text,
        at      timestamp,
        node_id uuid,
        id      uuid,
        data    text,
        nbf     timestamp,
        PRIMARY KEY (channel, at, node_id, id)
      ) WITH default_time_to_live = 86400;



      CREATE TABLE IF NOT EXISTS services(
        partition       text,
        id              uuid,
        created_at      timestamp,
        updated_at      timestamp,
        name            text,
        host            text,
        path            text,
        port            int,
        protocol        text,
        connect_timeout int,
        read_timeout    int,
        write_timeout   int,
        retries         int,
        PRIMARY KEY     (partition, id)
      );
      CREATE INDEX IF NOT EXISTS services_name_idx ON services(name);



      CREATE TABLE IF NOT EXISTS routes(
        partition      text,
        id             uuid,
        created_at     timestamp,
        updated_at     timestamp,
        hosts          list<text>,
        paths          list<text>,
        methods        set<text>,
        protocols      set<text>,
        preserve_host  boolean,
        strip_path     boolean,
        service_id     uuid,
        regex_priority int,
        PRIMARY KEY    (partition, id)
      );
      CREATE INDEX IF NOT EXISTS routes_service_id_idx ON routes(service_id);



      CREATE TABLE IF NOT EXISTS snis(
        partition          text,
        id                 uuid,
        name               text,
        certificate_id     uuid,
        created_at         timestamp,
        PRIMARY KEY        (partition, id)
      );
      CREATE INDEX IF NOT EXISTS snis_name_idx ON snis(name);
      CREATE INDEX IF NOT EXISTS snis_certificate_id_idx
        ON snis(certificate_id);



      CREATE TABLE IF NOT EXISTS certificates(
        partition text,
        id uuid,
        cert text,
        key text,
        created_at timestamp,
        PRIMARY KEY (partition, id)
      );



      CREATE TABLE IF NOT EXISTS consumers(
        id uuid    PRIMARY KEY,
        created_at timestamp,
        username   text,
        custom_id  text
      );
      CREATE INDEX IF NOT EXISTS consumers_username_idx ON consumers(username);
      CREATE INDEX IF NOT EXISTS consumers_custom_id_idx ON consumers(custom_id);



      CREATE TABLE IF NOT EXISTS plugins(
        id          uuid,
        name        text,
        api_id      uuid,
        config      text,
        consumer_id uuid,
        created_at  timestamp,
        enabled     boolean,
        route_id    uuid,
        service_id  uuid,
        PRIMARY KEY (id, name)
      );
      CREATE INDEX IF NOT EXISTS plugins_name_idx ON plugins(name);
      CREATE INDEX IF NOT EXISTS plugins_api_id_idx ON plugins(api_id);
      CREATE INDEX IF NOT EXISTS plugins_route_id_idx ON plugins(route_id);
      CREATE INDEX IF NOT EXISTS plugins_service_id_idx ON plugins(service_id);
      CREATE INDEX IF NOT EXISTS plugins_consumer_id_idx ON plugins(consumer_id);



      CREATE TABLE IF NOT EXISTS upstreams(
        id                   uuid PRIMARY KEY,
        created_at           timestamp,
        hash_fallback        text,
        hash_fallback_header text,
        hash_on              text,
        hash_on_cookie       text,
        hash_on_cookie_path  text,
        hash_on_header       text,
        healthchecks         text,
        name                 text,
        slots                int
      );
      CREATE INDEX IF NOT EXISTS upstreams_name_idx ON upstreams(name);



      CREATE TABLE IF NOT EXISTS targets(
        id          uuid PRIMARY KEY,
        created_at  timestamp,
        target      text,
        upstream_id uuid,
        weight      int
      );
      CREATE INDEX IF NOT EXISTS targets_upstream_id_idx ON targets(upstream_id);
      CREATE INDEX IF NOT EXISTS targets_target_idx ON targets(target);



      CREATE TABLE IF NOT EXISTS apis(
        id                       uuid PRIMARY KEY,
        created_at               timestamp,
        hosts                    text,
        http_if_terminated       boolean,
        https_only               boolean,
        methods                  text,
        name                     text,
        preserve_host            boolean,
        retries                  int,
        strip_uri                boolean,
        upstream_connect_timeout int,
        upstream_read_timeout    int,
        upstream_send_timeout    int,
        upstream_url             text,
        uris                     text
      );
      CREATE INDEX IF NOT EXISTS apis_name_idx ON apis(name);
    ]],
  },
}
