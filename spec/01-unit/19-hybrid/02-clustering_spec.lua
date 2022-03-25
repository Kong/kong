local clustering = require("kong.clustering")


describe("kong.clustering", function()
  describe(".calculate_config_hash()", function()
    it("calculating hash for nil errors", function()
      local pok = pcall(clustering.calculate_config_hash, clustering, nil)
      assert.falsy(pok)
    end)

    it("calculates hash for null", function()
      local value = ngx.null

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("5bf07a8b7343015026657d1108d8206e", hash)
      end

      local correct = ngx.md5("/null/")
      assert.equal("5bf07a8b7343015026657d1108d8206e", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for number", function()
      local value = 10

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("d3d9446802a44259755d38e6d163e820", hash)
      end

      local correct = ngx.md5("10")
      assert.equal("d3d9446802a44259755d38e6d163e820", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for double", function()
      local value = 0.9

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("a894124cc6d5c5c71afe060d5dde0762", hash)
      end

      local correct = ngx.md5("0.9")
      assert.equal("a894124cc6d5c5c71afe060d5dde0762", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for empty string", function()
      local value = ""

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("d41d8cd98f00b204e9800998ecf8427e", hash)
      end

      local correct = ngx.md5("")
      assert.equal("d41d8cd98f00b204e9800998ecf8427e", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for string", function()
      local value = "hello"

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("5d41402abc4b2a76b9719d911017c592", hash)
      end

      local correct = ngx.md5("hello")
      assert.equal("5d41402abc4b2a76b9719d911017c592", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for boolean false", function()
      local value = false

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("68934a3e9455fa72420237eb05902327", hash)
      end

      local correct = ngx.md5("false")
      assert.equal("68934a3e9455fa72420237eb05902327", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for boolean true", function()
      local value = true

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("b326b5062b2f0e69046810717534cb09", hash)
      end

      local correct = ngx.md5("true")
      assert.equal("b326b5062b2f0e69046810717534cb09", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculating hash for function errors", function()
      local pok = pcall(clustering.calculate_config_hash, clustering, function() end)
      assert.falsy(pok)
    end)

    it("calculating hash for thread errors", function()
      local pok = pcall(clustering.calculate_config_hash, clustering, coroutine.create(function() end))
      assert.falsy(pok)
    end)

    it("calculating hash for userdata errors", function()
      local pok = pcall(clustering.calculate_config_hash, clustering, io.tmpfile())
      assert.falsy(pok)
    end)

    it("calculating hash for cdata errors", function()
      local pok = pcall(clustering.calculate_config_hash, clustering, require "ffi".new("char[6]", "foobar"))
      assert.falsy(pok)
    end)

    it("calculates hash for empty table", function()
      local value = {}

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("aaf38faf0b5851d711027bb4d812d50d", hash)
      end

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("aaf38faf0b5851d711027bb4d812d50d", hash)
      end
    end)

    it("calculates hash for complex table", function()
      local value = {
        plugins = {
          { name = "0", config = { param = "value"}},
          { name = "1", config = { param = { "v1", "v2", "v3", "v4", "v5", "v6" }}},
          { name = "2", config = { param = { "v1", "v2", "v3", "v4", "v5" }}},
          { name = "3", config = { param = { "v1", "v2", "v3", "v4" }}},
          { name = "4", config = { param = { "v1", "v2", "v3" }}},
          { name = "5", config = { param = { "v1", "v2" }}},
          { name = "6", config = { param = { "v1" }}},
          { name = "7", config = { param = {}}},
          { name = "8", config = { param = "value", array = { "v1", "v2", "v3", "v4", "v5", "v6" }}},
          { name = "9", config = { bool1 = true, bool2 = false, number = 1, double = 1.1, empty = {}, null = ngx.null,
                                   string = "test", hash = { k = "v" }, array = { "v1", "v2", "v3", "v4", "v5", "v6" }}},
        },
        consumers = {}
      }

      for i = 1, 1000 do
        value.consumers[i] = { username = "user-" .. tostring(i) }
      end

      local h = clustering.calculate_config_hash(clustering, value)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal("cb83c48d5b2932d1bc9d13672b433365", hash)
        assert.equal(h, hash)
      end
    end)

  end)
end)
