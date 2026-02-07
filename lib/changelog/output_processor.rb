# typed: strict
# frozen_string_literal: true

require_relative "types"

module Homebrew
  module Changelog
    class OutputProcessor
      extend T::Sig

      sig { params(fetched_content: Types::FetchedContent).void }
      def initialize(fetched_content:)
        @fetched_content = fetched_content
      end

      sig { returns(T.nilable(String)) }
      def process
        content = fetched_content.content
        return nil if binary_content?(content)

        content
      end

      private

      sig { returns(Types::FetchedContent) }
      attr_reader :fetched_content

      sig { params(content: String).returns(T::Boolean) }
      def binary_content?(content)
        bytes = content.b
        return true if bytes.include?("\x00")
        return false if bytes.empty?

        utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
        if utf8.valid_encoding?
          total_count = 0
          control_count = 0
          utf8.each_codepoint do |cp|
            total_count += 1
            control_count += 1 if cp < 32 && ![9, 10, 13].include?(cp)
          end

          return false if total_count.zero?

          return (control_count.to_f / total_count) > 0.30
        end

        sample = bytes.bytes.first(4096)
        return false if sample.empty?

        control_count = sample.count { |b| b < 32 && ![9, 10, 13].include?(b) }
        (control_count.to_f / sample.length) > 0.30
      end
    end
  end
end
