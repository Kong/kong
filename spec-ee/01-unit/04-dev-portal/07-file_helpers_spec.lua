local file_helpers = require "kong.portal.file_helpers"

describe("file helpers", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("base64 encode/decode", function()
    it("decodes contents if valid base64", function()
      local decoded_file = file_helpers.decode_file({
        contents = "ZG9nZ29zIGFyZSBjb29sIQ=="
      })

      assert.equals("doggos are cool!", decoded_file.contents)
    end)

    it("does not decode contents if invalid base64", function()
      local decoded_file = file_helpers.decode_file({
        contents = "this isnt base64!"
      })

      assert.equals("this isnt base64!", decoded_file.contents)
    end)
  end)

  describe("file type checkers", function()
    it("can validate content files", function()
      local is_content
      local paths = {
        ["content/a/b/c.md"]   = true,
        ["content/a/b/c.txt"]  = true,
        ["content/a/b/c.html"] = true,
        ["content/a/b/c.json"] = true,
        ["content/a/b/c.yaml"] = true,
        ["content/a/b/c.yml"]  = true,
        ["content/a/b/c.fake"] = false,
        ["content/a/b/c.jpeg"] = false,
        ["content/a/b/c"]      = false,
        ["content"]            = false,
        ["a/b/c"]              = false,
        ["a/contents/b.txt"]   = false,
      }

      for k, v in pairs(paths) do
        is_content = file_helpers.is_content({ path = k })
        assert.equals(v, is_content)
      end
    end)

    it("can validate asset files", function()
      local is_asset
      local paths = {
        ["themes/a/assets/c.jpeg"]     = true,
        ["themes/ab/assets/c.jpeg"]    = true,
        ["themes/a/assets/c/d.jpeg"]   = true,
        ["themes/a/assets/c/d/e.jpeg"] = true,
        ["themes/a/b/assets/c.jpeg"]   = false,
        ["theme/a/assets/c.jpeg"]      = false,
        ["themes/assets/c.jpeg"]       = false,
        ["themes/a/asset/c.jpeg"]      = false,
        ["assets/c.jpeg"]              = false,
        ["c.jpeg"]                     = false,
      }

      for k, v in pairs(paths) do
        is_asset = file_helpers.is_asset({ path = k })
        assert.equals(v, is_asset)
      end
    end)

    it("can validate layout files", function()
      local is_layout
      local paths = {
        ["themes/a/layouts/c.html"]      = true,
        ["themes/ab/layouts/c.html"]     = true,
        ["themes/a/layouts/c/d.html"]   = true,
        ["themes/a/layouts/c/d/e.html"] = true,
        ["themes/a/layouts/c.txt"]       = false,
        ["themes/a/b/layouts/c.html"]   = false,
        ["theme/a/layouts/c.html"]      = false,
        ["themes/layouts/c.html"]       = false,
        ["themes/a/layout/c.html"]       = false,
        ["layouts/c.html"]               = false,
        ["c.html"]                       = false,
      }

      for k, v in pairs(paths) do
        is_layout = file_helpers.is_layout({ path = k })
        assert.equals(v, is_layout)
      end
    end)

    it("can validate partial files", function()
      local is_partial
      local paths = {
        ["themes/a/partials/c.html"]     = true,
        ["themes/ab/partials/c.html"]    = true,
        ["themes/a/partials/c/d.html"]   = true,
        ["themes/a/partials/c/d/e.html"] = true,
        ["themes/a/partials/c.txt"]      = false,
        ["themes/a/b/partials/c.html"]   = false,
        ["theme/a/partials/c.html"]      = false,
        ["themes/partials/c.html"]       = false,
        ["themes/a/partial/c.html"]      = false,
        ["partials/c.html"]              = false,
        ["c.html"]                       = false,
      }

      for k, v in pairs(paths) do
        is_partial = file_helpers.is_partial({ path = k })
        assert.equals(v, is_partial)
      end
    end)
  end)

  describe("get_ext", function()
    it("it returns the extension", function()
      local ext
      local paths = {
        ["a.html"]        = "html",
        ["a/json.txt"]    = "txt",
        ["html/b/c.md"]   = "md",
        ["derp/wow.json"] = "json",
        ["nope"]          = nil,

      }

      for k, v in pairs(paths) do
        ext = file_helpers.get_ext(k)
        assert.equals(v, ext)
      end
    end)
  end)

  describe("is_html_ext", function()
    it("checks if extension is .html", function()
      local ext
      local paths = {
        ["a.html"]             = true,
        ["a/b/c.html"]         = true,
        ["derp.json/wow.html"] = true,
        ["a/b.txt"]            = false,
        ["whut"]               = false,
      }

      for k, v in pairs(paths) do
        ext = file_helpers.is_html_ext(k)
        assert.equals(v, ext)
      end
    end)
  end)

  describe("is_valid_content_ext", function()
    it("checks if extension is valid for content type files", function()
      local ext
      local paths = {
        ["a.txt"]      = true,
        ["a.md"]       = true,
        ["a.html"]     = true,
        ["a.json"]     = true,
        ["a.yaml"]     = true,
        ["a.yml"]      = true,
        ["selfie.jpg"] = false,
        ["final.psd"]  = false,
        ["nope.js"]    = false,
      }

      for k, v in pairs(paths) do
        ext = file_helpers.is_valid_content_ext(k)
        assert.equals(v, ext)
      end
    end)
  end)

  describe("get_prefix", function()
    it("returns the prefix of a path", function()
      local prefix
      local paths = {
        ["neat/a.html"]      = "neat",
        ["rad/b.txt"]        = "rad",
        ["awesome/b/c.html"] = "awesome",
        ["whut.jpg"]         = nil,
      }

      for k, v in pairs(paths) do
        prefix = file_helpers.get_prefix(k)
        assert.equals(v, prefix)
      end
    end)
  end)

  describe("is_content_path", function()
    it("checks if path a content path", function()
      local is_content_path
      local paths = {
        ["content/a.html"]        = true,
        ["not/content/path.html"] = false,
        ["rad/content.txt"]       = false,
        ["awesome/b/c.html"]      = false,
      }

      for k, v in pairs(paths) do
        is_content_path = file_helpers.is_content_path(k)
        assert.equals(v, is_content_path)
      end
    end)
  end)

  describe("is_layout_path", function()
    it("checks if path a layout path", function()
      local is_layout_path
      local paths = {
        ["themes/mytheme/layouts/layout.html"]  = true,
        ["themes/my-theme/layouts/layout.html"] = true,
        ["not/layouts/path.html"]               = false,
        ["themes/mytheme/something.html"]       = false,
        ["themes/mytheme/something/else.html"]  = false,
        ["themes/mytheme/layouts.html"]         = false,
        ["nope/mytheme/layouts/layout.html"]    = false,
      }

      for k, v in pairs(paths) do
        is_layout_path = file_helpers.is_layout_path(k)
        assert.equals(v, is_layout_path)
      end
    end)
  end)

  describe("is_partial_path", function()
    it("checks if path a partial path", function()
      local is_partial_path
      local paths = {
        ["themes/mytheme/partials/partials.html"]   = true,
        ["themes/my-theme/partials/partials.html"]  = true,
        ["not/partials/path.html"]                  = false,
        ["themes/mytheme/something.html"]           = false,
        ["themes/mytheme/something/else.html"]      = false,
        ["themes/mytheme/partials.html"]            = false,
        ["nope/mytheme/partials/partial.html"]      = false,
      }

      for k, v in pairs(paths) do
        is_partial_path = file_helpers.is_partial_path(k)
        assert.equals(v, is_partial_path)
      end
    end)
  end)

  describe("is_asset_path", function()
    it("checks if path a asset path", function()
      local is_asset_path
      local paths = {
        ["themes/mytheme/assets/asset.png"]   = true,
        ["themes/my-theme/assets/asset.png"]  = true,
        ["not/assets/path.png"]               = false,
        ["themes/mytheme/something.png"]      = false,
        ["themes/mytheme/something/else.png"] = false,
        ["themes/mytheme/assets.pngs"]        = false,
        ["nope/mytheme/assets/assets.png"]    = false,
      }

      for k, v in pairs(paths) do
        is_asset_path = file_helpers.is_asset_path(k)
        assert.equals(v, is_asset_path)
      end
    end)
  end)

end)
