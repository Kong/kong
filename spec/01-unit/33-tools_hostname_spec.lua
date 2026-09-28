-- NOTE: is_valid_hostname uses kong.tools.ip.check_hostname internally,
-- which is more permissive than strict RFC 952/1123 validation.
-- This allows underscores and other characters to support all possible
-- gethostname() return values.

local hostname = require "kong.tools.hostname"


describe("kong.tools.hostname", function()
  describe("is_valid_hostname()", function()

    it("rejects nil hostname", function()
      local ok = hostname.is_valid_hostname(nil)
      assert.is_false(ok)
    end)

    it("rejects empty string hostname", function()
      local ok = hostname.is_valid_hostname("")
      assert.is_false(ok)
    end)

    describe("valid hostnames", function()
      local valid_hostnames = {
        "a",                              -- single character
        "a1",                             -- two characters
        "host",                           -- simple hostname
        "hostname",                       -- single word
        "host-name",                      -- with hyphen in middle
        "host123",                        -- alphanumeric
        "123host",                        -- starting with number
        "host.example.com",               -- FQDN
        "sub.domain.example.com",         -- multi-level FQDN
        "host-123.example-456.com",       -- complex FQDN with hyphens
        "a-b.c-d.e-f",                    -- all labels with hyphens
        "192-168-1-1",                    -- numeric-like but valid
        "xn--n3h",                        -- punycode (internationalized domain)
        "host_name",                      -- underscore (allowed by check_hostname)
        "host_.example.com",              -- underscore in label
        "_host.example.com",              -- label starts with underscore
        "my_server_01",                   -- realistic underscore hostname
        "host.example.com.",              -- FQDN with trailing dot
      }

      for _, valid_hostname in ipairs(valid_hostnames) do
        it("accepts valid hostname: " .. valid_hostname, function()
          local ok = hostname.is_valid_hostname(valid_hostname)
          assert.is_true(ok, "should accept '" .. valid_hostname .. "'")
        end)
      end
    end)

    describe("invalid hostnames - format violations", function()
      local invalid_hostnames = {
        { "hostname-",                    "ends with hyphen" },
        { ".hostname",                    "starts with dot" },
        { "host-.name",                   "label ends with hyphen" },
        { "host..name",                   "consecutive dots" },
        { "host...name",                  "multiple consecutive dots" },
        { "host name",                    "contains space" },
        { "host\tname",                   "contains tab" },
        { "host\nname",                   "contains newline" },
        { "host@example.com",             "contains @ symbol" },
        { "host#name",                    "contains # symbol" },
        { "host$name",                    "contains $ symbol" },
        { "host%name",                    "contains % symbol" },
        { "host&name",                    "contains & symbol" },
        { "host*name",                    "contains * symbol" },
        { "host+name",                    "contains + symbol" },
        { "host=name",                    "contains = symbol" },
        { "host!name",                    "contains ! symbol" },
        { "host?name",                    "contains ? symbol" },
        { "host/name",                    "contains / symbol" },
        { "host\\name",                   "contains \\ symbol" },
        { "host|name",                    "contains | symbol" },
        { "host:name",                    "contains : symbol" },
        { "host;name",                    "contains ; symbol" },
        { "host'name",                    "contains ' symbol" },
        { "host\"name",                   "contains \" symbol" },
        { "host<name",                    "contains < symbol" },
        { "host>name",                    "contains > symbol" },
        { "host,name",                    "contains , symbol" },
      }

      for _, test_case in ipairs(invalid_hostnames) do
        local invalid_hostname, description = test_case[1], test_case[2]
        it("rejects invalid hostname (" .. description .. "): " .. invalid_hostname, function()
          local ok = hostname.is_valid_hostname(invalid_hostname)
          assert.is_false(ok, "should reject '" .. invalid_hostname .. "'")
        end)
      end
    end)

    describe("invalid hostnames - security concerns", function()
      local malicious_hostnames = {
        { 'host"; DROP TABLE test; --',   "SQL injection attempt" },
        { "host'; DELETE FROM users; --", "SQL injection with single quote" },
        { "../../../etc/passwd",          "path traversal attempt" },
        { "host`cmd`",                    "command injection with backticks" },
        { "host$(cmd)",                   "command injection with $()" },
        { "host&cmd&",                    "command injection with &" },
        { "host|cmd",                     "pipe injection" },
        { "host;cmd",                     "semicolon command separator" },
      }

      for _, test_case in ipairs(malicious_hostnames) do
        local malicious_hostname, description = test_case[1], test_case[2]
        it("rejects malicious hostname (" .. description .. "): " .. malicious_hostname, function()
          local ok = hostname.is_valid_hostname(malicious_hostname)
          assert.is_false(ok, "should reject '" .. malicious_hostname .. "'")
        end)
      end
    end)

    describe("edge cases", function()
      it("accepts single character hostname", function()
        local ok = hostname.is_valid_hostname("a")
        assert.is_true(ok, "should accept single character")
      end)

      it("accepts two character hostname", function()
        local ok = hostname.is_valid_hostname("ab")
        assert.is_true(ok, "should accept two characters")
      end)

      it("accepts hostname starting with number", function()
        local ok = hostname.is_valid_hostname("1host")
        assert.is_true(ok, "should accept hostname starting with number")
      end)

      it("accepts hostname ending with number", function()
        local ok = hostname.is_valid_hostname("host1")
        assert.is_true(ok, "should accept hostname ending with number")
      end)

      it("accepts all-numeric hostname segments", function()
        local ok = hostname.is_valid_hostname("192-168-1-1")
        assert.is_true(ok, "should accept numeric-like hostname")
      end)

      it("accepts hostname with underscores", function()
        local ok = hostname.is_valid_hostname("my_server_01")
        assert.is_true(ok, "should accept hostname with underscores")
      end)

      it("accepts FQDN with trailing dot", function()
        local ok = hostname.is_valid_hostname("example.com.")
        assert.is_true(ok, "should accept FQDN with trailing dot")
      end)
    end)

  end)
end)
