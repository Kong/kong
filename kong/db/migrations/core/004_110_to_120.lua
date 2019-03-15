return {
  postgres = {
    up = [[

      ALTER TABLE upstreams ADD algorithm text;

    ]],
  },

  cassandra = {
    up = [[

      ALTER TABLE upstreams ADD algorithm text;

    ]],
  },
}
