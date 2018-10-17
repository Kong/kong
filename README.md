# Kong Azure Functions Plugin

This plugin invokes
[Azure Functions](https://azure.microsoft.com/en-us/services/functions/).
It can be used in combination with other request plugins to secure, manage
or extend the function.

Please see the [plugin documentation](https://getkong.org/plugins/azure-functions/)
for details on installation and usage.

# History

0.2.0
- Use of new db & PDK functions
- kong version compatibility bumped to >= 0.15.0

0.1.1

- Fix delayed response
- Change "Server" header to "Via" header and only add it when configured

0.1.0 Initial release

