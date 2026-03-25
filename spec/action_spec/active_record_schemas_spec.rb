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
      "name!" => {
        type: String,
        desc: "user name",
        length: { maximum: 20 }
      },
      "phone!" => {
        type: String,
        length: { maximum: 13 },
        pattern: /\A1\d{10}\z/
      },
      "role" => {
        type: String,
        enum: %w[admin member visitor]
      },
      "birthday" => {
        type: Date,
        enum: [Date.new(2025, 10, 17), Date.new(2025, 10, 18)]
      },
      "score" => {
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
      "phone!" => { type: String },
      "role" => { type: String, enum: %w[admin member] }
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
      "name" => {
        type: String,
        required: true,
        desc: "user name",
        length: { maximum: 20 }
      },
      "phone" => {
        type: String,
        required: true,
        length: { maximum: 13 }
      },
      "role" => {
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
      "phone" => { type: String, required: true },
      "role" => { type: String, enum: %w[admin member] }
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
end
