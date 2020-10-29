

return {
  _stream = {
    ["/echo"] = function(req)
      local body = req:get_body()

      return req:response(200, nil, body)
    end,
  }
}
