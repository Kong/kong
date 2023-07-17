-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- this file is used for FIPS tests, to ensure that the FIPS mode is enabled

describe("FIPS mode", function()
  it("is FIPS build", function()
    assert.truthy(require"spec.helpers".is_fips_build())
  end)
end)
