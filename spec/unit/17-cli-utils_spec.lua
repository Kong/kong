local dns = require "kong.cli.utils.dns"
local utils = require "kong.tools.utils"

describe("CLI Utils", function()
  describe("DNS", function()
    it("should properly parse the resolv.conf nameserver directive", function()
      assert.falsy(dns.parse_resolv_entry("asd"))
      assert.falsy(dns.parse_resolv_entry("1.1.1.1"))
      assert.falsy(dns.parse_resolv_entry("1.1.1.1:53"))

      local result = dns.parse_resolv_entry("nameserver 1.1.1.1")
      assert.equals("1.1.1.1", result.address)
      assert.equals("1.1.1.1", result.host)
      assert.equals(53, result.port)

      local result = dns.parse_resolv_entry("nameserver 1.1.1.1 #hello")
      assert.equals("1.1.1.1", result.address)
      assert.equals("1.1.1.1", result.host)
      assert.equals(53, result.port)

      local result = dns.parse_resolv_entry("nameserver [1.1.1.1]:8000")
      assert.equals("[1.1.1.1]:8000", result.address)
      assert.equals("1.1.1.1", result.host)
      assert.equals(8000, result.port)

      local result = dns.parse_resolv_entry("nameserver 2001:db8:a0b:12f0::1")
      assert.equals("2001:db8:a0b:12f0::1", result.address)
      assert.equals("2001:db8:a0b:12f0::1", result.host)
      assert.equals(53, result.port)

      local result = dns.parse_resolv_entry("nameserver [2001:db8:a0b:12f0::1]:8000")
      assert.equals("[2001:db8:a0b:12f0::1]:8000", result.address)
      assert.equals("2001:db8:a0b:12f0::1", result.host)
      assert.equals(8000, result.port)

      local result = dns.parse_resolv_entry("    nameserver [2001:db8:a0b:12f0::1]:8000     #hello")
      assert.equals("[2001:db8:a0b:12f0::1]:8000", result.address)
      assert.equals("2001:db8:a0b:12f0::1", result.host)
      assert.equals(8000, result.port)
    end)
    it("should retrieve the first nameserver", function()
      local result = dns.find_first_namespace()
      assert.truthy(result.address)
      assert.truthy(result.host)
      assert.truthy(result.port)
    end)
    it("should parse options", function()
      local result = dns.parse_options_entry("asd")
      assert.falsy(result)

      local result = dns.parse_options_entry("options ")
      assert.falsy(result)

      local result = dns.parse_options_entry("options hello world")
      assert.falsy(result)

      local result = dns.parse_options_entry("options hello timeout:43 world")
      assert.are.same({timeout = 43000}, result)

      local result = dns.parse_options_entry("options hello attempts:4 world")
      assert.are.same({attempts = 4}, result)

      local result = dns.parse_options_entry("options hello attempts:4 world timeout:55")
      assert.are.same({attempts = 4, timeout = 55000}, result)

      local result = dns.parse_options_entry("options hello attempts:4 world timeout:55 #hello")
      assert.are.same({attempts = 4, timeout = 55000}, result)
    end)
    it("should parse /etc/hosts", function()
      local result = dns.parse_etc_hosts()
      assert.truthy(result)
      assert.truthy(utils.table_size(result) > 0)
    end)
  end)
end)
