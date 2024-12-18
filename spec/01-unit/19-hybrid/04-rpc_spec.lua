-- by importing helpers, we initialize the kong PDK module
local helpers = require "spec.helpers"
local server = require("spec.helpers.rpc_mock.server")
local client = require("spec.helpers.rpc_mock.client")

describe("rpc v2", function()
  describe("full sync pagination", function()
    describe("server side", function()
      local server_mock
      local port
      lazy_setup(function()
        server_mock = server.new()
        server_mock:start()
        port = server_mock.listen
      end)
      lazy_teardown(function()
        server_mock:stop()
      end)
    end)
    
    describe("client side", function()
      local client_mock
      lazy_setup(function()
        client_mock = server.new()
      end)
      lazy_teardown(function()
        client_mock:stop()
      end)
    end)
  end)
end)
