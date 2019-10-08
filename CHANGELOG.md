## aws-lambda 3.0.0

- Renamed from `liamp` to `aws-lambda` to supersede the `aws-lambda` plugin
  from Kong core.
- Note that this version number is just to indicate it supersedes the
  previously build in one. The effective change from version 2.0 (build in)
  of the aws-lambda plugin to 3.0 (this) is the combined set of changes
  mentioned below for Liamp versions `0.1.0` and `0.2.0`.

## Liamp 0.2.0

- chore: convert the plugin to the PDK and new DB (developed against Kong 1.x)

## Liamp 0.1.0

- feat: if no credentiuals are provided, the plugin will automatically fetch
  EC2 or ECS credentials and use the AWS IAM roles retrieved for accessing the
  Lambda.
- feat: new option `awsgateway_compatible` to make the serialized request
  compatible with the AWS gateway format, making the plugin a drop-in
  replacement
- feat: new option `skip_large_bodies` to enable really large bodies (that
  have been cached to disk) to also be sent to the Lambda. Use with care!
- feat: added the ability to connect to the Lambda through a proxy
