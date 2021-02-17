-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
      up = [[
        CREATE TABLE IF NOT EXISTS licenses(
              id                uuid PRIMARY KEY,
              payload text,
              created_at        timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone),
              updated_at        timestamp without time zone DEFAULT timezone('utc'::text, ('now'::text)::timestamp(0) with time zone)
        );
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS licenses (
        partition       text,
        id              uuid,
        payload         text,
        created_at      timestamp,
        updated_at      timestamp,
        PRIMARY KEY     (partition, id)
      );
      CREATE INDEX IF NOT EXISTS licenses_payload_idx ON licenses(payload);
    ]],
  },
}
