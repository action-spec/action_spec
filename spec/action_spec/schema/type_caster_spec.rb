# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActionSpec::Schema::TypeCaster do
  describe ".cast" do
    it "casts supported scalar types" do
      expect(described_class.cast(String, 12)).to eq("12")
      expect(described_class.cast(Integer, "12")).to eq(12)
      expect(described_class.cast(Float, "12.5")).to eq(12.5)
      expect(described_class.cast(BigDecimal, "12.5")).to eq(BigDecimal("12.5"))
      expect(described_class.cast(:boolean, "true")).to eq(true)
      expect(described_class.cast(Date, "2025-10-17")).to eq(Date.iso8601("2025-10-17"))
      expect(described_class.cast(DateTime, "2025-10-17T12:30:00Z")).to eq(DateTime.iso8601("2025-10-17T12:30:00Z"))
    end

    it "supports host-defined Boolean constants without defining one itself" do
      stub_const("Boolean", :host_boolean)

      expect(described_class.cast(Boolean, "false")).to eq(false)
    end

    it "raises a cast error for invalid scalar values" do
      expect { described_class.cast(Integer, "abc") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      expect { described_class.cast(Date, "not-a-date") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
      expect { described_class.cast(:boolean, "maybe") }.to raise_error(ActionSpec::Schema::TypeCaster::CastError)
    end

    it "accepts file-like objects without loading file contents" do
      file = Tempfile.new("action-spec")
      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: file,
        filename: "action-spec.txt",
        type: "text/plain"
      )

      expect(described_class.cast(File, uploaded_file)).to equal(uploaded_file)
    ensure
      file.close!
    end
  end
end
