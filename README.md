# ActionSpec [WIP]

Concise and Powerful API Documentation Solution for Rails.

<img src=".github/assets/action_spec.jpg" />

- OpenAPI version: `v3.2.0`
- Requires: Ruby 3.1+ and Rails 7.0+
- Note: this project was implemented with Codex in about one hour, has not yet been manually reviewed, and has not been validated in production. It does, however, come with fairly detailed RSpec tests generated with Codex.

## Overview

ActionSpec keeps API request contracts close to controller actions. It gives you a readable DSL for declaring request and response shapes, and runtime helpers for validation and type coercion.

## Current Scope

- A controller-friendly DSL for declaring request and response contracts
- Runtime validation and type coercion based on that DSL
- `px`, a validated hash built from the declared contract

OpenAPI generation is planned, but not implemented yet.

### Quick Start

```ruby
class UsersController < ApplicationController
  before_action :validate_and_coerce_params!, only: :create

  doc {
    header :Authorization, String
    path :account_id, Integer
    query :locale, String, default: "zh-CN"
    query :page, Integer, default: -> { 1 }

    json data: {
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

## Usage

### How To Bind `doc`

Default form, with action inferred from the next instance method:

```ruby
doc {
  json data: { name!: String }
}
def create
end
```

You can still provide a summary in the default form:

```ruby
doc("Create user") {
  json data: { name!: String }
}
def create
end
```

You can also bind it explicitly when you want the action name declared in place:

```ruby
doc(:create, "Create user") {
  json data: { name!: String }
}
def create
end
```

### Shared Declarations With `doc_dry`

```ruby
class ApplicationController < ActionController::API
  doc_dry %i[show update destroy] do
    path! :id, Integer
  end

  doc_dry :index do
    query :page, Integer, default: 1
    query :per, Integer, default: 20
  end
end
```

All matching dry blocks are applied before the action-specific `doc`.

### DSL Reference

ActionSpec keeps the request DSL close to `zero-rails_openapi`.

#### Parameter Locations

Single-parameter forms:

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

#### Request Bodies

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

#### Response Metadata

```ruby
response 200, desc: "success"
response 422, "validation failed"
resp 400, "bad request"
error 401, "unauthorized"
```

Response declarations are stored as metadata now. They are not yet used to render responses automatically.

### Schema Writing

#### Required Fields

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

#### Supported Runtime Types

Scalar types currently supported by validation/coercion:

- `String`
- `Integer`
- `Float`
- `BigDecimal`
- `:boolean`
- host-defined `Boolean` constant, if the host app already defines one
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
  settings: { type: Object }
}
```

#### Type And Boundary Matrix

| Type | Accepted examples | Rejected examples / notes |
| --- | --- | --- |
| `String` | `12`, `true`, `""` | Follows `ActiveModel::Type::String`, so `true` becomes `"t"` |
| `Integer` | `"0"`, `"-12"`, `"+7"`, `12` | Rejects `"12.3"`, `"abc"`, `""` |
| `Float` | `"0"`, `"-12.5"`, `12`, `12.5` | Rejects `"12.3.4"`, `"abc"` |
| `BigDecimal` | `"0"`, `"-12.50"`, `12`, `12.5` | Rejects `"abc"` |
| `:boolean` / host-defined `Boolean` | `true`, `false`, `"1"`, `"0"`, `"true"`, `"false"`, `"yes"`, `"no"`, `"on"`, `"off"` | Rejects ambiguous values such as `""`, `"2"`, `"TRUE "`, `"maybe"` |
| `Date` | `"2025-10-17"` | Rejects invalid dates such as `"2025-02-30"` |
| `DateTime` | `"2025-10-17T12:30:00Z"` | Rejects invalid datetimes such as `"2025-10-17 25:00:00"` |
| `Time` | `"2025-10-17T12:30:00Z"` | Follows `ActiveModel::Type::Time`, so the date part becomes `2000-01-01` |
| `File` | `ActionDispatch::Http::UploadedFile`, `Tempfile`, file-like IO objects | Keeps the object as-is and does not read file contents into memory |
| `Object` | `Hash`, `ActionController::Parameters`, arbitrary Ruby objects | Passed through for scalar `Object`; nested hashes use object schema resolution |
| `[Type]` | arrays such as `%w[1 2 3]` for `[Integer]` | Rejects non-array values, and reports item errors like `tags.1` |
| nested object | `{ profile: { nickname: "neo" } }` | Rejects non-hash values, and reports nested paths like `profile.nickname` |

