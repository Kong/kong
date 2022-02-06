# Config Service

Config service deals with proxy configuration data.
This service is responsible for:
- getting configuration data like routes, services, plugins from the CPs to DPs
- recording and reporting errors for configuration

Version compatibility is out of scope for this service and will be addressed as
a separate service or a future addition to this service.


## Configuration data

Configuration contains data that Kong needs to proxy traffic correctly.
This includes (exhaustive list):
- Services
- Routes
- Consumers
- Plugins
- Upstreams
- Targets
- Certificates
- SNIs
- CACertificates
- Plugin-specific data such as consumer credentials

## Versions

This service has the following versions:
- [v1](v1/)

