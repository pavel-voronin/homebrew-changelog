# typed: false
# frozen_string_literal: true

require_relative "../cmd/changelog"
require "stringio"

module Homebrew
  module Cmd
    module ChangelogCmdTest
      FakeCask = Struct.new(:full_name)
      FakeFormula = Struct.new(:full_name)

      module_function

      def assert(condition, message)
        raise message unless condition
      end

      def capture_stdout
        old_stdout = $stdout
        buffer = StringIO.new
        $stdout = buffer
        yield
        buffer.string
      ensure
        $stdout = old_stdout
      end

      def capture_io
        old_stdout = $stdout
        old_stderr = $stderr
        out = StringIO.new
        err = StringIO.new
        $stdout = out
        $stderr = err
        yield
        [out.string, err.string]
      ensure
        $stdout = old_stdout
        $stderr = old_stderr
      end

      def test_parses_pattern_flag_as_array
        cmd = Changelog.new(["--print-url", "--allow-missing", "--pattern=CHANGELOG.md,NEWS.md", "git"])

        assert(cmd.args.pattern == %w[CHANGELOG.md NEWS.md], "pattern flag parsing failed")
        assert(cmd.args.print_url?, "print-url flag parsing failed")
        assert(cmd.args.allow_missing?, "allow-missing flag parsing failed")
        assert(cmd.args.named == ["git"], "named arg parsing failed")
      end

      def test_open_and_print_url_flags_conflict
        begin
          Changelog.new(["--open", "--print-url", "git"])
          raise "expected mutually exclusive flag conflict"
        rescue Homebrew::CLI::OptionConflictError => e
          assert(e.message.include?("--open"), "expected open flag in conflict message")
          assert(e.message.include?("--print-url"), "expected print-url flag in conflict message")
        end
      end

      def test_run_uses_default_patterns_without_pattern_flag
        cmd = Changelog.new(["--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        match = Homebrew::Changelog::Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "HEAD:CHANGELOG.md")
        received_patterns = nil
        fetched = Homebrew::Changelog::Types::FetchedContent.new(
          source:,
          path: "CHANGELOG.md",
          locator: "HEAD:CHANGELOG.md",
          content: "default changelog body",
        )
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, patterns|
          received_patterns = patterns
          match
        end
        cmd.define_singleton_method(:fetch_changelog) { |_match| fetched }

        out = capture_stdout { cmd.run }

        assert(out.include?("default changelog body"), "expected fetched changelog output")
        assert(received_patterns == Homebrew::Changelog::Patterns::DEFAULT, "expected default pattern set")
      end

      def test_run_uses_custom_patterns
        cmd = Changelog.new(["--formula", "--pattern=docs/CHANGELOG*,NEWS*", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        match = Homebrew::Changelog::Types::FileMatch.new(source:, path: "docs/CHANGELOG.md", locator: "HEAD:docs/CHANGELOG.md")
        received_patterns = nil
        fetched = Homebrew::Changelog::Types::FetchedContent.new(
          source:,
          path: "docs/CHANGELOG.md",
          locator: "HEAD:docs/CHANGELOG.md",
          content: "custom changelog body",
        )
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, patterns|
          received_patterns = patterns
          match
        end
        cmd.define_singleton_method(:fetch_changelog) { |_match| fetched }

        out = capture_stdout { cmd.run }

        assert(out.include?("custom changelog body"), "expected custom fetched changelog output")
        assert(received_patterns == ["docs/CHANGELOG*", "NEWS*"], "expected custom patterns in scanner")
      end

      def test_run_ignores_nil_pattern_entries_from_parser
        cmd = Changelog.new(["--formula", "--pattern=CHANGELOG.md,,NEWS.md", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        match = Homebrew::Changelog::Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "HEAD:CHANGELOG.md")
        received_patterns = nil
        fetched = Homebrew::Changelog::Types::FetchedContent.new(
          source:,
          path: "CHANGELOG.md",
          locator: "HEAD:CHANGELOG.md",
          content: "custom changelog body",
        )
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, patterns|
          received_patterns = patterns
          match
        end
        cmd.define_singleton_method(:fetch_changelog) { |_match| fetched }

        out = capture_stdout { cmd.run }

        assert(out.include?("custom changelog body"), "expected fetched changelog output")
        assert(received_patterns == ["CHANGELOG.md", "NEWS.md"], "expected nil pattern entries to be ignored")
      end

      def test_run_resolves_cask_with_cask_flag
        cmd = Changelog.new(["--cask", "iterm2"])
        target = FakeCask.new("homebrew/cask/iterm2")
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| nil }
        cmd.define_singleton_method(:fetch_changelog) { |_match| raise "fetch should not be called without file match" }

        out = capture_stdout { cmd.run }

        assert(out.include?("Changelog not found for homebrew/cask/iterm2"), "missing not-found output")
      end

      def test_debug_output_prints_parameter_values
        cmd = Changelog.new(["--debug", "--cask", "--pattern=docs/CHANGELOG*,NEWS*", "iterm2"])
        target = FakeCask.new("homebrew/cask/iterm2")
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| nil }
        cmd.define_singleton_method(:fetch_changelog) { |_match| nil }

        _, err = capture_io { cmd.run }

        assert(err.include?("brew-changelog debug"), "missing debug header")
        assert(err.include?("formula flag: false"), "missing formula flag debug value")
        assert(err.include?("cask flag: true"), "missing cask flag debug value")
        assert(err.include?("open flag: false"), "missing open flag debug value")
        assert(err.include?("print-url flag: false"), "missing print-url flag debug value")
        assert(err.include?("named args: iterm2"), "missing named args debug value")
        assert(err.include?("pattern flag values: docs/CHANGELOG*, NEWS*"), "missing pattern debug value")
        assert(err.include?("[stage] resolve_target target=homebrew/cask/iterm2 type=cask"),
               "missing resolve_target stage debug value")
        assert(err.include?("[stage] select_patterns count=2 values=docs/CHANGELOG*, NEWS*"),
               "missing select_patterns stage debug value")
        assert(err.include?("[stage] resolve_sources (none)"), "missing resolve_sources stage debug value")
        assert(err.include?("[stage] scan_files (none)"), "missing scan_files stage debug value")
        assert(err.include?("[stage] missing error Changelog not found for homebrew/cask/iterm2"),
               "missing missing/error stage debug value")
      end

      def test_verbose_output_prints_high_level_steps
        cmd = Changelog.new(["--verbose", "--formula", "--pattern=docs/CHANGELOG*,NEWS*", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        match = Homebrew::Changelog::Types::FileMatch.new(source:, path: "docs/CHANGELOG.md", locator: "HEAD:docs/CHANGELOG.md")
        fetched = Homebrew::Changelog::Types::FetchedContent.new(
          source:,
          path: "docs/CHANGELOG.md",
          locator: "HEAD:docs/CHANGELOG.md",
          content: "content",
        )
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| match }
        cmd.define_singleton_method(:fetch_changelog) { |_match| fetched }

        out = capture_stdout { cmd.run }

        assert(out.include?("[verbose] Resolving repository URL candidates..."), "missing verbose resolver step")
        assert(out.include?("[verbose] Scanning repository tree for changelog files..."), "missing verbose scan step")
        assert(out.include?("[verbose] Selected changelog file: docs/CHANGELOG.md"), "missing verbose selected file step")
        assert(out.include?("[verbose] Fetching changelog content..."), "missing verbose fetch step")
        assert(out.include?("[verbose] Processing changelog content..."), "missing verbose process step")
      end

      def test_binary_output_is_not_rendered
        cmd = Changelog.new(["--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")
        match = Homebrew::Changelog::Types::FileMatch.new(source:, path: "CHANGELOG.md", locator: "HEAD:CHANGELOG.md")
        fetched = Homebrew::Changelog::Types::FetchedContent.new(
          source:,
          path: "CHANGELOG.md",
          locator: "HEAD:CHANGELOG.md",
          content: "text that will be treated as binary by stub",
        )
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| match }
        cmd.define_singleton_method(:fetch_changelog) { |_match| fetched }
        cmd.define_singleton_method(:process_output) { |_fetched| nil }

        out = capture_stdout { cmd.run }

        assert(out.include?("Changelog appears to be binary for git"), "missing binary guard output")
      end

      def test_allow_missing_suppresses_not_found_error_output
        cmd = Changelog.new(["--allow-missing", "--formula", "git"])
        target = FakeFormula.new("git")
        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| nil }

        out = capture_stdout { cmd.run }

        assert(out.strip.empty?, "allow-missing should suppress not-found output")
      end

      def test_open_prints_url_and_attempts_browser_open
        cmd = Changelog.new(["-o", "--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://github.com/foo/bar.git")
        match = Homebrew::Changelog::Types::FileMatch.new(
          source:,
          path: "docs/CHANGELOG.md",
          locator: "HEAD:docs/CHANGELOG.md",
        )
        opened = nil

        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| match }
        cmd.define_singleton_method(:fetch_changelog) { |_match| raise "fetch should not be called in open mode" }
        cmd.define_singleton_method(:process_output) { |_fetched| raise "process should not be called in open mode" }
        cmd.define_singleton_method(:exec_browser) { |url| opened = url }

        out = capture_stdout { cmd.run }

        expected_url = "https://github.com/foo/bar/blob/HEAD/docs/CHANGELOG.md"
        assert(out.include?(expected_url), "expected open URL in output")
        assert(opened == expected_url, "expected browser to be called with open URL")
      end

      def test_print_url_prints_url_without_opening_browser
        cmd = Changelog.new(["--print-url", "--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://github.com/foo/bar.git")
        match = Homebrew::Changelog::Types::FileMatch.new(
          source:,
          path: "docs/CHANGELOG.md",
          locator: "HEAD:docs/CHANGELOG.md",
        )
        opened = false

        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) { |_refs, _patterns| match }
        cmd.define_singleton_method(:fetch_changelog) { |_match| raise "fetch should not be called in print-url mode" }
        cmd.define_singleton_method(:process_output) { |_fetched| raise "process should not be called in print-url mode" }
        cmd.define_singleton_method(:exec_browser) { |_url| opened = true }

        out = capture_stdout { cmd.run }

        expected_url = "https://github.com/foo/bar/blob/HEAD/docs/CHANGELOG.md"
        assert(out.include?(expected_url), "expected URL in output")
        assert(opened == false, "browser should not be called in print-url mode")
      end

      def test_execution_error_exits_with_code_2
        cmd = Changelog.new(["--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")

        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, _patterns|
          raise Homebrew::Changelog::Errors::ExecutionError, "scan failed"
        end

        begin
          capture_io { cmd.run }
          raise "expected SystemExit with code 2"
        rescue SystemExit => e
          assert(e.status == 2, "expected exit code 2 for execution error")
        end
      end

      def test_execution_error_hides_raw_command_output_without_debug
        cmd = Changelog.new(["--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")

        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, _patterns|
          raise Homebrew::Changelog::Errors::ExecutionError,
                "Failed to scan repository https://example.com/repo.git: " \
                "Failure while executing; `git clone ...` exited with 128. Here's the output:\n" \
                "fatal: unable to access 'https://example.com/repo.git/': Could not resolve host: example.com\n"
        end

        status = nil
        _, err = capture_io do
          begin
            cmd.run
          rescue SystemExit => e
            status = e.status
          end
        end
        assert(status == 2, "expected exit code 2 for execution error")
        assert(err.include?("Failed to scan repository https://example.com/repo.git."),
               "expected concise execution error")
        assert(!err.include?("Failure while executing;"), "should not include raw command execution detail")
        assert(!err.include?("Could not resolve host"), "should not include raw git stderr")
      end

      def test_execution_error_prints_debug_details_with_debug_flag
        cmd = Changelog.new(["--debug", "--formula", "git"])
        target = FakeFormula.new("git")
        source = Homebrew::Changelog::Types::SourceRef.new(kind: :git, location: "https://example.com/repo.git")

        cmd.define_singleton_method(:resolve_target) { target }
        cmd.define_singleton_method(:resolve_source_refs) { |_target| [source] }
        cmd.define_singleton_method(:scan_for_changelog) do |_refs, _patterns|
          raise Homebrew::Changelog::Errors::ExecutionError,
                "Failed to scan repository https://example.com/repo.git: " \
                "Failure while executing; `git clone ...` exited with 128."
        end

        _, err = capture_io do
          begin
            cmd.run
          rescue SystemExit
            nil
          end
        end
        assert(err.include?("Failed to scan repository https://example.com/repo.git."),
               "expected concise execution error for user")
        assert(err.include?("[stage] error Failed to scan repository https://example.com/repo.git: " \
                             "Failure while executing; `git clone ...` exited with 128."),
               "expected full execution details in debug output")
      end

      def run_all
        test_parses_pattern_flag_as_array
        test_open_and_print_url_flags_conflict
        test_run_uses_default_patterns_without_pattern_flag
        test_run_uses_custom_patterns
        test_run_ignores_nil_pattern_entries_from_parser
        test_run_resolves_cask_with_cask_flag
        test_debug_output_prints_parameter_values
        test_verbose_output_prints_high_level_steps
        test_binary_output_is_not_rendered
        test_allow_missing_suppresses_not_found_error_output
        test_open_prints_url_and_attempts_browser_open
        test_print_url_prints_url_without_opening_browser
        test_execution_error_exits_with_code_2
        test_execution_error_hides_raw_command_output_without_debug
        test_execution_error_prints_debug_details_with_debug_flag
      end
    end
  end
end

Homebrew::Cmd::ChangelogCmdTest.run_all
puts "changelog_cmd_test.rb: OK"
