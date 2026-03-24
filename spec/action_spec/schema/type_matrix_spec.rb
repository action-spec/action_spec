# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Schema::TypeCaster do
  describe "type and boundary matrix" do
    context "with String" do
      it "coerces scalars into strings" do
        expect(described_class.cast(String, 12)).to eq("12")
        expect(described_class.cast(String, true)).to eq("t")
        expect(described_class.cast(String, "")).to eq("")
      end
    end

    context "with Integer" do
      it "accepts integer-like strings" do
        expect(described_class.cast(Integer, "0")).to eq(0)
        expect(described_class.cast(Integer, "-12")).to eq(-12)
        expect(described_class.cast(Integer, "+7")).to eq(7)
      end

      it "rejects non-integer strings" do
        expect { described_class.cast(Integer, "12.3") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
        expect { described_class.cast(Integer, "abc") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
        expect { described_class.cast(Integer, "") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with Float" do
      it "accepts integer and decimal strings" do
        expect(described_class.cast(Float, "0")).to eq(0.0)
        expect(described_class.cast(Float, "-12.5")).to eq(-12.5)
      end

      it "rejects malformed float strings" do
        expect { described_class.cast(Float, "12.3.4") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
        expect { described_class.cast(Float, "abc") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with BigDecimal" do
      it "accepts numeric strings" do
        expect(described_class.cast(BigDecimal, "0")).to eq(BigDecimal("0"))
        expect(described_class.cast(BigDecimal, "-12.50")).to eq(BigDecimal("-12.5"))
      end

      it "rejects non-numeric strings" do
        expect { described_class.cast(BigDecimal, "abc") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with boolean" do
      it "accepts common true values" do
        %w[1 true t yes on].each do |value|
          expect(described_class.cast(:boolean, value)).to eq(true)
        end
      end

      it "accepts common false values" do
        %w[0 false f no off].each do |value|
          expect(described_class.cast(:boolean, value)).to eq(false)
        end
      end

      it "rejects ambiguous boolean values" do
        [ "", "2", "TRUE ", "maybe" ].each do |value|
          expect { described_class.cast(:boolean, value) }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
        end
      end
    end

    context "with Date" do
      it "accepts ISO8601 dates" do
        expect(described_class.cast(Date, "2025-10-17")).to eq(Date.iso8601("2025-10-17"))
      end

      it "rejects invalid dates" do
        expect { described_class.cast(Date, "2025-02-30") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
        expect { described_class.cast(Date, "not-a-date") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with DateTime" do
      it "accepts ISO8601 datetimes" do
        expect(described_class.cast(DateTime, "2025-10-17T12:30:00Z")).to eq(DateTime.iso8601("2025-10-17T12:30:00Z"))
      end

      it "rejects invalid datetimes" do
        expect { described_class.cast(DateTime, "2025-10-17 25:00:00") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with Time" do
      it "follows ActiveModel::Type::Time semantics for ISO8601 datetimes" do
        expect(described_class.cast(Time, "2025-10-17T12:30:00Z")).to eq(Time.iso8601("2000-01-01T12:30:00Z"))
      end

      it "rejects invalid times" do
        expect { described_class.cast(Time, "not-a-time") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with File" do
      it "accepts tempfile and uploaded file objects" do
        tempfile = Tempfile.new("action-spec")
        uploaded_file = ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename: "action-spec.txt",
          type: "text/plain"
        )

        expect(described_class.cast(File, tempfile)).to equal(tempfile)
        expect(described_class.cast(File, uploaded_file)).to equal(uploaded_file)
      ensure
        tempfile.close!
      end

      it "rejects non-file values" do
        expect { described_class.cast(File, "not-a-file") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      end
    end

    context "with Object" do
      it "passes object-like values through" do
        input = { "name" => "Tom" }

        expect(described_class.cast(Object, input)).to equal(input)
      end
    end
  end
end
