local lapis      = require "lapis"
local singletons = require "kong.singletons"
local ee         = require "kong.enterprise_edition"
local pl_file    = require "pl.file"
local EtluaWidget = require("lapis.etlua").EtluaWidget


local app = lapis.Application()

app:enable("etlua")
app.layout = EtluaWidget:load(pl_file.read(singletons.configuration.prefix .. "/portal/views/index.etlua"))

app:match("/(*)", function(self)
  self.configs = ee.prepare_portal(singletons.configuration, true)
end)

return app
