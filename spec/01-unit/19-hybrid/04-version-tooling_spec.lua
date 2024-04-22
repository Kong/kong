-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local version = require("kong.clustering.compat.version")

local string_to_number = version.string_to_number
local number_to_string = version.number_to_string
local extract_major_minor = version.extract_major_minor


local test_map = {
  -- major versions
  ["0.0.0.0"]  = 0,
  ["3.8.0.0"]  = 3008000000,
  ["4.0.0.0"]  = 4000000000,
  -- future proofing
  ["10.0.0.0"] = 10000000000,
  ["10.1.2.3"] = 10001002003,
  -- minor versions
  ["0.9.0.0"]  = 0009000000,
  ["2.3.0.0"]  = 2003000000,
  ["3.7.0.0"]  = 3007000000,
  -- patch versions
  ["0.3.0.0"]  = 0003000000,
  ["2.3.3.0"]  = 2003003000,
  ["3.0.4.0"]  = 3000004000,
  -- build versions
  ["3.0.4.1"]  = 3000004001,
  ["3.7.4.2"]  = 3007004002,
  ["3.0.0.3"]  = 3000000003,
}

describe("version.number_to_string", function()
  for k, v in pairs(test_map) do
    it(string.format("should correctly convert string %s to number %s", v, k), function()
      assert.equal(k, number_to_string(v))
    end)
  end
end)

describe("version.string_to_number", function()
  for k, v in pairs(test_map) do
    it(string.format("should correctly convert string %s to number %s", k, v), function()
      assert.equal(v, string_to_number(k))
    end)
  end
end)


local test_map_major_minor = {
  ["0.0.0"]  = { 0, 0 },
  ["3.8.0"]  = { 3, 8 },
  ["4.0.0"]  = { 4, 0 },
  ["10.1.2"] = { 10, 1 },
}

describe("version.extract_major_minor", function()
  for k, v in pairs(test_map_major_minor) do
    it(string.format("should correctly extract major and minor versions from %s", k), function()
      local major, minor = extract_major_minor(k)
      assert.equal(v[1], major)
      assert.equal(v[2], minor)
    end)
  end
end)
