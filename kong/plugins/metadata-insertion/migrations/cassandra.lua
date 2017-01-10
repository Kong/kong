return {
  {
    name = "2017-01-05-000000_init_metadata",
    up =  [[
      CREATE TABLE IF NOT EXISTS metadata_keyvaluestore(
        id uuid,
        consumer_id uuid,
        key text,
        value text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON metadata_keyvaluestore(key);
      CREATE INDEX IF NOT EXISTS metadata_keyvaluestore_consumer_id ON metadata_keyvaluestore(consumer_id);
    ]],
    down = [[
      DROP TABLE metadata_keyvaluestore;
    ]]
  }
}
