package = "kong-plugin-kafka-upstream"
version = "dev-0"
source = {
   url = "git://github.com/kong/kong-plugin-kafka-upstream",
   tag = "dev"
}
description = {
   summary = "This plugin encodes requests as Kafka messages and sends them to the configured Kafka topic.",
   homepage = "https://github.com/kong/kong-plugin-kafka-upstream",
}
dependencies = {
   "lua >= 5.1",
   "kong-lua-resty-kafka == 0.17",
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.kafka-upstream.handler"] = "kong/plugins/kafka-upstream/handler.lua",
      ["kong.plugins.kafka-upstream.schema"] = "kong/plugins/kafka-upstream/schema.lua",
   }
}
