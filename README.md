## Apenode

lua-resty-apenode - Lua Apenode

[![The beginning of a new era](http://img.youtube.com/vi/U2iiPpcwfCA/0.jpg)](http://www.youtube.com/watch?v=U2iiPpcwfCA)

### Requirements
- Lua `5.1`
- Luarocks for Lua `5.1`
- Openrestify ([Download](http://openresty.com/#Download) the latest version of OpenResty and install it.)

### Contribute
- `make global` installation (requires `sudo`)
- `make test` Run unit tests
- `make test-web` Run API instegration tests
- `make test-all` Run all tests:
- `make run`
  - Proxy: http://localhost:8000/
  - API: http://localhost:8001/

### APIs

The Apenode provides APIs to interact with the underlyind data model and create APIs, Accounts and Applications

#### Create APIs

`POST /apis/`

* **required** `public_dns`: The public DNS of the API
* **required** `target_url`: The target URL
* **required** `authentication_type`: The authentication to enable on the API, can be `query`, `header`, `basic`.
* **required** `authentication_key_names`: A *comma-separated* list of authentication parameter names, like `apikey` or `x-mashape-key`.


#### Create Accounts

`POST /accounts/`

* `provider_id`: A custom id to be set in the account entity

#### Create Applications

`POST /applications/`

* **required** `account_id`: The `account_id` that the application belongs to.
* `public_key`: The public key, or username if Basic Authentication is enabled.
* **required** `secret_key`: The secret key, or api key, or password if Basic authentication is enabled. Use only this fields for simple api keys.

