local auth_helpers = require "kong.enterprise_edition.auth_helpers"

describe("ee auth helpers", function()
  local function check(pwd, opts)
    return auth_helpers.check_password_complexity(pwd, nil, opts)
  end

  it("custom rules should work as expect", function()
    -- password require at least 8 chars
    local complexity = { min = "disabled,disabled,8,8,8" }

    assert.is_nil(check("$Pa27ss", complexity))
    assert(check("$Pa228ss", complexity))
  end)

  it("presets should override custom rules", function()
    local complexity = {
      min = "disabled,disabled,8,8,8",
      ["kong-preset"] = "min_12",
    }

    -- password should be invalid with the length of '8'
    -- since validation is preset 'min_12'
    assert.is_nil(check("$Pa27ss", complexity))
  end)
 
  describe("check_password():", function()
    it("expect the password is fine", function()
      assert(check("new2!pas$Word", { ["kong-preset"] = "min_12" }))
    end)

    it("preset: password length limitation", function()
      local invalid_lengths = {
        min_8         = { "$Pa27Ss", 7 },
        min_12        = { "$hortPa11ss", 11 },
        min_20        = { "$hortPa9sssSsssssss", 19 },
        too_long_pwd  = { "ThisIsA$uperLongPa$$Word", 39 },
      }

      -- gernerate a max length password
      while #invalid_lengths.too_long_pwd[1] <= invalid_lengths.too_long_pwd[2] do
        invalid_lengths.too_long_pwd[1] = invalid_lengths.too_long_pwd[1] .. 
                                          invalid_lengths.too_long_pwd[1]
      end

      -- expect password invalid
      for k, v in pairs(invalid_lengths) do
        local preset = "min_12"

        if k ~= "too_long_pwd" then
          preset = k
          assert.same(#v[1], v[2])
        end

        assert.is_nil(check(v[1], { ["kong-preset"] = preset }))
      end
    end)

    it("preset: password must have at least 3 categories", function()
      local invalid_types = {
        dig_pwd = "0123456789101112",
        low_pwd = "abcdefghijklmnop",
        cap_pwd = "ABCDEFGHIJKLMNOP",
        spe_pwd = "~!@#$%^&*()_+~!@",
      }

      -- expect 2 combos invalid
      for k1, v1 in pairs(invalid_types) do
        for k2, v2 in pairs(invalid_types) do
          if k1 ~= k2 then
            assert.is_nil(check(v1..v2, { ["kong-preset"] = "min_12" }))
          end
        end
      end

      for _,v in pairs(invalid_types) do
        assert.is_nil(check(v, { ["kong-preset"] = "min_12" }))
      end
    end)
  end)
end)
