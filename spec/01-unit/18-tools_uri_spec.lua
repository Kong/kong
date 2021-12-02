local uri = require "kong.tools.uri"

describe("kong.tools.uri", function()

  describe("normalize()", function()
    it("no normalization necessary", function()
      assert.equal("", uri.normalize(""))
      assert.equal("/", uri.normalize("/"))
      assert.equal("/a", uri.normalize("/a"))
      assert.equal("/a/", uri.normalize("/a/"))
      assert.equal("/a/b/c", uri.normalize("/a/b/c"))
      assert.equal("/a/b/c/", uri.normalize("/a/b/c/"))
    end)

    it("no normalization necessary (reserved characters)", function()
      assert.equal("/a%2Fb%2Fc/", uri.normalize("/a%2Fb%2Fc/"))
      assert.equal("/%21%23%24%25%26%27%28%29%2A%2B%2C%2F%3A%3B%3D%3F%40%5B%5D", uri.normalize("/%21%23%24%25%26%27%28%29%2A%2B%2C%2F%3A%3B%3D%3F%40%5B%5D"))
    end)

    it("converting percent-encoded triplets to uppercase", function()
      assert.equal("/a%2Fb%2Fc/", uri.normalize("/a%2fb%2fc/")) -- input is lower case (reserved characters)
      assert.equal("/foo", uri.normalize("/f%6f%6f")) -- input is lower case (unreserved characters)
    end)

    it("decoding percent-encoded triplets of unreserved characters", function()
      assert.equal("/kong", uri.normalize("/%6B%6f%6e%67"))
      assert.equal("/", uri.normalize("/%2E"))
    end)

    it("remove dot segments", function()
      assert.equal("//", uri.normalize("//"))
      assert.equal("/", uri.normalize("/./"))
      assert.equal("/", uri.normalize("/."))
      assert.equal("/", uri.normalize("/.."))
      assert.equal("/", uri.normalize("/../"))
      assert.equal("/////", uri.normalize("/////"))
      assert.equal("/", uri.normalize("/./.././../"))

      -- RFC3986 examples, p. 33
      assert.equal("/a/g", uri.normalize("/a/b/c/./../../g"))
      assert.equal("mid/6", uri.normalize("mid/content=5/../6"))
    end)

    it("merge_slashes", function()
      assert.equal("/", uri.normalize("//", true))
      assert.equal("/", uri.normalize("/////", true))
      assert.equal("/a/b/", uri.normalize("/a//b//", true))
    end)

    it("does not decode non-ASCII characters that are unreserved, issue #2366", function()
      assert.equal("/endel%C3%B8st", uri.normalize("/endel%C3%B8st"))
    end)

    it("does normalize complex uri that has characters outside of normal uri charset", function()
      assert.equal("/%C3%A4/a./a/_%99%AF%2F%2F" , uri.normalize("/ä/a/%2e./a%2E//a/%2e/./a/../a/%2e%2E/%5f%99%af%2f%2F", true))
    end)
  end)

  describe("escape()", function()
    it("do not escape reserved or unreserved characters, plus %", function()
      assert.equal("/!#$%&'()*+,/:;=?@[]ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~", uri.escape("/!#$%&'()*+,/:;=?@[]ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"))
    end)

    it("escape spaces", function()
      assert.equal("/a%20b/c%20d", uri.escape("/a b/c d"))
    end)

    it("escape utf-8 characters", function()
      assert.equal("/a%F0%9F%98%80", uri.escape("/a😀"))
      assert.equal("/endel%C3%B8st", uri.escape("/endeløst"))
    end)
  end)

  describe("unescape()", function()
    it("decodes non-ASCII characters that are unreserved, issue #2366", function()
      assert.equal("/endeløst", uri.unescape("/endel%C3%B8st"))
    end)
  end)
end)
