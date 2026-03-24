# ActionSpec [WIP]

Concise and Powerful API Documentation Solution for Rails.

<img src=".github/assets/action_spec.jpg" />

- OpenAPI version: `v3.2.0`
- Requires: Ruby 3.1+ and Rails 7.0+
- Note: this project was implemented with Codex in about 3 hours, has not yet been manually reviewed, and has not been validated in production. It does, however, come with fairly detailed RSpec tests generated with Codex.

## Table Of Contents

- [OpenAPI Generation](#openapi-generation)
- [Doc DSL](#doc-dsl)
  - [`doc`](#doc)
  - [`doc_dry`](#doc_dry)
  - [`openapi false`](#openapi-false)
  - [`tag`](#tag)
  - [DSL Reference](#dsl-reference)
- [Schemas](#schemas)
  - [Declare A Required Field](#declare-a-required-field)
  - [Field Types](#field-types)
  - [Field Options](#field-options)
  - [Schemas From ActiveRecord](#schemas-from-activerecord)
  - [Type And Boundary Matrix](#type-and-boundary-matrix)
- [Parameter Validation And Type Coercion](#parameter-validation-and-type-coercion)
  - [Validation Flow](#validation-flow)
  - [Reading Processed Values With `px`](#reading-processed-values-with-px)
  - [Errors](#errors)
- [Configuration And I18n](#configuration-and-i18n)
  - [Configuration](#configuration)
  - [I18n](#i18n)
- [AI Generation Style Guide](#ai-generation-style-guide)

## Example

```ruby
class UsersController < ApplicationController
  before_action :validate_and_coerce_params!, only: :create

  doc {
    header :Authorization, String
    path :account_id, Integer
    query :locale, String, default: "zh-CN"
    query :page, Integer, default: -> { 1 }

    form data: {
      name!: String,
      age: Integer,
      birthday: Date,
      admin: { type: :boolean, default: false },
      tags: [String],
      profile: {
        nickname!: String
      }
    }

    response 200, desc: "success"
  }
  def create
    User.create!(
      account_id: px[:account_id],
      name: px[:name],
      birthday: px[:birthday],
      admin: px[:admin]
    )
  end
end
```

## Installation

```ruby
# Gemfile
gem "action_spec"
```

Then run:

```bash
$ bundle
```

## OpenAPI Generation

Generate an OpenAPI document from the current Rails routes and ActionSpec controller docs:

```bash
bin/rails action_spec:gen
```

By default, this writes to:

```text
docs/openapi.yml
```

For one-off runs, environment variables can override the default output path and document metadata:

```bash
bin/rails action_spec:gen \
  OUTPUT=docs/openapi.yml \
  TITLE="My API" \
  VERSION="2026.03" \
  SERVER_URL="https://api.example.com"
```

Notes:

- only routed controller actions with a matching `doc` declaration are included
- endpoints with `openapi false` are skipped even when routed
- Rails paths such as `/users/:id(.:format)` are rendered as `/users/{id}`
- parameters, request bodies, and response descriptions are generated from the current DSL support
- if config and environment variables do not provide `TITLE` or `VERSION`, ActionSpec falls back to application-derived defaults

## Doc DSL

### `doc`

With action inferred from the next instance method:

```ruby
doc {
  form data: {    # <= request body DSL
    name!: String # <= schema DSL
  }
}
def create
end
```

Provide a summary:

```ruby
doc("Create user") {
  form data: { name!: String }
}
def create
end
```

You can also bind it explicitly when you want the action name declared in place:

```ruby
doc(:create, "Create user") {
  form data: { name!: String }
}
def create
end
```

### `doc_dry`

```ruby
class ApplicationController < ActionController::API
  doc_dry(%i[show update destroy]) {
    path! :id, Integer
  }

  doc_dry(:index) {
    query :page, Integer, default: 1
    query :per, Integer, default: 20
  }
end
```

All matching dry blocks are applied before the action-specific `doc`.

### `openapi false`

You can also opt an action out of OpenAPI generation from either `doc` or `doc_dry`:

```ruby
doc {
  openapi false
}
```

### `tag`

OpenAPI tags can also be set at either level:

```ruby
doc_dry(:index, tag: "backoffice")

doc("List users", tag: "members") {
  query :status, String
}
```

Generated OpenAPI operations also include an `operationId`, built from the final tag plus the action name, for example `members_index` or `users_create`.

### DSL Reference

#### Parameter

```ruby
header  :Authorization, String
header! :Authorization, String

path  :id, Integer
path! :id, Integer

query  :page, Integer
query! :page, Integer

cookie  :remember_token, String
cookie! :remember_token, String
```

Bang methods mark the field as required. For example, `query! :page, Integer` means the request must include `page`.

Batch declaration forms:

```ruby
in_header(
  Authorization: String
)

in_path!(
  id: Integer
)

in_query(
  page: Integer,
  per: { type: Integer, default: 20 },
  locale: String
)

in_cookie(
  remember_token: String
)

in_query!(
  user_id: Integer,
  token: String
)
```

#### request body 

General form:

```ruby
body :json, data: { name!: String, age: Integer }
```

Convenience helpers:

```ruby
json data: { name!: String }

json! data: { name!: String }

form data: { file!: File, position: String }

form! data: { file!: File }
```

Single multipart field helper:

```ruby
data :file, File
```

For `body/body!`, `json/json!`, and `form/form!`, the bang form is currently kept for DSL compatibility. At runtime they all contribute to the same body contract, and root-body requiredness is not yet enforced as a separate rule.

#### OpenAPI

```ruby
openapi false
```

Use this when an action should stay out of the generated OpenAPI document. It also works inside `doc_dry`.

#### Scope

Use `scope` when you want a grouped view that spans multiple request locations:

```ruby
doc {
  scope(:user) {
    query :user_id, Integer
    form data: { name: String }
  }
}
```

Then read it from `px.scope`:

```ruby
px.scope[:user] # => { user_id: 1, name: "Tom" }
```

#### Response 

```ruby
response 200, desc: "success"
response 422, "validation failed"
resp 400, "bad request"
error 401, "unauthorized"
```

Response declarations are stored as metadata now. They are not yet used to render responses automatically.

## Schemas

#### Declare A Required Field

Use `!` in either place:

```ruby
query! :page, Integer

json data: {
  name!: String,
  profile: {
    nickname!: String
  }
}
```

Meaning of `!`:

- `query!`, `path!`, `header!`, `cookie!` mark the parameter itself as required
- keys such as `name!:` or `nickname!:` mark nested object fields as required
- `body!`, `json!`, and `form!` are currently accepted for DSL consistency, but today they behave the same as the non-bang form at runtime

#### Field Types

Scalar types currently supported by validation/coercion:

- `String`
- `Integer`
- `Float`
- `BigDecimal`
- `:boolean` / `Boolean`
- `Date`
- `DateTime`
- `Time`
- `File`
- `Object`

Nested forms:

```ruby
json data: {
  tags: [String],
  profile: {
    nickname!: String
  },
  settings: { type: Object },
  users: [{ id: Integer }]
}
```

#### Field Options

These options are currently used by the validator:

```ruby
query :page, Integer, default: 1
query :today, Date, default: -> { Time.current.to_date }
query :status, String, enum: %w[draft published]
query :score, Integer, range: { ge: 1, le: 5 }
query :slug, String, pattern: /\A[a-z\-]+\z/
```

These options are currently used by OpenAPI generation, but are not yet used by the runtime validator:

- `desc`
- `example`
- `examples`

These options are not yet used by either the runtime validator or OpenAPI generation:

- `allow_nil`
- `allow_blank`

#### Schemas From ActiveRecord

If your model is an `ActiveRecord::Base`, you can derive an ActionSpec-friendly schema hash directly from the model:

```ruby
class UsersController < ApplicationController
  doc {
    form data: User.schemas
  }
  def create
  end
end
```

`User.schemas` returns a hash that can be passed directly into `form data:`, `json data:`, or `body`.

By default, it includes all model fields:

```ruby
User.schemas
```

You can also limit the exported fields:

```ruby
User.schemas(only: %i[name phone role])
```

ActionSpec extracts schema-relevant information from ActiveRecord / ActiveModel when available, including:

- field type
- requiredness, rendered as bang keys such as `"name!"`
- enum values from `enum`
- `default`
- `desc` from column comments
- `pattern` from format validators
- `range` from numericality validators
- `length` from length validators and string column limits

Example output:

```ruby
User.schemas
# {
#   "name!" => { type: String, desc: "user name", length: { maximum: 20 } },
#   "phone!" => { type: String, length: { maximum: 13 }, pattern: /\A1\d{10}\z/ },
#   "role" => { type: String, enum: %w[admin member visitor] }
# }
```

#### Type And Boundary Matrix

| Type | Accepted examples | Rejected examples / notes |
| --- | --- | --- |
| `String` | `12`, `true`, `""` | Follows `ActiveModel::Type::String`, so `true` becomes `"t"` |
| `Integer` | `"0"`, `"-12"`, `"+7"`, `12` | Rejects `"12.3"`, `"abc"`, `""` |
| `Float` | `"0"`, `"-12.5"`, `12`, `12.5` | Rejects `"12.3.4"`, `"abc"` |
| `BigDecimal` | `"0"`, `"-12.50"`, `12`, `12.5` | Rejects `"abc"` |
| `:boolean` / `Boolean` | `true`, `false`, `"1"`, `"0"`, `"true"`, `"false"`, `"yes"`, `"no"`, `"on"`, `"off"` | Rejects ambiguous values such as `""`, `"2"`, `"TRUE "`, `"maybe"` |
| `Date` | `"2025-10-17"` | Rejects invalid dates such as `"2025-02-30"` |
| `DateTime` | `"2025-10-17T12:30:00Z"` | Rejects invalid datetimes such as `"2025-10-17 25:00:00"` |
| `Time` | `"2025-10-17T12:30:00Z"` | Follows `ActiveModel::Type::Time`, so the date part becomes `2000-01-01` |
| `File` | `ActionDispatch::Http::UploadedFile`, `Tempfile`, file-like IO objects | Keeps the object as-is and does not read file contents into memory |
| `Object` | `Hash`, `ActionController::Parameters`, arbitrary Ruby objects | Passed through for scalar `Object`; nested hashes use object schema resolution |
| `[Type]` | arrays such as `%w[1 2 3]` for `[Integer]` | Rejects non-array values, and reports item errors like `tags.1` |
| nested object | `{ profile: { nickname: "neo" } }` | Rejects non-hash values, and reports nested paths like `profile.nickname` |


## Parameter Validation And Type Coercion

### Validation Flow

#### `validate_params!`

Validates using the DSL, but keeps raw values in `px`.

```ruby
before_action :validate_params!
```

Example:

- request query param `"page" => "2"`
- DSL says `query :page, Integer`
- result: `px[:page] == "2"`

You can safely put this hook on a base controller. If the current action has no matching `doc`, ActionSpec skips validation and returns an empty `px`.

#### `validate_and_coerce_params!`

Validates and coerces values before exposing them on `px`.

```ruby
before_action :validate_and_coerce_params!
```

Example:

- request query param `"page" => "2"`
- DSL says `query :page, Integer`
- result: `px[:page] == 2`

This hook also skips actions without a matching `doc`, so it is safe to declare on a shared base controller.

### Reading Processed Values With `px`

`px` stores the processed values produced by ActionSpec. With `validate_params!` they stay raw; with `validate_and_coerce_params!` they are coerced values.
Because `px` is still a hash, you can also use helpers such as `px.slice(...)` to simplify parameter access code.

```ruby
px[:id]
px[:page]
px[:profile][:nickname]
px.to_h
px.scope[:user]
```

Grouped views live under `px.scope`:

```ruby
px.scope[:path]
px.scope[:query]
px.scope[:body]
px.scope[:headers]
px.scope[:cookies]
```

Notes:

- every declared field from path/query/body is also flattened into the top-level `px[:field]`
- custom `scope(:name)` buckets are also exposed through `px.scope[:name]`
- headers and cookies stay inside their own grouped buckets; for example, `px[:Authorization]` is not a top-level shortcut
- header keys are stored in lowercase dashed form, but reading remains compatible with original forms such as `Authorization` and `HTTP_AUTHORIZATION`, for example:

```ruby
px.scope[:headers][:authorization]
px.scope[:headers]["Authorization"]
px.scope[:headers]["HTTP_AUTHORIZATION"]
```

- original `params` are not mutated

### Errors

Validation errors are stored in `ActiveModel::Errors`.

When validation fails, ActionSpec raises `ActionSpec::InvalidParameters`:

```ruby
begin
  validate_and_coerce_params!
rescue ActionSpec::InvalidParameters => error
  error.message
  error.errors.full_messages
end
```

The exception also keeps the full validation result on `error.result` and `error.parameters`.
ActionSpec does not render a default error response for you, so each application can decide its own rescue and JSON format.

`error.message` is built from `error.errors.full_messages.to_sentence`, so it follows normal `ActiveModel::Errors` wording:

- single error: `"Page is required"`
- multiple errors: `"Page is required and Birthday must be a valid date"`
- fallback when no detailed errors are present: `"Invalid parameters"`

Use `error.errors` when you need structured details, and `error.message` when you only need a single summary string.

## Configuration And I18n

### Configuration

```ruby
ActionSpec.configure { |config|
  config.open_api_output = "docs/openapi.yml"
  config.open_api_title = "My API"
  config.open_api_version = "2026.03"
  config.open_api_server_url = "https://api.example.com"

  config.error_messages[:invalid_type] = ->(_attribute, options) {
    "should be coercible to #{options.fetch(:expected)}"
  }
}
```

Available config keys:

- `invalid_parameters_exception_class`
  Default: `ActionSpec::InvalidParameters`.
  Controls which exception class is raised when validation fails.

- `error_messages`
  Default: `{}`.
  Lets you override error messages by error type, or by attribute plus error type.

- `open_api_output`
  Default: `"docs/openapi.yml"`.
  Controls where `bin/rails action_spec:gen` writes the generated OpenAPI document.

- `open_api_title`
  Default: `nil`.
  Sets the default OpenAPI `info.title` used by `bin/rails action_spec:gen`.

- `open_api_version`
  Default: `nil`.
  Sets the default OpenAPI `info.version` used by `bin/rails action_spec:gen`.

- `open_api_server_url`
  Default: `nil`.
  Sets the default server URL emitted in the generated OpenAPI document.

### I18n

ActionSpec uses `ActiveModel::Errors`, so you can override both messages and attribute names:

```yml
en:
  activemodel:
    attributes:
      action_spec/parameters:
        "profile.nickname": "Profile nickname"
    errors:
      messages:
        required: "is required"
        invalid_type: "must be a valid %{expected}"
```

You can also override messages per error type or per attribute in Ruby:

```ruby
ActionSpec.configure { |config|
  config.error_messages[:required] = "must be present"
  config.error_messages[:invalid_type] = ->(_attribute, options) { "must be a valid #{options.fetch(:expected)}" }
  config.error_messages[:page] = {
    required: "page is mandatory"
  }
}
```

## AI Generation Style Guide

When using AI tools to generate Rails controller code, and the change involves parameter validation, type coercion, default values, or similar parameter contracts, these conventions work well with ActionSpec:

- use `doc { }` or `doc("Summary") { }`; do not add the action name, and do not leave a blank line between the `doc` block and the action method
- use `{ }` blocks inside `doc` as well; prefer them over `do ... end`
- when a batch has 3 fields or fewer and does not contain nested hashes, prefer a single-line style, for example:
  - `json data: { type: String, required: true }`
  - `in_query(name: String, value: String)` (prefer `in_xxx(...)` batch declarations over multiple `xx` DSL lines when possible)
- use `doc_dry`, `scope`, and `px.slice` to reduce repetition in controllers
- when request parameters match model declarations, prefer `.schemas` to keep `doc` concise

## What Is Not Implemented Yet

- reusable `components` generation
- `$ref` generation and deduplication
- `description`, `externalDocs`, `deprecated`, and `security` on operations
- parameter-level `style`, `explode`, `allowReserved`, `examples`, and richer header/cookie serialization controls
- request body `encoding`
- multiple request/response media types beyond the current direct DSL mapping
- response body schema generation; current `response` / `resp` / `error` declarations only generate response descriptions
- response headers
- response links
- callbacks
- webhooks
- path-level shared parameters
- top-level `components.parameters`, `components.requestBodies`, `components.responses`, `components.headers`, `components.examples`, `components.links`, `components.callbacks`, `components.schemas`, `components.securitySchemes`, and `components.pathItems`
- top-level `security`
- top-level `tags`
- top-level `externalDocs`
- `jsonSchemaDialect`
- richer schema keywords beyond the current subset, including nullable/blank semantics, object-level constraints, and composition keywords such as `oneOf`, `anyOf`, `allOf`, and `not`

## Contributing

Contributions / Issues are welcome.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
