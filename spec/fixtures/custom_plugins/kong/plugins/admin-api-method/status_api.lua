return {
 ["/hello"] = {
    GET = function()
      kong.response.exit(200, { hello = "from status api" })
    end,
  },
}
