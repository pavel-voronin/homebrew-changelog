# typed: false
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../lib/changelog/file_scanner"

module Homebrew
  module Changelog
    module FileScannerTest
      module_function

      def assert(condition, message)
        raise message unless condition
      end

      def with_git_repo(files)
        Dir.mktmpdir("scanner-fixture-") do |dir|
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

      def cleanup_match(match)
        return if match.nil?

        checkout = match.meta[:checkout]
        return unless checkout.respond_to?(:cleanup)

        checkout.cleanup
      end

      def test_finds_first_pattern_match_in_priority_order
        with_git_repo(
          "NEWS.md" => "news",
          "CHANGELOG.md" => "changelog",
        ) do |repo|
          refs = [Types::SourceRef.new(kind: :git, location: repo)]
          scanner = FileScanner.new(source_refs: refs, patterns: ["CHANGELOG.md", "NEWS.md"])

          match = scanner.first_match
          assert(!match.nil?, "expected file match")
          begin
            assert(match.path == "CHANGELOG.md", "expected first pattern priority match")
            assert(match.locator == "HEAD:CHANGELOG.md", "expected git locator")
            assert(match.meta[:scanner] == :git_ls_tree, "expected scanner metadata")
            assert(match.meta[:checkout].respond_to?(:bare_repo), "expected reusable checkout metadata")
          ensure
            cleanup_match(match)
          end
        end
      end

      def test_matches_basename_when_pattern_has_no_slash
        with_git_repo(
          "docs/CHANGELOG.md" => "nested",
        ) do |repo|
          refs = [Types::SourceRef.new(kind: :git, location: repo)]
          scanner = FileScanner.new(source_refs: refs, patterns: ["CHANGELOG.md"])

          match = scanner.first_match
          assert(!match.nil?, "expected nested changelog match")
          begin
            assert(match.path == "docs/CHANGELOG.md", "expected basename matching")
          ensure
            cleanup_match(match)
          end
        end
      end

      def test_matches_full_path_when_pattern_has_slash
        with_git_repo(
          "docs/CHANGELOG.md" => "nested",
          "CHANGELOG.md" => "root",
        ) do |repo|
          refs = [Types::SourceRef.new(kind: :git, location: repo)]
          scanner = FileScanner.new(source_refs: refs, patterns: ["docs/CHANGELOG*"])

          match = scanner.first_match
          assert(!match.nil?, "expected path-specific match")
          begin
            assert(match.path == "docs/CHANGELOG.md", "expected path pattern matching")
          ensure
            cleanup_match(match)
          end
        end
      end

      def test_matching_is_case_insensitive
        with_git_repo(
          "Changelog.MD" => "content",
        ) do |repo|
          refs = [Types::SourceRef.new(kind: :git, location: repo)]
          scanner = FileScanner.new(source_refs: refs, patterns: ["CHANGELOG*"])

          match = scanner.first_match
          assert(!match.nil?, "expected case-insensitive match")
          begin
            assert(match.path == "Changelog.MD", "expected case-insensitive pattern matching")
          ensure
            cleanup_match(match)
          end
        end
      end

      def test_glob_pattern_matches_whatsnew_variants
        with_git_repo(
          "docs/whatsnew-2.0.txt" => "notes",
        ) do |repo|
          refs = [Types::SourceRef.new(kind: :git, location: repo)]
          scanner = FileScanner.new(source_refs: refs, patterns: ["*WHATSNEW*"])

          match = scanner.first_match
          assert(!match.nil?, "expected glob whatsnew match")
          begin
            assert(match.path == "docs/whatsnew-2.0.txt", "expected whatsnew glob matching")
          ensure
            cleanup_match(match)
          end
        end
      end

      def test_skips_non_git_sources
        refs = [Types::SourceRef.new(kind: :web, location: "https://example.com/changelog")]
        scanner = FileScanner.new(source_refs: refs, patterns: ["CHANGELOG.md"])

        match = scanner.first_match
        assert(match.nil?, "non-git sources should be skipped")
      end

      def test_continues_when_first_git_source_fails
        with_git_repo(
          "CHANGELOG.md" => "changelog",
        ) do |repo|
          refs = [
            Types::SourceRef.new(kind: :git, location: "https://example.invalid/nope.git"),
            Types::SourceRef.new(kind: :git, location: repo),
          ]
          scanner = FileScanner.new(source_refs: refs, patterns: ["CHANGELOG.md"])

          match = scanner.first_match
          assert(!match.nil?, "expected scanner to continue to next source")
          begin
            assert(match.path == "CHANGELOG.md", "expected fallback source match")
          ensure
            cleanup_match(match)
          end
        end
      end

      def run_all
        test_finds_first_pattern_match_in_priority_order
        test_matches_basename_when_pattern_has_no_slash
        test_matches_full_path_when_pattern_has_slash
        test_matching_is_case_insensitive
        test_glob_pattern_matches_whatsnew_variants
        test_skips_non_git_sources
        test_continues_when_first_git_source_fails
      end
    end
  end
end

Homebrew::Changelog::FileScannerTest.run_all
puts "file_scanner_test.rb: OK"