#### Supported Runtime Options

These options are currently used by the validator:

```ruby
query :page, Integer, default: 1
query :today, Date, default: -> { Time.current.to_date }
query :status, String, enum: %w[draft published]
query :score, Integer, range: { ge: 1, le: 5 }
query :slug, String, pattern: /\A[a-z\-]+\z/
```

These options are currently accepted as metadata, mainly for future OpenAPI work, but are not yet used by the runtime validator:

- `desc`
- `example`
- `examples`
- `allow_nil`
- `allow_blank`

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

#### `validate_and_coerce_params!`

Validates and coerces values before exposing them on `px`.

```ruby
before_action :validate_and_coerce_params!
```

Example:

- request query param `"page" => "2"`
- DSL says `query :page, Integer`
- result: `px[:page] == 2`

### Reading Validated Values With `px`

`px` is a hash.

```ruby
px[:id]
px[:page]
px[:profile][:nickname]
px.to_h
```

It also includes grouped buckets:

```ruby
px[:path]
px[:query]
px[:body]
px[:headers]
px[:cookies]
```

Notes:

- root values from path/query/body are also flattened into `px[:name]`
- header keys are stored in lowercase dashed form, but reading remains compatible with original forms such as `Authorization` and `HTTP_AUTHORIZATION`, for example:

```ruby
px[:headers][:authorization]
px[:headers]["Authorization"]
px[:headers]["HTTP_AUTHORIZATION"]
```

- original `params` are not mutated

### Errors

Validation errors are stored in `ActiveModel::Errors`.

If invalid parameters are not rescued, ActionSpec raises `ActionSpec::InvalidParameters`:

```ruby
begin
  validate_and_coerce_params!
rescue ActionSpec::InvalidParameters => error
  error.errors.full_messages
end
```

The exception also keeps the full validation result on `error.result` and `error.parameters`.

### Default Rescue Behavior

By default, when a controller raises `ActionSpec::InvalidParameters`, ActionSpec catches it automatically and returns a JSON error response:

```ruby
rescue_from ActionSpec::InvalidParameters
```

The default JSON response is:

```json
{
  "errors": {
    "page": ["Page is required"]
  }
}
```

### Configuration

```ruby
ActionSpec.configure do |config|
  config.rescue_invalid_parameters = true
  config.invalid_parameters_status = :bad_request

  config.error_messages[:invalid_type] = ->(_attribute, options) do
    "should be coercible to #{options.fetch(:expected)}"
  end

  config.invalid_parameters_renderer = ->(controller, error) do
    controller.render json: {
      code: "invalid_parameters",
      errors: error.errors.to_hash(full_messages: true)
    }, status: :unprocessable_entity
  end
end
```

Available config keys:

- `invalid_parameters_exception_class`
  Default: `ActionSpec::InvalidParameters`.
  Controls which exception class is raised when validation fails.

- `invalid_parameters_status`
  Default: `:bad_request`.
  Controls the HTTP status used by the built-in `rescue_from` renderer.

- `rescue_invalid_parameters`
  Default: `true`.
  When this option is enabled, controllers use the default `rescue_from ActionSpec::InvalidParameters`.

- `invalid_parameters_renderer`
  Default: `nil`.
  Lets you replace the built-in JSON error response. It can be a proc receiving `(controller, error)`, or a block executed in controller context.

- `error_messages`
  Default: `{}`.
  Lets you override error messages by error type, or by attribute plus error type.

### I18n

ActionSpec loads its own locale files and uses `ActiveModel::Errors`, so you can override both messages and attribute names:

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
ActionSpec.configure do |config|
  config.error_messages[:required] = "must be present"
  config.error_messages[:invalid_type] = ->(_attribute, options) { "must be a valid #{options.fetch(:expected)}" }
  config.error_messages[:page] = {
    required: "page is mandatory"
  }
end
```

### What Is Not Implemented Yet

- OpenAPI document generation
- automatic response rendering from `response`
- reusable schema/components system from `zero-rails_openapi`
- runtime behavior for `allow_nil` / `allow_blank`

## Contributing
.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
