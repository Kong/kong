local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"


local remove = os.remove
local open = io.open
local join = helpers.path.join


describe("File System Vault", function()
  local conf
  local function write_file(path, content)
    local file, err = open(path, "wb")
    if not file then
      return nil, err
    end

    local ok, err = file:write(content)

    file:close()

    if not ok then
      remove(path)
      return nil, err
    end

    return true
  end

  local get = function(reference, content)
    local ref, err = kong.vault.parse_reference(reference)
    if not ref then
      return nil, err
    end

    if not ref.resource then
      return nil, "vault reference has no resource"
    end

    local file_path = join(helpers.test_conf.prefix, ref.resource)

    if content then
      local ok, err = write_file(file_path, content)
      if not ok then
        return nil, err
      end

    else
      remove(file_path)
    end

    return kong.vault.get(reference)
  end

  lazy_setup(function()
    helpers.get_db_utils(nil, {}, nil, { "fs" })
    helpers.prepare_prefix()
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  before_each(function()
    conf = assert(conf_loader(helpers.test_conf_path, {
      vault_fs_prefix = helpers.test_conf.prefix,
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(_G.kong, conf)
  end)

  it("get undefined", function()
    local res, err = get("{vault://fs/test_fs_na}")
    assert.matches("could not get value from external vault", err)
    assert.is_nil(res)
  end)

  it("get empty value", function()
    local res, err = get("{vault://fs/test_fs_empty}", "")
    assert.is_nil(err)
    assert.is_equal(res, "")
  end)

  it("get text", function()
    local res, err = get("{vault://fs/test_env}", "test")
    assert.is_nil(err)
    assert.is_equal("test", res)
  end)

  it("get json", function()
    local json = assert(cjson.encode({
      username = "user",
      password = "pass",
    }))

    local res, err = get("{vault://fs/test_fs_json/username}", json)
    assert.is_nil(err)
    assert.is_equal(res, "user")
    local pw_res, pw_err = get("{vault://fs/test_fs_json/password}", json)
    assert.is_nil(pw_err)
    assert.is_equal(pw_res, "pass")
  end)
end)
