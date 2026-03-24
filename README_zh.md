# ActionSpec [WIP]

Concise and Powerful API Documentation Solution for Rails.

<img src=".github/assets/action_spec.jpg" />

- OpenAPI 版本: `v3.2.0`
- 要求: Ruby 3.1+ 和 Rails 7.0+
- 注意：本项目使用 Codex 花费一个小时实现，尚未人工 review，未在生产环境验证过。（但是已驱使 Codex 生成了比较详细的 Rspec 测试）

## 概览

ActionSpec 把接口契约直接放在 controller action 旁边。它提供一套可读性很强的 DSL 来声明请求与响应结构，并提供运行时参数校验、类型转换与 `px` 输出。

## 当前范围

1. 用 DSL 在 controller 旁边声明接口契约
2. 基于 DSL 对请求做校验和类型转换
3. 生成一份经过校验后的 hash 供 action 直接使用

OpenAPI 文档生成已在规划中，但当前还没有实现。

### 快速上手

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

## 安装

```ruby
# Gemfile
gem "action_spec"
```

然后执行：

```bash
$ bundle
```

## 用法

### `doc` 怎么绑定

默认写法会自动绑定到后面的实例方法：

```ruby
doc {
  json data: { name!: String }
}
def create
end
```

默认写法同样可以带 summary：

```ruby
doc("创建用户") {
  json data: { name!: String }
}
def create
end
```

如果你希望显式把 action 写出来，也可以这样：

```ruby
doc(:create, "创建用户") {
  json data: { name!: String }
}
def create
end
```

### 用 `doc_dry` 抽公共声明

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

贴近 `zero-rails_openapi` 写法

#### 1. 参数位置 DSL

单个参数：

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

#### 2. request body DSL

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

#### 3. response DSL

```ruby
response 200, desc: "success"
response 422, "validation failed"
resp 400, "bad request"
error 401, "unauthorized"
```

目前 `response` 只会保存元数据，暂时不会自动驱动响应渲染。

### Schema 怎么写

#### 1. 必填字段

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

#### 2. 当前支持的运行时类型

当前 validator/coercer 已支持：

1. `String`
2. `Integer`
3. `Float`
4. `BigDecimal`
5. `:boolean`
6. 宿主项目自己定义的 `Boolean` 常量
7. `Date`
8. `DateTime`
9. `Time`
10. `File`
11. `Object`

嵌套写法：

```ruby
json data: {
  tags: [String],
  profile: {
    nickname!: String
  },
  settings: { type: Object }
}
```

#### 3. 类型与边界矩阵

| 类型 | 可接受输入示例 | 拒绝输入 / 说明 |
| --- | --- | --- |
| `String` | `12`、`true`、`""` | 遵循 `ActiveModel::Type::String`，所以 `true` 会变成 `"t"` |
| `Integer` | `"0"`、`"-12"`、`"+7"`、`12` | 拒绝 `"12.3"`、`"abc"`、`""` |
| `Float` | `"0"`、`"-12.5"`、`12`、`12.5` | 拒绝 `"12.3.4"`、`"abc"` |
| `BigDecimal` | `"0"`、`"-12.50"`、`12`、`12.5` | 拒绝 `"abc"` |
| `:boolean` / 宿主项目自带的 `Boolean` | `true`、`false`、`"1"`、`"0"`、`"true"`、`"false"`、`"yes"`、`"no"`、`"on"`、`"off"` | 拒绝含糊值，例如 `""`、`"2"`、`"TRUE "`、`"maybe"` |
| `Date` | `"2025-10-17"` | 拒绝非法日期，例如 `"2025-02-30"` |
| `DateTime` | `"2025-10-17T12:30:00Z"` | 拒绝非法时间，例如 `"2025-10-17 25:00:00"` |
| `Time` | `"2025-10-17T12:30:00Z"` | 遵循 `ActiveModel::Type::Time`，日期部分会变成 `2000-01-01` |
| `File` | `ActionDispatch::Http::UploadedFile`、`Tempfile`、类文件 IO 对象 | 保留原对象，不会把文件内容读进内存 |
| `Object` | `Hash`、`ActionController::Parameters`、任意 Ruby 对象 | 作为标量 `Object` 时原样透传；嵌套 hash 会按对象 schema 递归解析 |
| `[Type]` | 比如 `[Integer]` 接收 `%w[1 2 3]` | 非数组会报错，数组项错误会记录成 `tags.1` 这种路径 |
| 嵌套对象 | `{ profile: { nickname: "neo" } }` | 非 hash 会报错，嵌套字段错误会记录成 `profile.nickname` |

#### 4. 当前已生效的运行时选项

```ruby
query :page, Integer, default: 1
query :today, Date, default: -> { Time.current.to_date }
query :status, String, enum: %w[draft published]
query :score, Integer, range: { ge: 1, le: 5 }
query :slug, String, pattern: /\A[a-z\-]+\z/
```

这些选项当前会作为元数据保存下来，但运行时暂未实际使用：

1. `desc`
2. `example`
3. `examples`
4. `allow_nil`
5. `allow_blank`

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

### 配置

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

### 当前还没实现的部分

1. OpenAPI 文档生成
2. 基于 `response` 的自动响应渲染
3. component / ref 体系
4. `allow_nil` / `allow_blank` 的运行时行为

## 贡献
.

## 许可
本项目以开源方式发布，遵循 [MIT License](https://opensource.org/licenses/MIT)。
