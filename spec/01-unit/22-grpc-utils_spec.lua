local grpc_tools = require "kong.tools.grpc"
local grpc = grpc_tools.new()

grpc:add_path( "spec/fixtures/grpc" )

describe("grpc tools", function()
  it("visits service methods", function()
    local methods = {}
    grpc:traverse_proto_file("helloworld.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end, nil)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
    }, methods)
  end)

  it("visits imported methods", function()
    local methods = {}
    grpc:traverse_proto_file("direct_imports.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end, nil)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
      "Own.Open",
    }, methods)
  end)

  it("imports recursively", function()
    local methods = {}
    grpc:traverse_proto_file("second_level_imports.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end, nil)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
      "Own.Open",
      "Added.Final",
    }, methods)
  end)

  it("visit every message field", function()
    local json_names = {}

    grpc:traverse_proto_file("second_level_imports.proto",
      nil,
      function(file, msg, field)
        if ( field.json_name ~= nil ) then
          json_names[#json_names + 1] = string.format("%s.%s = %s", msg.full_name, field.name, field.json_name)
        end
      end)
    assert.same({
      ".hello.HelloRequest.greeting = thisIsGreeting",
    }, json_names)
  end)
end)
