# typed: false
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../lib/changelog/file_fetcher"

module Homebrew
  module Changelog
    module FileFetcherTest
      module_function

      def assert(condition, message)
        raise message unless condition
      end

      def with_git_repo(files)
        Dir.mktmpdir("fetcher-fixture-") do |dir|
          Utils.safe_popen_read("git", "init", dir, err: :out)
          Utils.safe_popen_read("git", "-C", dir, "config", "user.email", "test@example.com", err: :out)
          Utils.safe_popen_read("git", "-C", dir, "config", "user.name", "Test User", err: :out)

          files.each do |path, content|
            full_path = File.join(dir, path)
            FileUtils.mkdir_p(File.dirname(full_path))
            File.write(full_path, content)
          end

          Utils.safe_popen_read("git", "-C", dir, "add", ".", err: :out)
          Utils.safe_popen_read("git", "-C", dir, "commit", "-m", "fixture", err: :out)

          yield(dir)
        end
      end

      def test_fetches_content_from_git_locator
        with_git_repo("CHANGELOG.md" => "hello changelog\n") do |repo|
          source = Types::SourceRef.new(kind: :git, location: repo)
          match = Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "HEAD:CHANGELOG.md")

          fetched = FileFetcher.new(file_match: match).fetch

          assert(!fetched.nil?, "expected fetched content")
          assert(fetched.path == "CHANGELOG.md", "expected fetched path")
          assert(fetched.locator == "HEAD:CHANGELOG.md", "expected fetched locator")
          assert(fetched.content.include?("hello changelog"), "expected fetched body")
        end
      end

      def test_returns_nil_for_non_git_source
        source = Types::SourceRef.new(kind: :web, location: "https://example.com/changelog")
        match = Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "https://example.com/CHANGELOG.md")

        fetched = FileFetcher.new(file_match: match).fetch

        assert(fetched.nil?, "non-git fetch should return nil")
      end

      def test_returns_nil_when_git_locator_is_missing
        with_git_repo("README.md" => "readme") do |repo|
          source = Types::SourceRef.new(kind: :git, location: repo)
          match = Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "HEAD:CHANGELOG.md")

          fetched = FileFetcher.new(file_match: match).fetch

          assert(fetched.nil?, "missing git object should return nil")
        end
      end

      def test_reuses_existing_bare_repo_from_scanner_metadata
        with_git_repo("CHANGELOG.md" => "hello once\n") do |repo|
          checkout = RepoCheckout.create(prefix: "fetcher-reuse-")
          begin
            Utils.safe_popen_read(
              "git", "clone", "--bare", "--filter=blob:none", "--depth=1", repo, checkout.bare_repo,
              err: :out,
            )

            source = Types::SourceRef.new(kind: :git, location: "/tmp/does-not-exist.git")
            match = Types::FileMatch.new(
              source:,
              path: "CHANGELOG.md",
              locator: "HEAD:CHANGELOG.md",
              meta: { checkout: checkout },
            )

            fetched = FileFetcher.new(file_match: match).fetch

            assert(!fetched.nil?, "expected fetched content from pre-cloned bare repo")
            assert(fetched.content.include?("hello once"), "expected fetched content from bare repo")
          ensure
            checkout.cleanup
          end
        end
      end

      def test_falls_back_to_fresh_clone_when_scanner_bare_repo_is_missing
        with_git_repo("CHANGELOG.md" => "fallback content\n") do |repo|
          source = Types::SourceRef.new(kind: :git, location: repo)
          match = Types::FileMatch.new(
            source:,
            path: "CHANGELOG.md",
            locator: "HEAD:CHANGELOG.md",
            meta: { bare_repo: "/tmp/non-existent-bare-repo" },
          )

          fetched = FileFetcher.new(file_match: match).fetch

          assert(!fetched.nil?, "expected fallback clone to fetch content")
          assert(fetched.content.include?("fallback content"), "expected content from fallback clone")
        end
      end

      def run_all
        test_fetches_content_from_git_locator
        test_returns_nil_for_non_git_source
        test_returns_nil_when_git_locator_is_missing
        test_reuses_existing_bare_repo_from_scanner_metadata
        test_falls_back_to_fresh_clone_when_scanner_bare_repo_is_missing
      end
    end
  end
end

Homebrew::Changelog::FileFetcherTest.run_all
puts "file_fetcher_test.rb: OK"
