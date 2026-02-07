# typed: strict
# frozen_string_literal: true

require_relative "types"
require_relative "errors"
require_relative "repo_checkout"

module Homebrew
  module Changelog
    class FileScanner
      extend T::Sig

      sig { params(source_refs: T::Array[Types::SourceRef], patterns: T::Array[String]).void }
      def initialize(source_refs:, patterns:)
        @source_refs = source_refs
        @patterns = patterns
      end

      sig { returns(T.nilable(Types::FileMatch)) }
      def first_match
        last_error = T.let(nil, T.nilable(Errors::ExecutionError))
        successful_scan = T.let(false, T::Boolean)

        source_refs.each do |source_ref|
          next unless source_ref.kind == :git

          begin
            match = scan_git_source(source_ref)
            successful_scan = true
          rescue Errors::ExecutionError => e
            last_error = e
            next
          end
          return match if match
        end

        raise last_error if !successful_scan && !last_error.nil?

        nil
      end

      private

      sig { returns(T::Array[Types::SourceRef]) }
      attr_reader :source_refs

      sig { returns(T::Array[String]) }
      attr_reader :patterns

      sig { params(source_ref: Types::SourceRef).returns(T.nilable(Types::FileMatch)) }
      def scan_git_source(source_ref)
        keep_checkout = T.let(false, T::Boolean)
        checkout = T.let(nil, T.nilable(RepoCheckout))
        checkout = RepoCheckout.create(prefix: "brew-changelog-")

        Utils.safe_popen_read(
          "git", "clone", "--bare", "--filter=blob:none", "--depth=1", source_ref.location, checkout.bare_repo,
          err: :out,
        )

        tree_output = Utils.safe_popen_read(
          "git", "-C", checkout.bare_repo, "ls-tree", "-r", "--name-only", "HEAD",
          err: :out,
        )

        files = tree_output.lines.map(&:strip).reject(&:empty?).sort
        matched_path = match_path(files)
        return nil if matched_path.nil?

        keep_checkout = true
        Types::FileMatch.new(
          source: source_ref,
          path: matched_path,
          locator: "HEAD:#{matched_path}",
          meta: {
            scanner: :git_ls_tree,
            checkout: checkout,
          },
        )
      rescue ErrorDuringExecution => e
        raise Errors::ExecutionError, "Failed to scan repository #{source_ref.location}: #{e.message}"
      ensure
        checkout&.cleanup unless keep_checkout
      end

      sig { params(files: T::Array[String]).returns(T.nilable(String)) }
      def match_path(files)
        patterns.each do |pattern|
          found = files.find { |path| path_matches?(path, pattern) }
          return found if found
        end

        nil
      end

      sig { params(path: String, pattern: String).returns(T::Boolean) }
      def path_matches?(path, pattern)
        flags = File::FNM_PATHNAME | File::FNM_CASEFOLD
        if pattern.include?("/")
          File.fnmatch?(pattern, path, flags)
        else
          File.fnmatch?(pattern, File.basename(path), flags)
        end
      end
    end
  end
end
