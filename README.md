# Kong Azure Functions Plugin

This plugin invokes
[Azure Functions](https://azure.microsoft.com/en-us/services/functions/).
It can be used in combination with other request plugins to secure, manage
or extend the function.

Please see the [plugin documentation](https://getkong.org/plugins/azure-functions/)
for details on installation and usage.

# History

0.4.0
- Fix #7 (run_on in schema should be in toplevel fields table)
- Remove BasePlugin inheritance (not needed anymore)

0.3.1
- Fix invalid references to functions invoked in the handler module
- Strip connections headers disallowed by HTTP/2

0.3.0
- Restrict the `config.run_on` field to `first`

0.2.0
- Use of new db & PDK functions
- kong version compatibility bumped to >= 0.15.0

0.1.1

- Fix delayed response
- Change "Server" header to "Via" header and only add it when configured

0.1.0 Initial release

