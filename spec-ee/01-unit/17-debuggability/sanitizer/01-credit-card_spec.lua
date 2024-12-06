-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local credit_card_sanitizer = require "kong.enterprise_edition.debug_session.instrumentation.content_capture.sanitizers.credit_card"

local valid_luhn_numbers = {
  "18",
  "885",
  "9894",
  "11114",
  "642587",
  "6543219",
  "68425123",
  "686458126",
  "8451236577",
  "10000000009",
  "499273987168",
  "5865869541251",
  "99895421547857",
  "999999999999994",
  "8888888888888888",
  "11111111111111116",
  "555555555555555551",
  "6587541252302020006",
  "55554444222266660004",
}

local invalid_luhn_numbers = {
  "12312312312312312008",
  "1000000000000000000",
  "100000000000000007",
  "9999999999999994",
  "555555444488597",
  "58545265358423",
  "5854526535841",
  "499273987174",
  "12587412564",
  "2587413694",
  "125689632",
  "25252525",
  "8888744",
  "254723",
  "22222",
  "2222",
  "111",
  "10",
}


describe("Credit card sanitizer spec", function()

  describe("#luhn_validate", function()
    it("passes validation with valid numbers", function()
      for _, num in ipairs(valid_luhn_numbers) do
        assert.is_true(credit_card_sanitizer.luhn_validate(num))
      end
    end)

    it("fails validation with invalid numbers", function()
      for _, num in ipairs(valid_luhn_numbers) do
        -- change last digit from valid numbers to make them invalid
        num = num:sub(1, -2) .. ((tonumber(num:sub(-1)) + 1) % 10)
        assert.is_false(credit_card_sanitizer.luhn_validate(num))
      end

      -- also check that other numbers that are invalid fail validation
      for _, num in ipairs(invalid_luhn_numbers) do
        assert.is_false(credit_card_sanitizer.luhn_validate(num))
      end
    end)

    it("handles invalid character sequences", function()
      assert.is_false(credit_card_sanitizer.luhn_validate("123456789test"))
      assert.is_false(credit_card_sanitizer.luhn_validate("ABCDEFGHIJKLM"))
      assert.is_false(credit_card_sanitizer.luhn_validate("test123456789"))
    end)
  end)

  it("#sanitize", function()
    local original_text = [[ Here are some card numbers to test:
      - This: 4111111111111111 should be redacted, and also: 378282246310005!
      - With dashes: 5555-5555-5555-4444 or 6011-6011-6011-6017
      - With spaces: 4242 4242 4242 4242
      - With mixed formatting: 4000-1234 5678-9017, 3400  0000-0000  009, and 6011111-11111111--7

      - Embedded in text: MyCard4111111111111111? and abcd5555555555554444efgh
      - Broken across lines:
      5105
      1051
      0510
      5100.

      Longer numbers should also be caught:
      555555555555555551 is valid and so is 6221269876543010982.
      Invalid numbers like 4242-4242-4242-4243, 12345, 6221269876543010987 or 9476543010981 should remain unchanged.

      Short numbers with valid checksum should remain unchanged: 94761245847
      And also long ones: 62212698365430109874.
    ]]

    local expected_text = [[ Here are some card numbers to test:
      - This: **************** should be redacted, and also: ***************!
      - With dashes: ******************* or *******************
      - With spaces: *******************
      - With mixed formatting: *******************, ********************, and *******************

      - Embedded in text: MyCard****************? and abcd****************efgh
      - Broken across lines:
      *************************************.

      Longer numbers should also be caught:
      ****************** is valid and so is *******************.
      Invalid numbers like 4242-4242-4242-4243, 12345, 6221269876543010987 or 9476543010981 should remain unchanged.

      Short numbers with valid checksum should remain unchanged: 94761245847
      And also long ones: 62212698365430109874.
    ]]

    local text_after, err = credit_card_sanitizer.sanitize(original_text)
    assert.is_nil(err)
    assert.equals(expected_text, text_after)
  end)
end)
