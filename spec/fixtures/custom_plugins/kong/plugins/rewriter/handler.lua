-- a plugin fixture to test running of the rewrite phase handler.

local Rewriter =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}

function Rewriter:rewrite(conf)
  ngx.req.set_header("rewriter", conf.value)
end

return Rewriter
