return {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        issuer        text,
        webfinger     text,
        configuration text,
        keys          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (iss)
      );
      CREATE TABLE IF NOT EXISTS oic_issuers (
        hash          text,
        created_at    timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (hash)
      );
    ]],
    down =  [[
      DROP TABLE oic_issuers;
      DROP TABLE oic_revoked;
    ]]
  },
}
