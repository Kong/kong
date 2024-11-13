local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the \"clustering_rpc_requests\" table", function()
    assert.database_has_relation("clustering_rpc_requests")
    assert.table_has_column("clustering_rpc_requests", "id", "bigint")
    assert.table_has_column("clustering_rpc_requests", "node_id", "uuid")
    assert.table_has_column("clustering_rpc_requests", "reply_to", "uuid")
    assert.table_has_column("clustering_rpc_requests", "ttl", "timestamp with time zone")
    assert.table_has_column("clustering_rpc_requests", "payload", "json")
  end)
end)
