# Table of Contents

- [0.2.5](#025---20200604)
- [0.2.4](#024---20200526)
- [0.2.3](#023---20200518)
- [0.2.2](#022---20200211)
- [0.2.1](#021---20200123)
- [0.2.0](#020---20191218)
- [0.1.2](#012---20191216)
- [0.1.1](#011---20191212)
- [0.1.0](#010---20191212)

##  [0.2.5] - 2020/06/04

- Rename API endpoints to be RESTful.
- `api_uri` includes `/directory` part by default.

##  [0.2.4] - 2020/05/26

- Add endpoints to actively create and renew certificates.
- Cleanup renew config when the certificate is deleted in the storage.

##  [0.2.3] - 2020/05/18

- Bump lua-resty-acme to get better error handling.

##  [0.2.2] - 2020/02/11

- Change the plugin priority to ensure uniqueness among Kong bundled plugins

##  [0.2.1] - 2020/01/23

- Make tests more resilient

##  [0.2.0] - 2019/12/18

- *Breaking change*: this plugin now can only configured as global plugin.
- Add support for dbless mode.
- Add `tos_accepted` to plugin config if using Let's Encrypt.
- Add `domains` to plugin config to include domains that needs certificate.

##  [0.1.2] - 2019/12/16

- Fix some typos in tests.

##  [0.1.1] - 2019/12/12

- Remove BasePlugin dependency.

##  [0.1.0] - 2019/12/12

- Initial release of ACME plugin for Kong.

[0.2.5]: https://github.com/Kong/kong-plugin-acme/compare/0.2.4...0.2.5
[0.2.4]: https://github.com/Kong/kong-plugin-acme/compare/0.2.3...0.2.4
[0.2.3]: https://github.com/Kong/kong-plugin-acme/compare/0.2.2...0.2.3
[0.2.2]: https://github.com/Kong/kong-plugin-acme/compare/0.2.1...0.2.2
[0.2.1]: https://github.com/Kong/kong-plugin-acme/compare/0.2.0...0.2.1
[0.2.0]: https://github.com/Kong/kong-plugin-acme/compare/0.1.2...0.2.0
[0.1.2]: https://github.com/Kong/kong-plugin-acme/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/Kong/kong-plugin-acme/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/Kong/kong-plugin-acme/commit/8b250b72218a350b71723670005c3c355e5d73b4
