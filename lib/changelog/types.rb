# typed: strict
# frozen_string_literal: true

module Homebrew
  module Changelog
    module Types
      class SourceRef < T::Struct
        const :kind, Symbol
        const :location, String
        const :meta, T::Hash[Symbol, T.untyped], default: {}
      end

      class FileMatch < T::Struct
        const :source, SourceRef
        const :path, String
        const :locator, String
        const :meta, T::Hash[Symbol, T.untyped], default: {}
      end

      class FetchedContent < T::Struct
        const :source, SourceRef
        const :path, String
        const :locator, String
        const :content, String
        const :meta, T::Hash[Symbol, T.untyped], default: {}
      end
    end
  end
end
