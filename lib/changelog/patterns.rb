# typed: strict
# frozen_string_literal: true

module Homebrew
  module Changelog
    module Patterns
      DEFAULT = [
        "CHANGELOG*",
        "CHANGES*",
        "NEWS*",
        "HISTORY",
        "HISTORY.md",
        "HISTORY.txt",
        "RELEASES*",
        "*WHATSNEW*",
      ].freeze
    end
  end
end
