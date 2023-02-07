-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mp    = require 'MessagePack'
local ltn12 = require 'ltn12'

describe("gcsnapshot", function ()
  it("arg #1 must be a string", function ()
    assert.has_error(function ()
      gcsnapshot({})
    end, "bad argument #1 to 'gcsnapshot' (string expected, got table)")
  end)

  it("arg #2 must be a number", function ()
    assert.has_error(function ()
      gcsnapshot(os.tmpname(), "foo")
    end, "bad argument #2 to 'gcsnapshot' (number expected, got string)")
  end)

  it("snapshot header", function ()
    local path = os.tmpname()
    assert(gcsnapshot(path))

    local data = ltn12.source.file(io.open(path, 'rb'))
    local _, header = mp.unpacker(data)()

    assert(type(header.gcsize) == "number", "expected gcsize to be a number")
    assert.same({
      major = 1,
      minor = 0,
      patch = 0,
      string = "1.0.0"
    }, header.version)
  end)

  it("dump a complex table", function ()
    math.randomseed()
    local path = os.tmpname()
    local target = {
      rand_str = tostring(math.random()) .. tostring(math.random()),
      rand_num = math.random(2e20),
      rand_bool = math.random() > 0.5,
      [1] = math.random(2e20),
      [2] = math.random(2e20),
      [3] = math.random(2e20),
    }
    local ok, err = gcsnapshot(path)

    assert(ok, err)

    local data = ltn12.source.file(io.open(path, 'rb'))
    local found
    local hit
    for _, v in mp.unpacker(data) do
      hit = 0
      found = {
        rand_str = false,
        rand_num = false,
        rand_bool = false,
        [1] = false,
        [2] = false,
        [3] = false,
      }

      if v.type ~= "table" then
        goto continue
      end

      if #(v.hash) < 2 * 3 then
        goto continue
      end

      local array = v.array

      --[[
        array[1] is the index 0 in C code when dumping a table,
        so we need to skip it.
      --]]
      for i = 2, #array do
        if array[i].type == "number" and array[i].value == target[i - 1] then
          found[i - 1] = true
          hit = hit + 1
        end
      end

      local hash = {}

      for i = 1, #v.hash, 2 do
        hash[v.hash[i]] = v.hash[i + 1]
      end

      for kk, vv in pairs(hash) do
        if kk.type == "string" then
          if kk.value == "rand_str" then
            if vv.type == "string" and vv.value == target.rand_str then
              found.rand_str = true
              hit = hit + 1
            end
          end

          if kk.value == "rand_num" then
            if vv.type == "number" and vv.value == target.rand_num then
              found.rand_num = true
              hit = hit + 1
            end
          end

          if kk.value == "rand_bool" then
            if vv.type == "boolean" and vv.value == target.rand_bool then
              found.rand_bool = true
              hit = hit + 1
            end
          end
        end

        -- some number index and it's value may be in the hash part
        if kk.type == "number" then
          if kk.value == 1 then
            if vv.type == "number" and vv.value == target[1] then
              found[1] = true
              hit = hit + 1
            end
          end

          if kk.value == 2 then
            if vv.type == "number" and vv.value == target[2] then
              found[2] = true
              hit = hit + 1
            end
          end

          if kk.value == 3 then
            if vv.type == "number" and vv.value == target[3] then
              found[3] = true
              hit = hit + 1
            end
          end
        end
      end

      if hit == 6 then
        break
      end

      ::continue::
    end

    assert.same({
      rand_str = true,
      rand_num = true,
      rand_bool = true,
      [1] = true,
      [2] = true,
      [3] = true,
    }, found, "expected to find all values in the snapshot")
  end)
end)