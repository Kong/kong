

# Kong Portal Lua API

Kong Developer Portal supports writing templates using lua, we have abstracted away some concepts and replaced them with more familiar concepts, here we define those concepts, and the objects exposed to help build custom functionality / pages.

## Globals

- [`l`](#lkey-fallback) - Locale helper, first version, gets values from the currently active page.
- [`each`](#eachlist_or_table) - Commonly used helper to iterate over lists / tables.
- [`print`](#printany) - Commonly used helper to print lists / tables.

## Objects

- [`portal`](#portal) - The portal object refers to the current workspace portal being accessed.
- [`page`](#page) - The page object refers to the currently active page, and it's contents.
- [`user`](#user) - The user object represents the currently logged in developer accessing the Kong Portal.
- [`theme`](#theme) - The theme object represents the currently active theme, and it's variables.
- [`helpers`](#helpers) - Helper functions simplify common tasks or provide easy shortcuts to Kong Portal methods.

## Terminology / Definitions

- `list` - Also referred to commonly as an array (`[1, 2, 3]`) in lua is a table-like object (`{1, 2, 3}`). Lua list index starts at `1` not `0`. Values can be accessed by array notation (`list[1]`).
- `table` - Also commonly-known-as an object or hashmap (`{1: 2}`) in lua looks like (`{1 = 2}`). Values can be accessed by array or dot notation (`table.one or table["one"]`).

# `l(key, fallback)`

#### Description

> Returns the current translation by key from the currently active page.

#### Return Type

```lua
string
```

#### Usage


##### `content/en/example.txt`

```yaml
layout: example.html

locale:
  title: Welcome to {{portal.name}}
  slogan: The best developer portal ever created.
```

##### `content/es/example.txt`

```yaml
layout: example.html

locale:
  title: Bienvenido a {{portal.name}}
  slogan: El mejor portal para desarrolladores jamás creado.
```

##### `layouts/example.html`

```hbs
<h1>{* l("title", "Welcome to" .. portal.name) *}</h1>
<p>{* l("slogan", "My amazing developer portal!") *}</p>
<p>{* l("powered_by", "Powered by Kong.") *}</p>
```

##### Output when on `en/example`

```html
<h1>Welcome to Kong Portal</h1>
<p>The best developer portal ever created.</p>
<p>Powered by Kong.</p>
```

##### Output when on `es/example`

```html
<h1>Bienvenido a Kong Portal</h1>
<p>El mejor portal para desarrolladores jamás creado.</p>
<p>Powered by Kong.</p>
```

#### Notes

- `l(...)` is a helper from the `page` object. It can be also accessed via `page.l`. However `page.l` does not support template interpolation (aka `{{portal.name}}` will not work.)

# `each(list_or_table)`

#### Description

> Returns the appropriate iterator depending on what type of argument is passed.

#### Return Type

```lua
Iterator
```

#### Usage

##### Template (List)

```hbs
{% for index, value in each(table) do %}
<ul>
  <li>Index: {{index}}</li>
  <li>Value: {{ print(value) }}</li>
</ul>
{% end %}
```

##### Template (Table)

```hbs
{% for key, value in each(table) do %}
<ul>
  <li>Key: {{key}}</li>
  <li>Value: {{ print(value) }}</li>
</ul>
{% end %}
```

# `print(any)`

#### Description

> Returns stringified output of input value

#### Return Type

```lua
string
```

#### Usage

##### Template (Table)

```hbs
<pre>{{print(page)}}</pre>
```

# `portal`

> `portal` gives access to data relating to the current portal, this includes things like portal configuration, content, specs, and layouts.

---

- [How To Access Config Values](#how-to-access-config-values)
- [Portal Members](#portal-members)
  - [`portal.workspace`](#portalworkspace)
  - [`portal.url`](#portalurl)
  - [`portal.api_url`](#portalapi_url)
  - [`portal.auth`](#portalauth)
  - [`portal.specs`](#portalspecs)
  - [`portal.developer_meta_fields`](#portaldeveloper_meta_fields)

---

## How To Access Config Values

You can access the current workspace's portal config directly on the `portal` object like so:

```lua
portal[config_key] or portal.config_key
```

For example `portal.auth` is a portal config value. You can find a list of config values by reading the portal section of `kong.conf`.

### From `kong.conf`

The portal only exposes config values that start with  `portal_`, and they can be access by removing the `portal_` prefix.

> Some configuration values are modified or customized, these customizations are documented under the [Portal Members](#portal-members) section.

## Portal Members

### `portal.workspace`

#### Description

> Returns the current portal's workspace.

#### Return Type

```lua
string
```

#### Usage

##### Template

```hbs
{{portal.workspace}}
```

##### Output

```html
default
```

### `portal.url`

#### Description

> Returns the current portal's url with workspace.

#### Return Type

```lua
string
```

#### Usage

##### Template

```hbs
{{portal.url}}
```

##### Output

```html
http://127.0.0.1:8003/default
```

## `portal.api_url`

#### Description

> Returns the configuration value for `portal_api_url` with
> the current workspace appended.

#### Return Type

```lua
string or nil
```

#### Usage

##### Template

```hbs
{{portal.api_url}}
```

##### Output when `portal_api_url = http://127.0.0.1:8004`

```html
http://127.0.0.1:8004/default
```

### `portal.auth`

#### Description

> Returns the current portal's authentication type.

#### Return Type

```lua
string
```

#### Usage

#### Printing Value

###### Input

```hbs
{{portal.auth}}
```

###### Output when `portal_auth = basic-auth`

```html
basic-auth
```

#### Checking Authentication Enabled

###### Input

```hbs
{% if portal.auth then %}
  Authentication is enabled!
{% end %}
```

###### Output when `portal_auth = basic-auth`

```html
Authentication is endabled!
```

### `portal.specs`

#### Description

Returns an array of specification files contained within the current portal

#### Return type

```lua
array
```

#### Usage

##### Viewing content value

###### Template

```hbs
<pre>{{ print(portal.specs) }}</pre>
```

###### Output

```lua
{
  {
    "path" = "content/example1_spec.json",
    "content" = "..."
  },
  {
    "path" = "content/documentation/example1_spec.json",
    "content" = "..."
  },
  ...
}
```

##### Looping through values

###### Template

```hbs
{% for _, spec in each(portal.specs) %}
  <li>{{spec.path}}</li>
{% end %}
```

###### Output

```hbs
  <li>content/example1_spec.json</li>
  <li>content/documentation/example1_spec.json</li>
```

##### Filter by path

###### Template

```hbs
{% for _, spec in each(helpers.filter_by_path(portal.specs, "content/documentation")) %}
  <li>{{spec.path}}</li>
{% end %}
```

###### Output

```hbs
  <li>content/documentation/example1_spec.json</li>
```

### `portal.developer_meta_fields`

#### Description

Returns an array of developer meta fields availabe/required by kong to register a developer

#### Return Type

```lua
array
```

#### Usage

##### Printing

###### Template

```hbs
{{ print(portal.developer_meta_fields) }}
```

###### Output

```lua
{
  {
    label    = "Full Name",
    name     = "full_name",
    type     = "text",
    required = true,
  },
  ...
}
```

#### Looping

###### Template

```hbs
{% for i, field in each(portal.developer_meta_fields) do %}
<ul>
  <li>Label: {{field.label}}</li>
  <li>Name: {{field.name}}</li>
  <li>Type: {{field.type}}</li>
  <li>Required: {{field.required}}</li>
</ul>
{% end %}
```

###### Output

```html
<ul>
  <li>Label: Full Name</li>
  <li>Name: full_name</li>
  <li>Type: text</li>
  <li>Required: true</li>
</ul>
...
```

# `page`

> `page` gives access to data relating to the current page, this includes things like page url, path, breadcrumbs...

---

- [How to access content values](#how-to-access-content-values)
- [Page Members](#page-members)
  - [`page.contents`](#pagecontents)
  - [`page.path`](#pagepath)
  - [`page.url`](#pageurl)
  - [`page.breadcrumbs`](#pagebreadcrumbs)
  - [`page.body`](#pagebody)

---

## How to access content values

When you create a new content page, you are able to define key-values. Here you are going to learn how to access those values and a few interesting things.

You can access the key-values you define directly on the `page` object like so:

```lua
page[key_name] or page.key_name
```

You can also access nested keys like so:

```lua
page.key_name.nested_key
```

> Be careful! Make sure that the `key_name` exists before accessing `nested_key` like so to avoid output errors:
> ```hbs
> {{page.key_name and page.key_name.nested_key}}
> ```

## Page Members

### `page.contents`

#### Description

> Returns the current page's variables clean of helpers. Allows the page contents to be JSON encoded. See below.

#### Return Type

```lua
string
```

#### Usage

##### Template

```hbs
<pre>{{ helpers.json_encode(page.contents) }}</pre>
```

### `page.path`

#### Description

> Returns the current page's route / path.

#### Return Type

```lua
string
```

#### Usage

##### Template

```hbs
{{page.path}}
```

##### Output given url is `http://127.0.0.1:8003/default/guides/getting-started`

```html
guides/getting-started
```

### `page.url`

#### Description

> Returns the current page's url

#### Return Type

```lua
string
```

#### Usage

##### Template

```hbs
{{page.url}}
```

##### Output given url is `http://127.0.0.1:8003/default/guides/getting-started`

```html
http://127.0.0.1:8003/default/guides/getting-started
```

### `page.breadcrumbs`

#### Description

> Returns the current page's breadcrumb collection

#### Return Type

```lua
table[]
```

#### Item Properties

- `item.path` - Full path to item, no forward-slash prefix.
- `item.display_name` - Formatted name
- `item.is_first` - Is this the first item in the list?
- `item.is_last` - Is this the last item in the list?

#### Usage

##### Template

```hbs
<div id="breadcrumbs">
  <a href="">Home</a>
  {% for i, crumb in each(page.breadcrumbs) do %}
    {% if crumb.is_last then %}
      / {{ crumb.display_name }}
    {% else %}
      / <a href="{{crumb.path}}">{{ crumb.display_name }}</a>
    {% end %}
  {% end %}
</div>
```

### `page.body`

#### Description

> Returns the body of the current page as a string. If the routes content file has a `.md` or `.markdown` extension, the body will be parsed from markdown to html.

#### Return Type

```lua
string
```

#### Usage for .txt, .json, .yaml, .yml templates

##### index.txt
```hbs
This is text content.
```

##### Template
```hbs
<h1>This is a title</h1>
<p>{{ page.body) }}</p>
```

##### Output
> # This is a title
> This is text content

#### Usage for .md, .markdown templates

##### Template (markdown)
You must use the raw delimiter syntax `{* *}` in order to render markdown within a template.

##### index.txt
```hbs
# This is a title
This is text content.
```

##### Template
```hbs
{* page.body *}
```

##### Output
> # This is a title
> This is text content

# `user`

> TODO: document

# `theme`

> TODO: document

# `helpers`

> TODO: document

- `
