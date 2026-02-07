# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "uri"
require_relative "../lib/changelog/patterns"
require_relative "../lib/changelog/errors"
require_relative "../lib/changelog/repo_resolver"
require_relative "../lib/changelog/file_scanner"
require_relative "../lib/changelog/file_fetcher"
require_relative "../lib/changelog/output_processor"

module Homebrew
  module Cmd
    class Changelog < AbstractCommand
      cmd_args do
        description <<~EOS
          Display changelog for a formula or cask.
        EOS
        switch "--formula",
               description: "Treat the named argument as a formula."
        switch "--cask",
               description: "Treat the named argument as a cask."
        comma_array "--pattern",
                    description: "Comma-separated wildcard patterns to match changelog filenames."
        switch "-o", "--open",
               description: "Open found changelog in browser and print its URL."
        switch "--print-url",
               description: "Print found changelog URL without opening browser."
        switch "--allow-missing",
               description: "Exit successfully if no changelog is found."

        conflicts "--formula", "--cask"
        conflicts "--open", "--print-url"

        named_args [:formula, :cask], number: 1
      end

      sig { override.void }
      def run
        file_match = T.let(nil, T.nilable(Homebrew::Changelog::Types::FileMatch))

        print_debug_initial_context

        target = resolve_target
        print_debug_stage("resolve_target", "target=#{display_name(target)} type=#{target_type(target)}")

        patterns = selected_patterns
        print_debug_stage("select_patterns", "count=#{patterns.length} values=#{patterns.join(", ")}")

        print_verbose_step("Resolving repository URL candidates...")
        source_refs = resolve_source_refs(target)
        print_debug_stage("resolve_sources", source_refs_text(source_refs))

        if source_refs.present?
          print_verbose_step("Using candidate source: #{source_refs.first.location}")
        else
          print_verbose_step("No repository candidates resolved from metadata")
        end
        print_verbose_step("Scanning repository tree for changelog files...")
        file_match = scan_for_changelog(source_refs, patterns)
        print_debug_stage("scan_files", file_match.nil? ? "(none)" : "#{file_match.path} via #{file_match.locator}")
        if file_match
          print_verbose_step("Selected changelog file: #{file_match.path}")
        else
          print_verbose_step("No changelog files matched current patterns")
          handle_missing("Changelog not found for #{display_name(target)}")
          return
        end

        if args.open?
          print_verbose_step("Opening changelog in browser...")
          browser_url = build_browser_url(file_match)
          if browser_url.nil?
            print_debug_stage("render_output_open", "(no browser URL)")
            handle_missing("Changelog URL not available for #{display_name(target)}")
            return
          end

          puts browser_url
          open_browser_url(browser_url)
          print_debug_stage("render_output_open", browser_url)
          return
        end

        if args.print_url?
          print_verbose_step("Rendering changelog URL...")
          browser_url = build_browser_url(file_match)
          if browser_url.nil?
            print_debug_stage("render_output_url", "(no browser URL)")
            handle_missing("Changelog URL not available for #{display_name(target)}")
            return
          end

          puts browser_url
          print_debug_stage("render_output_url", browser_url)
          return
        end

        print_verbose_step("Fetching changelog content...")
        fetched_content = fetch_changelog(file_match)
        fetch_result = fetched_content.nil? ? "(none)" : "#{fetched_content.path} bytes=#{fetched_content.content.bytesize}"
        print_debug_stage("fetch_file", fetch_result)
        if fetched_content.nil?
          print_verbose_step("Could not fetch selected changelog file")
          handle_missing("Changelog not found for #{display_name(target)}")
          return
        end

        print_verbose_step("Processing changelog content...")
        processed_output = process_output(fetched_content)
        process_result = processed_output.nil? ? "(none)" : "bytes=#{processed_output.bytesize}"
        print_debug_stage("process_output", process_result)
        if processed_output.nil?
          print_verbose_step("Selected changelog content looks binary and was skipped")
          handle_missing("Changelog appears to be binary for #{display_name(target)}")
          return
        end

        puts processed_output
      rescue Homebrew::Changelog::Errors::ExecutionError => e
        handle_error(e)
      ensure
        cleanup_scanner_checkout(file_match)
      end

      private

      sig { returns(T.untyped) }
      def resolve_target
        if args.formula?
          return args.named.to_formulae.fetch(0)
        end

        if args.cask?
          return args.named.to_casks.fetch(0)
        end

        args.named.to_formulae_and_casks.fetch(0)
      end

      sig { returns(T::Array[String]) }
      def selected_patterns
        user_patterns = args.pattern
        return Homebrew::Changelog::Patterns::DEFAULT if user_patterns.blank?

        selected = user_patterns.compact.map(&:strip).reject(&:empty?)
        return Homebrew::Changelog::Patterns::DEFAULT if selected.empty?

        selected
      end

      sig { void }
      def print_debug_initial_context
        return unless args.debug?

        user_patterns = args.pattern
        odebug(
          "brew-changelog debug",
          "formula flag: #{args.formula?}",
          "cask flag: #{args.cask?}",
          "debug flag: #{args.debug?}",
          "open flag: #{args.open?}",
          "print-url flag: #{args.print_url?}",
          "allow-missing flag: #{args.allow_missing?}",
          "quiet flag: #{args.quiet?}",
          "verbose flag: #{args.verbose?}",
          "named args: #{args.named.join(", ")}",
          "pattern flag values: #{user_patterns.blank? ? "(none)" : user_patterns.join(", ")}",
          always_display: true,
        )
      end

      sig { params(target: T.untyped).returns(T::Array[Homebrew::Changelog::Types::SourceRef]) }
      def resolve_source_refs(target)
        Homebrew::Changelog::RepoResolver.new(target).source_refs
      end

      sig {
        params(
          source_refs: T::Array[Homebrew::Changelog::Types::SourceRef],
          patterns: T::Array[String],
        ).returns(T.nilable(Homebrew::Changelog::Types::FileMatch))
      }
      def scan_for_changelog(source_refs, patterns)
        Homebrew::Changelog::FileScanner.new(source_refs:, patterns:).first_match
      end

      sig { params(file_match: Homebrew::Changelog::Types::FileMatch).returns(T.nilable(Homebrew::Changelog::Types::FetchedContent)) }
      def fetch_changelog(file_match)
        Homebrew::Changelog::FileFetcher.new(file_match:).fetch
      end

      sig { params(fetched_content: Homebrew::Changelog::Types::FetchedContent).returns(T.nilable(String)) }
      def process_output(fetched_content)
        Homebrew::Changelog::OutputProcessor.new(fetched_content:).process
      end

      sig { params(file_match: Homebrew::Changelog::Types::FileMatch).returns(T.nilable(String)) }
      def build_browser_url(file_match)
        repo = file_match.source.location
        path = encode_url_path(file_match.path)
        uri = URI.parse(repo)

        case uri.host
        when "github.com"
          base = repo.sub(/\.git\z/, "")
          "#{base}/blob/HEAD/#{path}"
        when "gitlab.com"
          base = repo.sub(/\.git\z/, "")
          "#{base}/-/blob/HEAD/#{path}"
        when "bitbucket.org"
          base = repo.sub(/\.git\z/, "")
          "#{base}/src/HEAD/#{path}"
        else
          nil
        end
      rescue URI::InvalidURIError
        nil
      end

      sig { params(path: String).returns(String) }
      def encode_url_path(path)
        path.split("/").map { |part| URI.encode_www_form_component(part).gsub("+", "%20") }.join("/")
      end

      sig { params(url: String).void }
      def open_browser_url(url)
        exec_browser(url)
      rescue StandardError => e
        opoo "Could not open browser automatically: #{e.message}"
      end

      sig { params(message: String).void }
      def handle_missing(message)
        if args.allow_missing?
          print_debug_stage("missing", "allowed #{message}")
          return
        end

        print_debug_stage("missing", "error #{message}")
        puts message
        Homebrew.failed = true
      end

      sig { params(error: Homebrew::Changelog::Errors::ExecutionError).returns(T.noreturn) }
      def handle_error(error)
        print_debug_stage("error", error.message)
        $stderr.puts(user_facing_error_message(error.message))
        raise SystemExit.new(2)
      end

      sig { params(message: String).returns(String) }
      def user_facing_error_message(message)
        execution_marker = ": Failure while executing;"
        if message.include?(execution_marker)
          return "#{message.split(execution_marker, 2).first}."
        end

        message.lines.first.to_s.chomp
      end

      sig { params(source_refs: T::Array[Homebrew::Changelog::Types::SourceRef]).returns(String) }
      def source_refs_text(source_refs)
        return "(none)" if source_refs.blank?

        source_refs.map { |ref| "#{ref.kind}:#{ref.location}" }.join(", ")
      end

      sig { params(file_match: T.nilable(Homebrew::Changelog::Types::FileMatch)).void }
      def cleanup_scanner_checkout(file_match)
        return if file_match.nil?

        checkout = T.let(file_match.meta[:checkout], T.untyped)
        return unless checkout.respond_to?(:cleanup)

        checkout.cleanup
      rescue StandardError => e
        odebug("brew-changelog debug", "cleanup scanner checkout failed: #{e.message}") if args.debug?
      end

      sig { params(stage: String, details: T.nilable(String)).void }
      def print_debug_stage(stage, details = nil)
        return unless args.debug?

        message = "[stage] #{stage}"
        message = "#{message} #{details}" if details.present?
        odebug("brew-changelog debug", message, always_display: true)
      end

      sig { params(message: String).void }
      def print_verbose_step(message)
        return unless args.verbose?
        return if args.quiet?

        puts "[verbose] #{message}"
      end

      sig { params(target: T.untyped).returns(String) }
      def display_name(target)
        target.full_name
      end

      sig { params(target: T.untyped).returns(String) }
      def target_type(target)
        target.is_a?(Formula) ? "formula" : "cask"
      end
    end
  end
end
