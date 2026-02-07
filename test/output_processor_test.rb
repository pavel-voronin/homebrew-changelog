# typed: false
# frozen_string_literal: true

require_relative "../lib/changelog/output_processor"

module Homebrew
  module Changelog
    module OutputProcessorTest
      module_function

      def assert(condition, message)
        raise message unless condition
      end

      def fetched(content)
        source = Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        Types::FetchedContent.new(
          source:,
          path: "CHANGELOG.md",
          locator: "HEAD:CHANGELOG.md",
          content:,
        )
      end

      def test_passthrough_for_text_content
        input = "# Changelog\n\nПривет\n"
        output = OutputProcessor.new(fetched_content: fetched(input)).process

        assert(output == input, "text content should pass through unchanged")
      end

      def test_returns_nil_for_null_byte_content
        input = "abc\x00def".b
        output = OutputProcessor.new(fetched_content: fetched(input)).process

        assert(output.nil?, "content with null byte should be treated as binary")
      end

      def test_returns_nil_for_control_heavy_content
        input = "\x01\x02\x03\x04\x05abc".b
        output = OutputProcessor.new(fetched_content: fetched(input)).process

        assert(output.nil?, "control-heavy content should be treated as binary")
      end

      def test_passes_non_latin_utf8_text
        input = "# 更新履歴\n\nمرحبا\n"
        output = OutputProcessor.new(fetched_content: fetched(input)).process

        assert(output == input, "valid non-latin UTF-8 text should pass through")
      end

      def run_all
        test_passthrough_for_text_content
        test_returns_nil_for_null_byte_content
        test_returns_nil_for_control_heavy_content
        test_passes_non_latin_utf8_text
      end
    end
  end
end

Homebrew::Changelog::OutputProcessorTest.run_all
puts "output_processor_test.rb: OK"
