## 0.2.3

- iterrate over plugin instances in all workspaces

## 0.2.2

- chore(*) add copyright

## 0.2.1

- fix logging; ensure basic serializer generates `request.tls.client_verify`

## 0.2.0

- fix workspace fields (migration)

## 0.1.2

- skip verification when `IGNORE_CA_ERROR` is configured

## 0.1.1

- add `STRICT` mode

## 0.1.0

- add support for OCSP and CRL

## 0.0.9

- fix schema `consumer_id_by` => `consumer_id`

## 0.0.8

- exclude disabled `mtls-auth` plugins when looking for SNIs

## 0.0.7

- add route filtering and customer lookup overrides

## 0.0.5

- add support for ACL
- add error message when CA certificate is missing
- return proper status code for authentication failures

## 0.0.4

- correct plugin iterator usage

## 0.0.3

- fix iteration of missing attributes

## 0.0.2

- fix incorrect default cache key when looking up credentials

## 0.0.1

- Initial release
