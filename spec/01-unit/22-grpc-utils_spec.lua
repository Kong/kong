local grpc_tools = require "kong.tools.grpc"

describe("grpc tools", function()
  it("visits service methods", function()
    local methods = {}
    local grpc_tools_instance = grpc_tools.new()
    grpc_tools_instance:each_method("helloworld.proto",
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
    local grpc_tools_instance = grpc_tools.new()
    grpc_tools_instance:each_method("direct_imports.proto",
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
    local grpc_tools_instance = grpc_tools.new()
    grpc_tools_instance:each_method("second_level_imports.proto",
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

  it("includes kong/include in the load path", function()
    local grpc_tools_instance = grpc_tools.new()
    assert.matches("kong/include$", grpc_tools_instance.protoc_instance.paths[3])
  end)

  -- duplicates how we load .proto files so we have a finer grain test pointing out if that breaks
  it("loads .proto files with luarocks loader", function()
    local loader = require "luarocks.loader"
    local kong_init_file, _, _ = loader.which("kong")
    local kong_include_dir = kong_init_file:gsub("init%.lua$", "include")
    
    local protoc = require "protoc"
    local p = protoc.new()
    p.include_imports = true
    p:addpath(kong_include_dir)
    assert(p:loadfile("opentelemetry/proto/collector/trace/v1/trace_service.proto"))
  end)
end)
