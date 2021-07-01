-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jq_request_filter_schema = require "kong.plugins.jq-request-filter.schema"
local validate = require("spec.helpers").validate_plugin_config_schema

describe("jq-request-filter schema", function()
  it("rejects empty config", function()
    local ok, err = validate({}, jq_request_filter_schema)
		assert.is_falsy(ok)
		assert.same("required field missing", err.config.filters)
	end)
end)
