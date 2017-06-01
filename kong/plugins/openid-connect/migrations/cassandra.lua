return {
  {
    name = "2017-06-01-180000_init_oic",
    up = [[
      CREATE TABLE IF NOT EXISTS oic_issuers (
        issuer        text,
        webfinger     text,
        configuration text,
        keys          text,
        created_at    timestamp,
        PRIMARY KEY (iss)
      );
      CREATE TABLE IF NOT EXISTS oic_revoked (
        hash          text,
        created_at    timestamp,
        PRIMARY KEY (hash)
      );
    ]],
    down = [[
      DROP TABLE oic_issuers;
      DROP TABLE oic_revoked;
    ]]
  },
}
