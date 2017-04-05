return {
  fields = {
    timeout = {type = "number", default = 60000, required = true },
    keepalive = {type = "number", default = 60000, required = true },
    aws_key = {type = "string", required = true},
    aws_secret = {type = "string", required = true},
    aws_region = {type = "string", required = true, enum = {
                  "us-east-1", "us-east-2", "ap-northeast-1", "ap-northeast-2", "us-west-2",
                  "ap-southeast-1", "ap-southeast-2", "eu-central-1", "eu-west-1",
                  "mock"}},
    function_name = {type="string", required = true},
    qualifier = {type = "string"},
    invocation_type = {type = "string", required = true, default = "RequestResponse", 
                       enum = {"RequestResponse", "Event", "DryRun"}},
    log_type = {type = "string", required = true, default = "Tail", 
                       enum = {"Tail", "None"}}
  }
}
