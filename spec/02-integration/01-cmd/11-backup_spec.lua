local timestamp = require "kong.tools.timestamp"
local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local pl_stringx = require "pl.stringx"
local cjson = require "cjson"
local meta = require "kong.meta"

describe("kong backup", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  before_each(function()
    helpers.dao:drop_schema()
    assert(helpers.dao:run_migrations())
  end)
  after_each(function()
    helpers.clean_prefix()
    helpers.kill_all()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)

  describe("create", function()
    it("creates a valid backup", function()
      assert(helpers.dao.apis:insert {
        request_host = "test.com",
        upstream_url = "http://mockbin.com"
      })

      local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
      assert.matches("backup successfully created", stdout, nil, true)

      -- Make sure the backup really exists
      local lines = pl_stringx.splitlines(stdout)
      local backup_path = ngx.re.match(lines[#lines], [[.+:\s*(.+)]])[1]
      assert.is_string(backup_path)
      assert.truthy(pl_path.exists(backup_path))

      -- Make sure the meta data is correct
      local meta_path = pl_path.join(backup_path, ".kong_backup")
      assert.truthy(pl_path.exists(meta_path))
      local meta_value = cjson.decode(pl_file.read(meta_path))
      assert.is_table(meta_value)
      assert.equal(meta._VERSION, meta_value.version)
    end)
    describe("errors", function()
      it("fails with an empty database", function()
        local ok, err = helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Error: the database is empty", err, nil, true)
      end)
    end)
  end)

  describe("import", function()
    it("imports a backup", function()
      -- Create backup
      assert(helpers.dao.apis:insert {
        request_host = "test.com",
        upstream_url = "http://mockbin.com"
      })
      local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
      assert.matches("backup successfully created", stdout, nil, true)
      
      -- Reset DB
      assert.equal(1, assert(helpers.dao.apis:count()))
      helpers.dao:drop_schema()
      assert(helpers.dao:run_migrations())
      assert.equal(0, assert(helpers.dao.apis:count()))

      -- Import backup
      local backups_path = pl_path.join(helpers.test_conf.prefix, "backups")
      local backup_path = pl_dir.getdirectories(backups_path)[1]
      assert.truthy(backup_path)

      local _, _, stdout = assert(helpers.kong_exec("backup import "..backup_path.." -y --conf "..helpers.test_conf_path))
      assert.matches("backup successfully imported", stdout, nil, true)
      assert.equal(1, assert(helpers.dao.apis:count()))
    end)
    describe("errors", function()
      it("fails without a folder", function()
        local ok, err = helpers.kong_exec("backup import -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Error: must specify the folder path to import", err, nil, true)
      end)
      it("fails with an invalid folder", function()
        local ok, err = helpers.kong_exec("backup import /tmp -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Error: Backup is missing the metadata file", err, nil, true)
      end)
      it("fails when two backups are created at the same time #only", function()
        -- Wait for beginning of next second
        local current_second = timestamp.get_timetable().sec
        while not (timestamp.get_timetable().sec == current_second + 1 or timestamp.get_timetable().sec == 0) do
          -- Wait
        end

        assert(helpers.dao.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        })
        local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
        assert.matches("backup successfully created", stdout, nil, true)

        local ok, stderr = helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Backup already exists at", stderr, nil, true)
      end)
      it("fails without the meta file", function()
        -- Create backup
        assert(helpers.dao.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        })
        local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
        assert.matches("backup successfully created", stdout, nil, true)

        -- Reset DB
        assert.equal(1, assert(helpers.dao.apis:count()))
        helpers.dao:drop_schema()
        assert(helpers.dao:run_migrations())
        assert.equal(0, assert(helpers.dao.apis:count()))

        -- Import backup
        local backups_path = pl_path.join(helpers.test_conf.prefix, "backups")
        local backup_path = pl_dir.getdirectories(backups_path)[1]
        assert.truthy(backup_path)

        -- Delete meta file
        local meta_path = pl_path.join(backup_path, ".kong_backup")
        assert.truthy(pl_path.exists(meta_path))
        pl_file.delete(meta_path)
        assert.falsy(pl_path.exists(meta_path))

        local ok, stderr = helpers.kong_exec("backup import "..backup_path.." -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Backup is missing the metadata file", stderr, nil, true)
        assert.equal(0, assert(helpers.dao.apis:count()))
      end)
      it("fails with a backup for a different version of Kong", function()
        -- Create backup
        assert(helpers.dao.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        })
        local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
        assert.matches("backup successfully created", stdout, nil, true)

        -- Reset DB
        assert.equal(1, assert(helpers.dao.apis:count()))
        helpers.dao:drop_schema()
        assert(helpers.dao:run_migrations())
        assert.equal(0, assert(helpers.dao.apis:count()))

        -- Import backup
        local backups_path = pl_path.join(helpers.test_conf.prefix, "backups")
        local backup_path = pl_dir.getdirectories(backups_path)[1]
        assert.is_string(backup_path)

        -- Delete meta file
        local meta_path = pl_path.join(backup_path, ".kong_backup")
        assert.truthy(pl_path.exists(meta_path))
        local meta_value = cjson.decode(pl_file.read(meta_path))
        meta_value.version = "0.1a"
        pl_file.write(meta_path, cjson.encode(meta_value))

        local ok, stderr = helpers.kong_exec("backup import "..backup_path.." -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("The backup is for a different version of Kong", stderr, nil, true)
        assert.equal(0, assert(helpers.dao.apis:count()))
      end)
      it("fails with an invalid meta file", function()
        -- Create backup
        assert(helpers.dao.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        })
        local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
        assert.matches("backup successfully created", stdout, nil, true)

        -- Reset DB
        assert.equal(1, assert(helpers.dao.apis:count()))
        helpers.dao:drop_schema()
        assert(helpers.dao:run_migrations())
        assert.equal(0, assert(helpers.dao.apis:count()))

        -- Import backup
        local backups_path = pl_path.join(helpers.test_conf.prefix, "backups")
        local backup_path = pl_dir.getdirectories(backups_path)[1]
        assert.truthy(backup_path)

        -- Delete meta file
        local meta_path = pl_path.join(backup_path, ".kong_backup")
        pl_file.write(meta_path, "hello world")

        local ok, stderr = helpers.kong_exec("backup import "..backup_path.." -y --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("Expected value but found invalid token at character 1", stderr, nil, true)
        assert.equal(0, assert(helpers.dao.apis:count()))
      end)
    end)
  end)
end)
