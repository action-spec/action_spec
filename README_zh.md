# ActionSpec [WIP]

Concise and Powerful API Documentation Solution for Rails.

<img src=".github/assets/action_spec.jpg" />

- OpenAPI 版本: `v3.2.0`
- 要求: Ruby 3.1+ 和 Rails 7.0+
- 注意：本项目使用 Codex 花费两个小时实现，尚未人工 review，未在生产环境验证过。（但是已驱使 Codex 生成了比较详细的 Rspec 测试）

## 目录

1. [OpenAPI 生成](#openapi-生成)
2. [Doc DSL](#doc-dsl)
   1. [`doc`](#doc)
   2. [`doc_dry`](#doc_dry)
   3. [DSL 详细说明](#dsl-详细说明)
3. [Schemas](#schemas)
   1. [声明一个字段为必填项](#1-声明一个字段为必填项)
   2. [字段类型](#2-字段类型)
   3. [字段选项](#3-字段选项)
   4. [从 ActiveRecord 生成 Schemas](#4-从-activerecord-生成-schemas)
   5. [类型与边界矩阵](#5-类型与边界矩阵)
4. [参数验证和类型转换](#参数验证和类型转换)
   1. [参数处理流程](#参数处理流程)
   2. [`px` 怎么用](#px-怎么用)
   3. [错误处理](#错误处理)
   4. [默认 `rescue_from`](#默认-rescue_from)
5. [配置和 I18n](#配置和-i18n)
   1. [配置](#配置)
   2. [I18n](#i18n)

## 示例

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

## 安装

```ruby
# Gemfile
gem "action_spec"
```

然后执行：

```bash
$ bundle
```

## OpenAPI 生成

基于当前 Rails 路由和 ActionSpec 的 controller DSL 生成一份 OpenAPI 文档：

```bash
bin/rails action_spec:gen
```

默认会输出到：

```text
docs/openapi.yml
```

如果只是临时执行一次，也可以用环境变量覆盖默认输出路径和文档元信息：

```bash
bin/rails action_spec:gen \
  OUTPUT=docs/openapi.yml \
  TITLE="My API" \
  VERSION="2026.03" \
  SERVER_URL="https://api.example.com"
```

说明：

1. 只会生成那些已经有对应 `doc` 声明、并且真的挂在 Rails 路由上的 controller action。
2. 像 `/users/:id(.:format)` 这样的 Rails 路径，会输出成 `/users/{id}`。
3. 请求参数、请求体、响应描述，会基于当前 DSL 能表达的内容生成。
4. 如果配置和环境变量里都没有提供 `TITLE` 或 `VERSION`，ActionSpec 会使用应用名推导的默认值。

## Doc DSL

### `doc`

`doc` 会自动绑定到后面的实例方法：

```ruby
doc {
  form data: {    # <= request body DSL
    name!: String # <= schema DSL
  }
}
def create
end
```

可以带 summary：

```ruby
doc("创建用户") {
  form data: { name!: String }
}
def create
end
```

如果你希望显式把 action 写出来，也可以这样：

```ruby
doc(:create, "创建用户") {
  form data: { name!: String }
}
def create
end
```

### `doc_dry`

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

对应 action 的 dry 声明会先应用，再应用当前 `doc` 自己的声明。

### DSL 详细说明

#### 1. Parameter

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

bang 方法表示“必填”。例如 `query! :page, Integer` 表示请求里必须传 `page`。

批量声明参数：

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

#### 2. request body

通用形式：

```ruby
body :json, data: { name!: String, age: Integer }
```

便捷方法：

```ruby
json data: { name!: String }

json! data: { name!: String }

form data: { file!: File, position: String }

form! data: { file!: File }
```

单个 multipart 字段：

```ruby
data :file, File
```

说明：

1. 运行时校验里，`body/body!`、`json/json!`、`form/form!` 最终都会汇总进同一份请求体契约。
2. `body!`、`json!`、`form!` 目前主要是为了保留 DSL 兼容性；“整个 body 是否 required” 这个根级语义，运行时还没有单独做规则区分。

#### 3. response

```ruby
response 200, desc: "success"
response 422, "validation failed"
resp 400, "bad request"
error 401, "unauthorized"
```

目前 `response` 只会保存元数据，暂时不会自动驱动响应渲染。

## Schemas

#### 1. 声明一个字段为必填项

可以写在参数方法上：

```ruby
query! :page, Integer
```

也可以写在对象字段上：

```ruby
json data: {
  name!: String,
  profile: {
    nickname!: String
  }
}
```

`!` 的含义：

1. `query!`、`path!`、`header!`、`cookie!` 表示这个参数本身必填。
2. `name!:`、`nickname!:` 这种写法表示嵌套对象里的字段必填。
3. `body!`、`json!`、`form!` 目前是为了保持 DSL 一致性；在当前运行时行为里，它们和不带 `!` 的版本等价。

#### 2. 字段类型

当前 validator/coercer 已支持：

1. `String`
2. `Integer`
3. `Float`
4. `BigDecimal`
5. `:boolean` / `Boolean`
6. `Date`
7. `DateTime`
8. `Time`
9. `File`
10. `Object`

嵌套写法：

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

#### 3. 字段选项

这些选项当前会参与运行时校验：

```ruby
query :page, Integer, default: 1
query :today, Date, default: -> { Time.current.to_date }
query :status, String, enum: %w[draft published]
query :score, Integer, range: { ge: 1, le: 5 }
query :slug, String, pattern: /\A[a-z\-]+\z/
```

这些选项当前已经用于 OpenAPI 文档生成，但运行时暂未实际使用：

1. `desc`
2. `example`
3. `examples`

这些选项目前在运行时校验和 OpenAPI 文档生成里都还没有实际使用：

4. `allow_nil`
5. `allow_blank`

#### 4. 从 ActiveRecord 生成 Schemas

如果模型是 `ActiveRecord::Base`，可以直接从模型导出一份可用于 ActionSpec DSL 的 schema hash：

```ruby
class UsersController < ApplicationController
  doc {
    form data: User.schemas
  }
  def create
  end
end
```

`User.schemas` 返回的就是一份可以直接传给 `form data:`、`json data:` 或 `body` 的 hash。

默认会包含模型的全部字段：

```ruby
User.schemas
```

如果只想导出部分字段，可以使用 `only:`：

```ruby
User.schemas(only: %i[name phone role])
```

ActionSpec 会尽量从 ActiveRecord / ActiveModel 中提取和 schema 有关的信息，包括：

1. 字段类型
2. 必填状态，并输出成 `"name!"` 这样的 bang key
3. `enum` 定义
4. `default`
5. 列注释对应的 `desc`
6. format validator 对应的 `pattern`
7. numericality validator 对应的 `range`
8. length validator 和字符串列长度对应的 `length`

输出示例：

```ruby
User.schemas
# {
#   "name!" => { type: String, desc: "user name", length: { maximum: 20 } },
#   "phone!" => { type: String, length: { maximum: 13 }, pattern: /\A1\d{10}\z/ },
#   "role" => { type: String, enum: %w[admin member visitor] }
# }
```

#### 5. 类型与边界矩阵

| 类型 | 可接受输入示例 | 拒绝输入 / 说明 |
| --- | --- | --- |
| `String` | `12`、`true`、`""` | 遵循 `ActiveModel::Type::String`，所以 `true` 会变成 `"t"` |
| `Integer` | `"0"`、`"-12"`、`"+7"`、`12` | 拒绝 `"12.3"`、`"abc"`、`""` |
| `Float` | `"0"`、`"-12.5"`、`12`、`12.5` | 拒绝 `"12.3.4"`、`"abc"` |
| `BigDecimal` | `"0"`、`"-12.50"`、`12`、`12.5` | 拒绝 `"abc"` |
| `:boolean` / `Boolean` | `true`、`false`、`"1"`、`"0"`、`"true"`、`"false"`、`"yes"`、`"no"`、`"on"`、`"off"` | 拒绝含糊值，例如 `""`、`"2"`、`"TRUE "`、`"maybe"` |
| `Date` | `"2025-10-17"` | 拒绝非法日期，例如 `"2025-02-30"` |
| `DateTime` | `"2025-10-17T12:30:00Z"` | 拒绝非法时间，例如 `"2025-10-17 25:00:00"` |
| `Time` | `"2025-10-17T12:30:00Z"` | 遵循 `ActiveModel::Type::Time`，日期部分会变成 `2000-01-01` |
| `File` | `ActionDispatch::Http::UploadedFile`、`Tempfile`、类文件 IO 对象 | 保留原对象，不会把文件内容读进内存 |
| `Object` | `Hash`、`ActionController::Parameters`、任意 Ruby 对象 | 作为标量 `Object` 时原样透传；嵌套 hash 会按对象 schema 递归解析 |
| `[Type]` | 比如 `[Integer]` 接收 `%w[1 2 3]` | 非数组会报错，数组项错误会记录成 `tags.1` 这种路径 |
| 嵌套对象 | `{ profile: { nickname: "neo" } }` | 非 hash 会报错，嵌套字段错误会记录成 `profile.nickname` |


## 参数验证和类型转换

### 参数处理流程

#### `validate_params!`

只做校验，`px` 中保留原始值：

```ruby
before_action :validate_params!
```

例如：

1. 请求进来 `"page" => "2"`
2. DSL 写的是 `query :page, Integer`
3. 结果是 `px[:page] == "2"`

#### `validate_and_coerce_params!`

校验后再做类型转换：

```ruby
before_action :validate_and_coerce_params!
```

例如：

1. 请求进来 `"page" => "2"`
2. DSL 写的是 `query :page, Integer`
3. 结果是 `px[:page] == 2`

### `px` 怎么用

`px` 就是一个 hash。

```ruby
px[:id]
px[:page]
px[:profile][:nickname]
px.to_h
```

它也会保留分组视图：

```ruby
px[:path]
px[:query]
px[:body]
px[:headers]
px[:cookies]
```

说明：

1. path/query/body 的字段也会被铺平到 `px[:field]`
2. header key 内部会按小写 dashed 形式存储，但读取时兼容 `Authorization`、`HTTP_AUTHORIZATION` 这类原始写法，例如：
   ```ruby
   px[:headers][:authorization]
   px[:headers]["Authorization"]
   px[:headers]["HTTP_AUTHORIZATION"]
   ```
3. 原始 `params` 不会被回写修改

### 错误处理

校验错误会进入 `ActiveModel::Errors`。

如果你关闭默认 rescue，则会抛出 `ActionSpec::InvalidParameters`：

```ruby
begin
  validate_and_coerce_params!
rescue ActionSpec::InvalidParameters => error
  error.errors.full_messages
end
```

异常对象上也保留了完整结果，可通过 `error.result` 或 `error.parameters` 访问。

### 默认 `rescue_from`

默认情况下，如果 controller 里抛出了 `ActionSpec::InvalidParameters`，ActionSpec 会自动捕获这个异常，并返回一份 JSON 错误响应：

```ruby
rescue_from ActionSpec::InvalidParameters
```

默认响应：

```json
{
  "errors": {
    "page": ["Page is required"]
  }
}
```

## 配置和 I18n

### 配置

```ruby
ActionSpec.configure do |config|
  config.rescue_invalid_parameters = true
  config.invalid_parameters_status = :bad_request
  config.open_api_output = "docs/openapi.yml"
  config.open_api_title = "My API"
  config.open_api_version = "2026.03"
  config.open_api_server_url = "https://api.example.com"

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

当前可配置项：

1. `invalid_parameters_exception_class`
   默认值：`ActionSpec::InvalidParameters`。
   用来指定校验失败时抛出的异常类型。

2. `invalid_parameters_status`
   默认值：`:bad_request`。
   用来指定内置 `rescue_from` 渲染器返回的 HTTP 状态码。

3. `rescue_invalid_parameters`
   默认值：`true`。
   开启后，controller 会使用默认的 `rescue_from ActionSpec::InvalidParameters` 处理逻辑。

4. `invalid_parameters_renderer`
   默认值：`nil`。
   用来自定义校验失败时的响应渲染逻辑。可以是接收 `(controller, error)` 的 proc，也可以是运行在 controller 上下文中的 block。

5. `error_messages`
   默认值：`{}`。
   用来按错误类型，或者按“字段 + 错误类型”的粒度覆写错误消息。

6. `open_api_output`
   默认值：`"docs/openapi.yml"`。
   用来指定 `bin/rails action_spec:gen` 生成文档时的默认输出路径。

7. `open_api_title`
   默认值：`nil`。
   用来指定 `bin/rails action_spec:gen` 生成的 OpenAPI 文档 `info.title`。

8. `open_api_version`
   默认值：`nil`。
   用来指定 `bin/rails action_spec:gen` 生成的 OpenAPI 文档 `info.version`。

9. `open_api_server_url`
   默认值：`nil`。
   用来指定生成文档里的默认 server URL。

### I18n

ActionSpec 会加载自己的 locale，并基于 `ActiveModel::Errors` 工作，所以你可以覆写消息和字段名：

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

你也可以直接在 Ruby 里按错误类型或字段覆写消息：

```ruby
ActionSpec.configure do |config|
  config.error_messages[:required] = "must be present"
  config.error_messages[:invalid_type] = ->(_attribute, options) { "must be a valid #{options.fetch(:expected)}" }
  config.error_messages[:page] = {
    required: "page is mandatory"
  }
end
```

## 当前还没实现的部分

1. 可复用的 `components` 生成
2. `$ref` 生成与去重
3. operation 上的 `description`、`operationId`、`tags`、`externalDocs`、`deprecated`、`security`
4. parameter 上的 `style`、`explode`、`allowReserved`、`examples`，以及更完整的 header / cookie 序列化控制
5. request body 的 `encoding`
6. 除当前 DSL 直接映射之外的更多 request / response media type
7. response body schema 生成；当前 `response` / `resp` / `error` 只会生成响应描述
8. response headers
9. response links
10. callbacks
11. webhooks
12. path 级共享 parameters
13. 顶层 `components.parameters`、`components.requestBodies`、`components.responses`、`components.headers`、`components.examples`、`components.links`、`components.callbacks`、`components.schemas`、`components.securitySchemes`、`components.pathItems`
14. 顶层 `security`
15. 顶层 `tags`
16. 顶层 `externalDocs`
17. `jsonSchemaDialect`
18. 超出当前子集的更多 schema 关键字支持，包括 nullable / blank 语义、对象级约束，以及 `oneOf`、`anyOf`、`allOf`、`not` 这类组合关键字

## 贡献
.

## 许可
本项目以开源方式发布，遵循 [MIT License](https://opensource.org/licenses/MIT)。
