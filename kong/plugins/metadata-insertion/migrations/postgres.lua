return {
  {
    name = "2017-01-05-000000_init_metadata",
    up = [[
      CREATE TABLE IF NOT EXISTS metadata_keyvaluestore(
        id uuid,
        consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
        key text,
        value text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id)
      );

      DO $$
      BEGIN
        IF (SELECT to_regclass('metadata_keyvaluestore_key_idx')) IS NULL THEN
          CREATE INDEX metadata_keyvaluestore_key_idx ON metadata_keyvaluestore(key);
        END IF;
        IF (SELECT to_regclass('metadata_keyvaluestore_consumer_idx')) IS NULL THEN
          CREATE INDEX metadata_keyvaluestore_consumer_idx ON metadata_keyvaluestore(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE metadata_keyvaluestore;
    ]]
  }
}
