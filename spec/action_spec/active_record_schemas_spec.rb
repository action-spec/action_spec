# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Schema::ActiveRecord do
  Column = Struct.new(:name, :type, :null, :default, :comment, :limit, keyword_init: true) do
    def array?
      false
    end
  end

  class DemoPresenceValidator < ActiveModel::Validations::PresenceValidator; end
  class DemoLengthValidator < ActiveModel::Validations::LengthValidator; end
  class DemoFormatValidator < ActiveModel::Validations::FormatValidator; end
  class DemoNumericalityValidator < ActiveModel::Validations::NumericalityValidator; end
  class DemoInclusionValidator < ActiveModel::Validations::InclusionValidator; end

  it "builds action-spec-friendly schemas from columns, enums, and validators" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role birthday score])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: "user name", limit: 50),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: 13),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: 2),
      "birthday" => Column.new(name: "birthday", type: :date, null: true, default: nil, comment: nil, limit: nil),
      "score" => Column.new(name: "score", type: :integer, null: true, default: 1, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1, "visitor" => 2 }
    )
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:phone]),
        DemoLengthValidator.new(attributes: [:name], maximum: 20),
        DemoFormatValidator.new(attributes: [:phone], with: /\A1\d{10}\z/),
        DemoNumericalityValidator.new(attributes: [:score], greater_than_or_equal_to: 1, less_than: 10),
        DemoInclusionValidator.new(attributes: [:birthday], in: [Date.new(2025, 10, 17), Date.new(2025, 10, 18)])
      ]
    )

    expect(user_class.schemas).to eq(
      name!: {
        type: String,
        desc: "user name",
        length: { maximum: 20 }
      },
      phone!: {
        type: String,
        allow_blank: false,
        length: { maximum: 13 },
        pattern: /\A1\d{10}\z/
      },
      role: {
        type: String,
        enum: %w[admin member visitor]
      },
      birthday: {
        type: Date,
        enum: [Date.new(2025, 10, 17), Date.new(2025, 10, 18)]
      },
      score: {
        type: Integer,
        default: 1,
        range: { ge: 1, lt: 10 }
      }
    )
  end

  it "filters schemas by the only option" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(only: %i[role phone!])).to eq(
      phone!: { type: String },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "filters schemas by the except option" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(except: %i[phone!])).to eq(
      name!: { type: String },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "can emit required: true instead of bang keys" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: "user name", limit: 20),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: 13),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:phone])]
    )

    expect(user_class.schemas(bang: false)).to eq(
      name: {
        type: String,
        required: true,
        desc: "user name",
        length: { maximum: 20 }
      },
      phone: {
        type: String,
        required: true,
        allow_blank: false,
        length: { maximum: 13 }
      },
      role: {
        type: String,
        enum: %w[admin member]
      }
    )
  end

  it "accepts bang-style names in only even when bang output is disabled" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(only: %i[phone! role], bang: false)).to eq(
      phone: { type: String, required: true },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "accepts bang-style names in except even when bang output is disabled" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(except: %i[phone!], bang: false)).to eq(
      name: { type: String, required: true },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "applies except after only" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(only: %i[name phone role], except: %i[phone!])).to eq(
      name!: { type: String },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "indexes validators once instead of rescanning them per field" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:phone]),
        DemoFormatValidator.new(attributes: [:phone], with: /\A1\d{10}\z/)
      ]
    )

    expect(user_class).to receive(:validators).once.and_call_original

    user_class.schemas
  end

  it "does not extract required or allow_blank constraints from presence validators that allow blank" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[nickname])
    allow(user_class).to receive(:columns_hash).and_return(
      "nickname" => Column.new(name: "nickname", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:nickname], allow_blank: true)]
    )

    expect(user_class.schemas).to eq(
      nickname: { type: String }
    )
  end

  it "ignores conditional validators when extracting schema constraints" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[nickname score role])
    allow(user_class).to receive(:columns_hash).and_return(
      "nickname" => Column.new(name: "nickname", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "score" => Column.new(name: "score", type: :integer, null: true, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:nickname], if: :published?),
        DemoLengthValidator.new(attributes: [:nickname], minimum: 2, on: :create),
        DemoNumericalityValidator.new(attributes: [:score], greater_than: 0, unless: :draft?),
        DemoInclusionValidator.new(attributes: [:role], in: %w[admin member], if: -> { true })
      ]
    )

    expect(user_class.schemas).to eq(
      nickname: { type: String },
      score: { type: Integer },
      role: { type: String }
    )
  end

  it "still extracts unconditional validators when conditional ones of the same type also exist" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[phone])
    allow(user_class).to receive(:columns_hash).and_return(
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:phone], if: :published?),
        DemoPresenceValidator.new(attributes: [:phone])
      ]
    )

    expect(user_class.schemas).to eq(
      phone!: { type: String, allow_blank: false }
    )
  end

  it "extracts validators for the requested validation context via on" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[nickname score role])
    allow(user_class).to receive(:columns_hash).and_return(
      "nickname" => Column.new(name: "nickname", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "score" => Column.new(name: "score", type: :integer, null: true, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:nickname], on: :create),
        DemoLengthValidator.new(attributes: [:nickname], minimum: 2, on: :create),
        DemoNumericalityValidator.new(attributes: [:score], greater_than: 0, on: :create),
        DemoInclusionValidator.new(attributes: [:role], in: %w[admin member], on: :create),
        DemoLengthValidator.new(attributes: [:nickname], maximum: 20),
        DemoNumericalityValidator.new(attributes: [:score], less_than: 10, on: :update)
      ]
    )

    expect(user_class.schemas(on: :create)).to eq(
      nickname!: { type: String, allow_blank: false, length: { minimum: 2, maximum: 20 } },
      score: { type: Integer, range: { gt: 0 } },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "respects except_on for the requested validation context" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[nickname score])
    allow(user_class).to receive(:columns_hash).and_return(
      "nickname" => Column.new(name: "nickname", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "score" => Column.new(name: "score", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:nickname], except_on: :update),
        DemoNumericalityValidator.new(attributes: [:score], greater_than: 0, except_on: :update)
      ]
    )

    expect(user_class.schemas(on: :create)).to eq(
      nickname!: { type: String, allow_blank: false },
      score: { type: Integer, range: { gt: 0 } }
    )

    expect(user_class.schemas(on: :update)).to eq(
      nickname: { type: String },
      score: { type: Integer }
    )
  end

  it "can force all exported fields to be required" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(required: true)).to eq(
      name!: { type: String },
      phone!: { type: String },
      role!: { type: String, enum: %w[admin member] }
    )

    expect(user_class.schemas(required: true, bang: false)).to eq(
      name: { type: String, required: true },
      phone: { type: String, required: true },
      role: { type: String, enum: %w[admin member], required: true }
    )
  end

  it "can force all exported fields to be non-required" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:phone])]
    )

    expect(user_class.schemas(required: false)).to eq(
      name: { type: String },
      phone: { type: String, allow_blank: false },
      role: { type: String, enum: %w[admin member] }
    )
  end

  it "can mark only selected fields as required" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:phone])]
    )

    expect(user_class.schemas(required: %i[role phone!])).to eq(
      name: { type: String },
      phone!: { type: String, allow_blank: false },
      role!: { type: String, enum: %w[admin member] }
    )

    expect(user_class.schemas(required: %i[role phone!], bang: false)).to eq(
      name: { type: String },
      phone: { type: String, allow_blank: false, required: true },
      role: { type: String, enum: %w[admin member], required: true }
    )
  end

  it "can merge custom schema fragments by raw field name" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name role])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: "user name", limit: 20),
      "role" => Column.new(name: "role", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return(
      "role" => { "admin" => 0, "member" => 1 }
    )
    allow(user_class).to receive(:validators).and_return([])

    expect(user_class.schemas(merge: { name: { desc: "nickname" }, role: { example: "admin" } })).to eq(
      name!: { type: String, desc: "nickname", length: { maximum: 20 } },
      role: { type: String, enum: %w[admin member], example: "admin" }
    )
  end

  it "deep merges custom schema fragments" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name score])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: 20),
      "score" => Column.new(name: "score", type: :integer, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [DemoNumericalityValidator.new(attributes: [:score], greater_than_or_equal_to: 1)]
    )

    expect(user_class.schemas(merge: {
      name: { length: { minimum: 2 } },
      score: { range: { le: 10 } }
    })).to eq(
      name!: { type: String, length: { minimum: 2, maximum: 20 } },
      score: { type: Integer, range: { ge: 1, le: 10 } }
    )
  end

  it "does not let merge depend on bang-style output names" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:phone])]
    )

    expect(user_class.schemas(
      bang: false,
      required: false,
      merge: { name: { desc: "nickname" }, phone: { example: "13800138000" } }
    )).to eq(
      name: { type: String, desc: "nickname" },
      phone: { type: String, allow_blank: false, example: "13800138000" }
    )
  end

  it "lets merge disable required output, including bang-style keys" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[name phone])
    allow(user_class).to receive(:columns_hash).and_return(
      "name" => Column.new(name: "name", type: :string, null: false, default: nil, comment: nil, limit: nil),
      "phone" => Column.new(name: "phone", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [DemoPresenceValidator.new(attributes: [:phone])]
    )

    expect(user_class.schemas(
      merge: { name: { required: false }, phone: { required: false } }
    )).to eq(
      name: { type: String },
      phone: { type: String, allow_blank: false }
    )
  end

  it "still ignores if and unless even when on is provided" do
    user_class = Class.new(ActiveRecord::Base) do
      include ActionSpec::Schema::ActiveRecord

      def self.name
        "User"
      end
    end

    allow(user_class).to receive(:column_names).and_return(%w[nickname])
    allow(user_class).to receive(:columns_hash).and_return(
      "nickname" => Column.new(name: "nickname", type: :string, null: true, default: nil, comment: nil, limit: nil)
    )
    allow(user_class).to receive(:defined_enums).and_return({})
    allow(user_class).to receive(:validators).and_return(
      [
        DemoPresenceValidator.new(attributes: [:nickname], on: :create, if: :published?),
        DemoLengthValidator.new(attributes: [:nickname], on: :create, unless: :draft?, minimum: 2)
      ]
    )

    expect(user_class.schemas(on: :create)).to eq(
      nickname: { type: String }
    )
  end
end
