local grpc_tools = require "kong.tools.grpc"

describe("grpc tools", function()
  it("visits service methods", function()
    local methods = {}
    grpc_tools.each_method("helloworld.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
    }, methods)
  end)

  it("visits imported methods", function()
    local methods = {}
    grpc_tools.each_method("direct_imports.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end, true)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
      "Own.Open",
    }, methods)
  end)

  it("imports recursively", function()
    local methods = {}
    grpc_tools.each_method("second_level_imports.proto",
      function(parsed, service, method)
        methods[#methods + 1] = string.format("%s.%s", service.name, method.name)
      end, true)
    assert.same({
      "HelloService.SayHello",
      "HelloService.UnknownMethod",
      "Own.Open",
      "Added.Final",
    }, methods)
  end)
end)
