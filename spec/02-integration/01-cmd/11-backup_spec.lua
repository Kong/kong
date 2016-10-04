local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"

describe("kong backup", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  before_each(function()
    helpers.dao:drop_schema()
    assert(helpers.dao:run_migrations())
  end)
  after_each(function()
    helpers.kill_all()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)

  describe("create", function()
    it("creates a backup", function()
      assert(helpers.dao.apis:insert {
        request_host = "test.com",
        upstream_url = "http://mockbin.com"
      })

      local _, _, stdout = assert(helpers.kong_exec("backup create -y --conf "..helpers.test_conf_path))
      assert.matches("backup successfully created", stdout, nil, true)
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
    end)
  end)
end)
