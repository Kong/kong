package = "kong-plugin-aws-lambda"
version = "3.5.1-1"

supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/kong/kong-plugin-aws-lambda",
  tag = "3.5.1",
}

description = {
  summary = "Kong plugin to invoke AWS Lambda functions",
  homepage = "http://konghq.com",
  license = "Apache 2.0"
}

dependencies = {
  "lua-resty-openssl",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.aws-lambda.aws-serializer"]       = "kong/plugins/aws-lambda/aws-serializer.lua",
    ["kong.plugins.aws-lambda.handler"]              = "kong/plugins/aws-lambda/handler.lua",
    ["kong.plugins.aws-lambda.iam-ec2-credentials"]  = "kong/plugins/aws-lambda/iam-ec2-credentials.lua",
    ["kong.plugins.aws-lambda.iam-ecs-credentials"]  = "kong/plugins/aws-lambda/iam-ecs-credentials.lua",
    ["kong.plugins.aws-lambda.schema"]               = "kong/plugins/aws-lambda/schema.lua",
    ["kong.plugins.aws-lambda.v4"]                   = "kong/plugins/aws-lambda/v4.lua",
    ["kong.plugins.aws-lambda.http.connect-better"]  = "kong/plugins/aws-lambda/http/connect-better.lua",
    ["kong.plugins.aws-lambda.request-util"]         = "kong/plugins/aws-lambda/request-util.lua",
  }
}
