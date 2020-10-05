local operations = require "kong.db.migrations.operations.210_to_211"


return {
  postgres = {
    up = [[]],
  },
  cassandra = {
    up = [[]],
    teardown = function(connector, coordinator)
      return operations.clean_cassandra_fields(connector, coordinator, operations.entities)
    end
  }
}
