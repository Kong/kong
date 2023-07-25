-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers" -- initializes 'kong' global for vaults
local conf_loader = require "kong.conf_loader"
local cjson = require "cjson"
local fmt = string.format

for _, strategy in helpers.each_strategy() do

  describe("GCP Secret Manager Vault #" .. strategy, function()
    local get
    local GCP_SERVICE_ACCOUNT
    local project_id = "kong-test-project"

    lazy_setup(function()
      -- parse `GCP_SERVICE_ACCOUNT` env
      GCP_SERVICE_ACCOUNT = os.getenv("GCP_SERVICE_ACCOUNT")
      if GCP_SERVICE_ACCOUNT then
        project_id = cjson.decode(GCP_SERVICE_ACCOUNT).project_id
      end
    end)

    before_each(function()
      -- prevent being overridden
      if GCP_SERVICE_ACCOUNT then
        helpers.setenv("GCP_SERVICE_ACCOUNT", GCP_SERVICE_ACCOUNT)
      end

      local conf = assert(conf_loader(nil))

      local kong_global = require "kong.global"
      _G.kong = kong_global.new()
      kong_global.init_pdk(kong, conf)

      get = _G.kong.vault.get
    end)

    it("check GCP_SERVICE_ACCOUNT validity", function()
      helpers.setenv("GCP_SERVICE_ACCOUNT", "")
      local res, err = get("{vault://gcp/test?project_id=test}")
      assert.is_nil(res)
      assert.equals("could not get value from external vault (no value found (GCP_SERVICE_ACCOUNT invalid (invalid service account)))", err)
    end)

    it("missing gcp project_id", function()
      local res, err = get("{vault://gcp/test}")
      assert.is_nil(res)
      assert.matches("gcp secret manager requires project_id", err)
    end)

    --- Below tests must be run with `GCP_SERVICE_ACCOUNT` set to a valid service account
    it("get undefined #flaky", function()
      -- helpers.setenv("GCP_SERVICE_ACCOUNT", GCP_SERVICE_ACCOUNT)
      local res, err = get(fmt("{vault://gcp/test?project_id=%s}", project_id))
      assert.is_nil(res)
      assert.matches("code : 404, status: NOT_FOUND", err)
    end)

    it("empty value returns 404 #flaky", function()
      local res, err = get(fmt("{vault://gcp/test_empty?project_id=%s}", project_id))
      assert.is_nil(res)
      assert.matches("code : 404, status: NOT_FOUND", err)
    end)

    it("get text #flaky", function()
      local res, err = get(fmt("{vault://gcp/db-password-3?project_id=%s}", project_id))
      assert.is_nil(err)
      assert.same(res, "kongdbpassword")
    end)

    it("get json #flaky", function()
      local res, err = get(fmt("{vault://gcp/test_json/username?project_id=%s}", project_id))
      assert.is_nil(err)
      assert.is_equal(res, "user")
      local pw_res, pw_err = get(fmt("{vault://gcp/test_json/password?project_id=%s}", project_id))
      assert.is_nil(pw_err)
      assert.is_equal(pw_res, "pass")
    end)
  end)

end
