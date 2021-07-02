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
        assert.equal("326afd95b21a24c277d9d05684cc3de6", hash)
      end

      local correct = ngx.md5("#10#")
      assert.equal("326afd95b21a24c277d9d05684cc3de6", correct)

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
        assert.equal("fccfc6bd485ed004537bbcac3c697048", hash)
      end

      local correct = ngx.md5("#0.9#")
      assert.equal("fccfc6bd485ed004537bbcac3c697048", correct)

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
        assert.equal("58859d93c30e635814dc980ed86e3f84", hash)
      end

      local correct = ngx.md5("$$")
      assert.equal("58859d93c30e635814dc980ed86e3f84", correct)

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
        assert.equal("34d2d743af7d615ff842c839ac762e14", hash)
      end

      local correct = ngx.md5("$hello$")
      assert.equal("34d2d743af7d615ff842c839ac762e14", correct)

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
        assert.equal("7317c9dbe950ab8ffe4a4cff2f596e8a", hash)
      end

      local correct = ngx.md5("?false?")
      assert.equal("7317c9dbe950ab8ffe4a4cff2f596e8a", correct)

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
        assert.equal("437765a4d8772918472d8a25102edf2e", hash)
      end

      local correct = ngx.md5("?true?")
      assert.equal("437765a4d8772918472d8a25102edf2e", correct)

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
        assert.equal("99914b932bd37a50b983c5e7c90ae93b", hash)
      end

      local correct = ngx.md5("{}")
      assert.equal("99914b932bd37a50b983c5e7c90ae93b", correct)

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

    it("calculates hash for complex table", function()
      local value = {
        "a",
        -3,
        3,
        "b",
        -2,
        2,
        "c",
        1,
        -1,
        0.9,
        {},
        { a = "b" },
        ngx.null,
        hello      = "a",
        [-1]       = "b",
        [0.9]      = "c",
        [true]     = "d",
        [false]    = "e",
        [ngx.null] = "f",
        [{}]       = "g",
        a = "hello",
        b = -1,
        c = 0.9,
        d = true,
        e = false,
        f = ngx.null,
        g = {},
      }

      local correct = ngx.md5(
        "{#-1#:$b$;#0.9#:$c$;#1#:$a$;#10#:#0.9#;#11#:{};#12#:{$a$:$b$};#13#:/null/;" ..
        "#2#:#-3#;#3#:#3#;#4#:$b$;#5#:#-2#;#6#:#2#;#7#:$c$;#8#:#1#;#9#:#-1#;$a$:$he" ..
        "llo$;$b$:#-1#;$c$:#0.9#;$d$:?true?;$e$:?false?;$f$:/null/;$g$:{};$hello$:$" ..
        "a$;/null/:$f$;?false?:$e$;?true?:$d$;{}:$g$}")

      for _ = 1, 10 do
        local hash = clustering.calculate_config_hash(clustering, value)
        assert.is_string(hash)
        assert.equal(correct, hash)
      end
    end)

  end)
end)
