-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("ee meta", function()
    local ee_meta = require "kong.enterprise_edition.meta"
    local ce_meta = require "kong.meta"
  
    describe("versions", function()
  
      it("version always starts with CE version", function()
        assert.equal(ce_meta.version, string.sub(ee_meta.version, 1, #ce_meta.version))
      end)
  
    end)
  end)