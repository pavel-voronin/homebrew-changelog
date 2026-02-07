# typed: strict
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Homebrew
  module Changelog
    class RepoCheckout
      extend T::Sig

      sig { params(prefix: String).returns(RepoCheckout) }
      def self.create(prefix:)
        temp_dir = Dir.mktmpdir(prefix)
        bare_repo = File.join(temp_dir, "repo.git")
        new(temp_dir:, bare_repo:)
      end

      sig { params(temp_dir: String, bare_repo: String).void }
      def initialize(temp_dir:, bare_repo:)
        @temp_dir = temp_dir
        @bare_repo = bare_repo
      end

      sig { returns(String) }
      attr_reader :temp_dir

      sig { returns(String) }
      attr_reader :bare_repo

      sig { void }
      def cleanup
        return unless Dir.exist?(temp_dir)

        FileUtils.remove_entry_secure(temp_dir)
      end
    end
  end
end
