-- Related to issue https://github.com/Mashape/kong/issues/1207 
-- unit test to check body remains unaltered
describe("response-transformer body-check", function()
  
  local old_ngx, handler
  
  setup(function()
    old_ngx = ngx
    _G.ngx = {       -- busted requires explicit _G to access the global environment
      log = function() end,
      header = {
          ["content-type"] = "application/json",
        },
      arg = {},
      ctx = {
          buffer = "",
        },
    }
    handler = require("kong.plugins.response-transformer.handler")
    handler:new()
  end)
  
  teardown(function()
    ngx = old_ngx
  end)

  it("check the body to remain unaltered if no transforms have been set", function()
    -- only a header transform, no body changes
    local conf = {
      remove = {
        headers = {"h1", "h2", "h3"},
        json = {}
      },
      add = {
        headers = {},
        json = {},
      },
      append = {
        headers = {},
        json = {},
      },
      replace = {
        headers = {},
        json = {},
      },
    }
    local body = [[

  {
    "id": 1,
    "name": "Some One",
    "username": "Bretchen",
    "email": "Not@here.com",
    "address": {
      "street": "Down Town street",
      "suite": "Apt. 23",
      "city": "Gwendoline"
    },
    "phone": "1-783-729-8531 x56442",
    "website": "hardwork.org",
    "company": {
      "name": "BestBuy",
      "catchPhrase": "just a bunch of words",
      "bs": "bullshit words"
    }
  }

]]
    
    ngx.arg[1] = body
    handler:body_filter(conf)
    local result = ngx.arg[1]
    ngx.arg[1] = ""
    ngx.arg[2] = true -- end of body marker
    handler:body_filter(conf)
    result = result .. ngx.arg[1]
    
    -- body filter should not execute, it would parse and reencode the json, removing
    -- the whitespace. So check equality to make sure whitespace is still there, and hence
    -- body was not touched.
    assert.are.same(body, result)

  end)

end)
