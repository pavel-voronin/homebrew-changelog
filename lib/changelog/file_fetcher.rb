# typed: strict
# frozen_string_literal: true

require_relative "types"
require_relative "errors"
require_relative "repo_checkout"

module Homebrew
  module Changelog
    class FileFetcher
      extend T::Sig

      sig { params(file_match: Types::FileMatch).void }
      def initialize(file_match:)
        @file_match = file_match
      end

      sig { returns(T.nilable(Types::FetchedContent)) }
      def fetch
        case file_match.source.kind
        when :git
          fetch_git
        else
          nil
        end
      end

      private

      sig { returns(Types::FileMatch) }
      attr_reader :file_match

      sig { returns(T.nilable(Types::FetchedContent)) }
      def fetch_git
        existing_bare_repo = T.let(existing_bare_repo_path, T.nilable(String))
        if existing_bare_repo.is_a?(String) && !existing_bare_repo.empty?
          fetched = fetch_from_bare_repo(existing_bare_repo)
          return fetched if fetched
        end

        checkout = RepoCheckout.create(prefix: "brew-changelog-fetch-")

        begin
          Utils.safe_popen_read(
            "git", "clone", "--bare", "--filter=blob:none", "--depth=1", file_match.source.location, checkout.bare_repo,
            err: :out,
          )

          fetch_from_bare_repo(checkout.bare_repo)
        ensure
          checkout.cleanup
        end
      rescue ErrorDuringExecution => e
        raise Errors::ExecutionError, "Failed to fetch changelog from #{file_match.source.location}: #{e.message}"
      end

      sig { returns(T.nilable(String)) }
      def existing_bare_repo_path
        checkout = T.let(file_match.meta[:checkout], T.untyped)
        if checkout.is_a?(RepoCheckout)
          return checkout.bare_repo
        end

        bare_repo = T.let(file_match.meta[:bare_repo], T.untyped)
        return bare_repo if bare_repo.is_a?(String) && !bare_repo.empty?

        nil
      end

      sig { params(bare_repo: String).returns(T.nilable(Types::FetchedContent)) }
      def fetch_from_bare_repo(bare_repo)
        return nil unless Dir.exist?(bare_repo)
        return nil unless git_path_exists?(bare_repo)

        content = Utils.safe_popen_read(
          "git", "-C", bare_repo, "show", file_match.locator,
          err: :out,
        )

        Types::FetchedContent.new(
          source: file_match.source,
          path: file_match.path,
          locator: file_match.locator,
          content: content,
          meta: { fetcher: :git_show },
        )
      end

      sig { params(bare_repo: String).returns(T::Boolean) }
      def git_path_exists?(bare_repo)
        tree_output = Utils.safe_popen_read(
          "git", "-C", bare_repo, "ls-tree", "--name-only", "HEAD", "--", file_match.path,
          err: :out,
        )

        tree_output.lines.any? { |line| line.chomp == file_match.path }
      end
    end
  end
end
