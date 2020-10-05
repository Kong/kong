local operations = require "kong.db.migrations.operations.210_to_211"


local plugin_entities = {
  {
    name = "oauth2_credentials",
    unique_keys = {"client_id"},
  },
  {
    name = "oauth2_authorization_codes",
    unique_keys = {"code"},
  },
  {
    name = "oauth2_tokens",
    unique_keys = {"access_token", "refresh_token"},
  },
}


return {
  postgres = {
    up = [[]],
  },
  cassandra = {
    up = [[]],
    teardown = function(connector, connection)
      return operations.clean_cassandra_fields(connector, connection, plugin_entities)
    end
  }
}
