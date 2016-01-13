require("kong.cli.utils.logger"):set_silent(true) -- Set silent for test

local spec_helper = require "spec.spec_helpers"
local configuration, configuration_path = require("kong.tools.config_loader").load(spec_helper.get_env().conf_file)
local nginx = require("kong.cli.services.nginx")(configuration, configuration_path)

local TIMEOUT = 10

describe("Nginx", function()
 
  setup(function()
    spec_helper.prepare_db()
    nginx:prepare()
  end)

  after_each(function() 
    local prepare_res, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(prepare_res)

    nginx:stop(prepare_res)

    -- Wait for process to quit, with a timeout
    local start = os.time()
    while (nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end
  end)

  it("should prepare", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    assert.truthy(nginx._configuration)
    assert.truthy(type(nginx._configuration) == "table")

    assert.truthy(nginx._configuration_path)
  end)

  it("should start and stop", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    local ok, err = nginx:start()
    assert.truthy(ok)
    assert.falsy(err)
    
    -- Wait for process to start, with a timeout
    local start = os.time()
    while (not nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end
    
    assert.truthy(nginx:is_running())

    -- Trying again will fail
    local ok, err = nginx:start()
    assert.falsy(ok)
    assert.truthy(err)
    assert.equal("nginx is already running", err)

    nginx:stop()

    -- Wait for process to quit, with a timeout
    local start = os.time()
    while (nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end

    assert.falsy(nginx:is_running())
  end)

  it("should stop even when not running", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    assert.falsy(nginx:is_running())
    nginx:stop()

    -- Wait for process to quit, with a timeout
    local start = os.time()
    while (nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end

    assert.falsy(nginx:is_running())
  end)

  it("should quit", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    assert.falsy(nginx:is_running())

    local ok, err = nginx:start()
    assert.truthy(ok)
    assert.falsy(err)

    -- Wait for process to start, with a timeout
    local start = os.time()
    while (not nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end
    
    assert.truthy(nginx:is_running())
    local ok, err = nginx:quit()
    assert.truthy(ok)
    assert.falsy(err)

    -- Wait for process to quit, with a timeout
    local start = os.time()
    while (nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end
    assert.falsy(nginx:is_running())
  end)

  it("should not quit when not running", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    assert.falsy(nginx:is_running())
    local ok, err = nginx:quit()
    assert.falsy(ok)
    assert.truthy(err)

    -- Wait for process to quit, with a timeout
    local start = os.time()
    while (nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end
    assert.falsy(nginx:is_running())
  end)

  it("should reload", function()
    local ok, err = nginx:prepare()
    assert.falsy(err)
    assert.truthy(ok)

    assert.falsy(nginx:is_running())

    local ok, err = nginx:start()
    assert.truthy(ok)
    assert.falsy(err)
    
    -- Wait for process to start, with a timeout
    local start = os.time()
    while (not nginx:is_running() and os.time() < (start + TIMEOUT)) do
      -- Wait
    end

    local pid = nginx:is_running()
    assert.truthy(pid)

    local ok, err = nginx:reload()
    assert.truthy(ok)
    assert.falsy(err)

    local new_pid = nginx:is_running()
    assert.truthy(new_pid)
    assert.truthy(pid == new_pid)
  end)

end)
