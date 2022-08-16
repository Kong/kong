-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local wrpc_proto = require "kong.tools.wrpc.proto"
local pl_dir = require "pl.dir"
local pl_path = require "pl.path"

local parse_annotations = wrpc_proto.__parse_annotations

local function mock_file(str)
  return {
    str = str,
    lines = function(self)
      self.iter = self.str:gmatch("[^\r\n]+")
      return self.iter
    end,
    -- only used to read a line
    read = function(self, _)
      return self.iter()
    end
  }
end


local test_path = "/tmp/lua_test_proto"
describe("kong.tools.wrpc.proto", function()
  local wrpc_service

  before_each(function()
    wrpc_service = wrpc_proto.new()
    wrpc_service:addpath(test_path)
  end)

  describe("parse annotation", function()
    it("works", function()
      local module
      module = mock_file [[
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:rpc-id=4; comment=test
          rpc A(EmptyMsg) returns (EmptyMsg);
        }
      ]]
      parse_annotations(wrpc_service, module)
      assert.same({
        TestService = {
          ["service-id"] = '1'
        },
        ["TestService.A"] = {
          comment = 'test',
          ["rpc-id"] = '4'
        },
      }, wrpc_service.annotations)
    end)

    it("errors", function()
      local module
      module = mock_file [[
        // +wrpc:rpc-id=1
        service TestService {
          
        }
      ]]
      assert.error(function()
        parse_annotations(wrpc_service, module)
      end, "service with no id assigned")

      module = mock_file [[
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:service-id=4
          rpc A(EmptyMsg) returns (EmptyMsg);
        }
      ]]
      assert.error(function()
        parse_annotations(wrpc_service, module)
      end, "rpc with no id assigned")

      module = mock_file [[
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:rpc-id=4
        }
      ]]
      -- ignoring, as plain comment
      assert.has.no.error(function()
        parse_annotations(wrpc_service, module)
      end)

    end)
  end)

  describe("import test", function ()

    local function tmp_file(str, module_name)
      module_name = module_name or "default"
      local filename = test_path .. "/" .. module_name .. ".proto"
      local file = assert(io.open(filename, "w"))
      assert(file:write(str))
      file:close()
      return module_name, file, filename
    end

    lazy_setup(function ()
      pl_path.mkdir(test_path)
    end)
    lazy_teardown(function ()
      pl_dir.rmtree(test_path)
    end)

    it("works", function()
      local module
      module = tmp_file [[
        message EmptyMsg {}
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:rpc-id=4; comment=test
          rpc A(EmptyMsg) returns (EmptyMsg);
        }
      ]]
      wrpc_service:import(module)
      assert.same({
        TestService = {
          ["service-id"] = '1'
        },
        ["TestService.A"] = {
          comment = 'test',
          ["rpc-id"] = '4'
        },
      }, wrpc_service.annotations)
    end)

    it("errors", function()
      local module
      module = tmp_file [[
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:rpc-id=4; comment=test
          rpc A(EmptyMsg) returns (EmptyMsg);
        }
      ]]
      assert.error_matches(function()
        wrpc_service:import(module)
      end, "unknown type 'EmptyMsg'")
      
      module = tmp_file ([[
        // +wrpc:service-id=1
        service TestService {
          //+wrpc:rpc-id=4; comment=test
          rpc A() returns ();
        }
      ]], "test2")
      assert.error_matches(function()
        wrpc_service:import(module)
      end, "type name expected")
    end)
  end)

end)
