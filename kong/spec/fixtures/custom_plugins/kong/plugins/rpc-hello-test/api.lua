return {
  ["/rpc-hello-test"] = {
    resource = "rpc-hello-test",

    GET = function()
      local headers = kong.request.get_headers()
      local greeting = headers["x-greeting"]
      local node_id = headers["x-node-id"]
      if not greeting or not node_id then
        kong.response.exit(400, "Greeting header is required")
      end
    
      local res, err = kong.rpc:call(node_id, "kong.test.hello", greeting)
      if not res then
        return kong.response.exit(500, err)
      end
    
      return kong.response.exit(200, res)
    end
  },
}