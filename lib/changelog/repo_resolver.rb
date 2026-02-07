# typed: strict
# frozen_string_literal: true

require "uri"
require_relative "types"

module Homebrew
  module Changelog
    class RepoResolver
      extend T::Sig
      GITLAB_DASH_ROUTE_MARKERS = T.let(
        %w[
          archive
          blob
          raw
          tree
          commit
          commits
          issues
          merge_requests
          pipelines
          releases
          uploads
          tags
          wikis
          snippets
          files
          jobs
        ].freeze,
        T::Array[String],
      )
      GITLAB_LEGACY_ROUTE_MARKERS = T.let(
        %w[
          raw
          blob
          tree
        ].freeze,
        T::Array[String],
      )

      sig { params(target: T.untyped).void }
      def initialize(target)
        @target = target
      end

      sig { returns(T::Array[Types::SourceRef]) }
      def source_refs
        refs = source_urls.filter_map do |url|
          normalized_url = normalize_repo_url(url)
          next if normalized_url.nil?

          Types::SourceRef.new(
            kind: :git,
            location: normalized_url,
            meta: { resolver: :repo_resolver },
          )
        end
        refs.uniq { |ref| [ref.kind, ref.location] }
      end

      sig { returns(T::Array[String]) }
      def candidate_urls
        source_refs.map(&:location)
      end

      private

      sig { returns(T.untyped) }
      attr_reader :target

      sig { returns(T::Array[String]) }
      def source_urls
        urls = []

        if formula_target?
          urls << target.head&.url
          urls << target.homepage
          urls << target.stable&.url
        else
          urls << target.homepage if target.respond_to?(:homepage)
          urls << target.url.to_s if target.respond_to?(:url)
        end

        urls.compact.map(&:to_s)
      end

      sig { returns(T::Boolean) }
      def formula_target?
        return true if defined?(Formula) && target.is_a?(Formula)

        target.respond_to?(:head) && target.respond_to?(:stable)
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def normalize_repo_url(url)
        return nil if url.empty?

        github_repo_url(url) ||
          gitlab_repo_url(url) ||
          bitbucket_repo_url(url)
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def github_repo_url(url)
        path = host_path(url, "github.com")
        return nil unless path

        owner, repo = path.first(2)
        return nil if owner.nil? || repo.nil?

        "https://github.com/#{owner}/#{repo.delete_suffix(".git")}.git"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def gitlab_repo_url(url)
        path = host_path(url, "gitlab.com")
        return nil unless path

        repo_segments = gitlab_repo_segments(path)
        return nil if repo_segments.nil?
        return nil if repo_segments.length < 2

        owner_parts = repo_segments[0...-1]
        repo = repo_segments.last
        return nil if repo.nil?
        return nil if owner_parts.empty?

        owner = owner_parts.join("/")
        "https://gitlab.com/#{owner}/#{repo.delete_suffix(".git")}.git"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def bitbucket_repo_url(url)
        path = host_path(url, "bitbucket.org")
        return nil unless path

        owner, repo = path.first(2)
        return nil if owner.nil? || repo.nil?

        "https://bitbucket.org/#{owner}/#{repo.delete_suffix(".git")}.git"
      end

      sig { params(url: String, host: String).returns(T.nilable(T::Array[String])) }
      def host_path(url, host)
        uri = URI.parse(url)
        return nil unless uri.host == host

        segments = uri.path.to_s.split("/").reject(&:empty?)
        return nil if segments.empty?

        segments
      rescue URI::InvalidURIError
        nil
      end

      sig { params(path: T::Array[String]).returns(T.nilable(T::Array[String])) }
      def gitlab_repo_segments(path)
        return nil if path.empty?
        return nil if gitlab_api_path?(path)

        if gitlab_route_marker?(path)
          dash_index = path.index("-")
          return nil if dash_index.nil?
          return path.first(dash_index)
        end

        if legacy_gitlab_route_marker?(path)
          marker_index = path.index { |segment| GITLAB_LEGACY_ROUTE_MARKERS.include?(segment) }
          return nil if marker_index.nil?
          return path.first(marker_index)
        end

        path
      end

      sig { params(path: T::Array[String]).returns(T::Boolean) }
      def gitlab_route_marker?(path)
        dash_index = path.index("-")
        return false if dash_index.nil?
        return false if dash_index < 2

        marker = path[dash_index + 1]
        return false if marker.nil?

        GITLAB_DASH_ROUTE_MARKERS.include?(marker)
      end

      sig { params(path: T::Array[String]).returns(T::Boolean) }
      def legacy_gitlab_route_marker?(path)
        marker_index = path.index { |segment| GITLAB_LEGACY_ROUTE_MARKERS.include?(segment) }
        return false if marker_index.nil?
        return false if marker_index < 2

        # legacy routes must have at least a ref after marker:
        # /group/proj/tree/main or /group/proj/raw/main/file
        marker_index + 1 < path.length
      end

      sig { params(path: T::Array[String]).returns(T::Boolean) }
      def gitlab_api_path?(path)
        return false unless path.first == "api"

        version = path[1].to_s
        version.match?(/\Av\d+\z/)
      end
    end
  end
end
