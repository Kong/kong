local cjson = require "cjson"
local tablex = require "pl.tablex"
local helpers = require "spec.helpers"
local Schema = require "kong.db.schema"
local queue_schema = Schema.new(require "kong.tools.queue_schema")
local queue_parameter_migration_340 = require "kong.db.migrations.core.queue_parameter_migration_340"

describe("Kong Gateway 3.4 queue parameter migration", function()
  local db

  local function load_queue_config()
    local rows, err = db.connector:query([[SELECT config->>'queue' AS queue_config FROM plugins]])
    assert(rows, "SQL query for queue config failed: " .. (err or ""))
    return cjson.decode(rows[1].queue_config)
  end

  local sane_queue_config

  lazy_setup(function()
    -- Create a service to make sure that our database is initialized properly.
    local bp
    bp, db = helpers.get_db_utils()

    db:truncate()

    bp.plugins:insert{
      name = "http-log",
      config = {
        http_endpoint = "http://example.com",
      }
    }

    sane_queue_config = load_queue_config()
  end)

  local function update_plugin_queue_config(queue_config)
    local query = string.format([[
        UPDATE plugins
        SET config = jsonb_set(config, '{queue}', '%s'::jsonb)
        WHERE config->'queue' IS NOT NULL]],
      cjson.encode(queue_config))
    local ok, err = db.connector:query(query)
    assert(ok, "SQL query " .. query .. " failed: " .. (err or ""))
  end

  local function validate_queue_config()
    local queue_config = load_queue_config()
    assert(queue_schema:validate(queue_config))
    return queue_config
  end

  local function run_migration()
    local ok, err = db.connector:query(queue_parameter_migration_340)
    assert(ok, "Running migration failed: " .. (err or ""))
  end

  local function test_one_parameter(key, value, migrated_value)
    local queue_config = tablex.deepcopy(sane_queue_config)
    queue_config[key] = value
    update_plugin_queue_config(queue_config)
    run_migration()
    local migrated_queue_config = validate_queue_config()
    assert.equals(migrated_value, migrated_queue_config[key])
  end

  it("parameters that were previously unrestricted migrated to conform to the restricions", function()
    test_one_parameter("max_batch_size", 120, 120)
    test_one_parameter("max_batch_size", 120.20, 120)
    test_one_parameter("max_entries", 203, 203)
    test_one_parameter("max_entries", 203.20, 203)
    test_one_parameter("max_bytes", 304, 304)
    test_one_parameter("max_bytes", 303.9, 304)
    test_one_parameter("initial_retry_delay", -2000, 0.001)
    test_one_parameter("initial_retry_delay", 0.001, 0.001)
    test_one_parameter("initial_retry_delay", 1000000, 1000000)
    test_one_parameter("initial_retry_delay", 39999999, 1000000)
    test_one_parameter("max_retry_delay", -2000, 0.001)
    test_one_parameter("max_retry_delay", 0.001, 0.001)
    test_one_parameter("max_retry_delay", 1000000, 1000000)
    test_one_parameter("max_retry_delay", 39999999, 1000000)
  end)
end)
