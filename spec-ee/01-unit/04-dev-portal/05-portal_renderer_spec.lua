local renderer   = require "kong.portal.renderer"

describe("portal_renderer", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  describe("find_next_partial", function()

    it("should return `nil` if no partial in page", function()
      local page = [[
        <div>
          <h1>No Partials Here!</h1>
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal(nil, res)
    end)

    it("should return partial with correctly formatted `{{> }}` delimeters", function()
      local page = [[
        <div>
          <h1>Title</h1>
          {{> dog }}
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal('{{> dog }}', res)
    end)

    it("should return partial with correctly formatted `{{#> }}` delimeters", function()
      local page = [[
        <div>
          <h1>Title</h1>
          {{#> dog }}
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal('{{#> dog }}', res)
    end)

    it("should only return first valid partial", function()
      local page = [[
        <div>
          <h1>Title</h1>
          {> cat }}
          {{> bat }}
          {{#> dog }}
          {{> hog
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal('{{> bat }}', res)
    end)

    it("should return valid partial including passed in params", function()
      local page = [[
        <div>
          <h1>Title</h1>
          {{#> bat pageTitle='dog' }}
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal("{{#> bat pageTitle='dog' }}", res)

      page = [[
        <div>
          <h1>Title</h1>
          {{> bat pageTitle='dog' }}
        </div>
      ]]

      res = renderer.find_next_partial(page)
      assert.equal("{{> bat pageTitle='dog' }}", res)
    end)

    it("should return partials with different valid spacings", function()
      local page = [[
        <div>
          <h1>Title</h1>
          {{#>      bat }}
        </div>
      ]]
      local res = renderer.find_next_partial(page)
      assert.equal("{{#>      bat }}", res)

      page = [[
        <div>
          <h1>Title</h1>
          {{#>bat }}
        </div>
      ]]
      res = renderer.find_next_partial(page)
      assert.equal("{{#>bat }}", res)

      page = [[
        <div>
          <h1>Title</h1>
          {{#>    bat}}
        </div>
      ]]
      res = renderer.find_next_partial(page)
      assert.equal("{{#>    bat}}", res)

      page = [[
        <div>
          <h1>Title</h1>
          {{#>bat}}
        </div>
      ]]
      res = renderer.find_next_partial(page)
      assert.equal("{{#>bat}}", res)
    end)

  end)

  describe("parse_partial_name", function()
    local partial, res

    it("should return name only with simple partial", function()
      partial = '{{> partial }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)

      partial = '{{#> partial }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)
    end)

    it("should return name only from partial with argument", function()
      partial = '{{> partial dog=cat }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)

      partial = '{{#> partial cat=dog }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)
    end)

    it("should return name only from partial with different spacings", function()
      partial = '{{>partial dog=cat}}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)

      partial = '{{>partial     dog=cat}}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)

      partial = '{{>          partial     dog=cat}}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)

      partial = '{{>partial dog=cat  }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('partial', res)
    end)

    it("should not return proper name if arguments come first", function()
      partial = '{{>dog=cat partial }}'
      res = renderer.parse_partial_name(partial)
      assert.equal('dog=cat', res)
    end)
  end)

  describe("replace_partial_in_page", function()
    local page, partial, match, res, result

    it("should replace partial delimeter with partial content", function()
      match = '{{> partial }}'
      partial = '<h2>content</h2>'
      page = [[
        <div class="header">
          <h1>header</h1>
        </div>
        <div class="content">
          {{> partial }}
        </div>
        <div class="footer">
          <h2>footer</h2>
        </div>
      ]]
      result = [[
        <div class="header">
          <h1>header</h1>
        </div>
        <div class="content">
          <h2>content</h2>
        </div>
        <div class="footer">
          <h2>footer</h2>
        </div>
      ]]
      res = renderer.replace_partial_in_page(page, partial, match)
      assert.equal(result, res)
    end)

    it("should not replace partial delimeter with malformed match arg", function()
      match = '{{> partial }}'
      partial = '<h2>content</h2>'
      page = [[
        <div class="header">
          <h1>header</h1>
        </div>
        <div class="content">
          {{>partial }}
        </div>
        <div class="footer">
          <h2>footer</h2>
        </div>
      ]]
      result = [[
        <div class="header">
          <h1>header</h1>
        </div>
        <div class="content">
          {{>partial }}
        </div>
        <div class="footer">
          <h2>footer</h2>
        </div>
      ]]
      res = renderer.replace_partial_in_page(page, partial, match)
      assert.equal(result, res)
    end)
  end)

  describe("get_next_route", function()
    local og_path, path, extension

    it("should properly climb down path", function()
      og_path = 'cat/dog/bat/hog'
      extension = ''

      path, extension = renderer.get_next_route(og_path, extension)
      assert.equal('cat/dog/bat', path)
      assert.equal('hog', extension)
      assert.equal(og_path, path .. '/' .. extension)

      path, extension = renderer.get_next_route(path, extension)
      assert.equal('cat/dog', path)
      assert.equal('bat/hog', extension)
      assert.equal(og_path, path .. '/' .. extension)

      path, extension = renderer.get_next_route(path, extension)
      assert.equal('cat', path)
      assert.equal('dog/bat/hog', extension)
      assert.equal(og_path, path .. '/' .. extension)
    end)

    it("should handle single namespaced path", function()
      og_path = 'cat'
      extension = ''
  
      path, extension = renderer.get_next_route(og_path, extension)
      assert.equal('', path)
      assert.equal('cat', extension)
    end)
  end)
end)
