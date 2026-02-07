# typed: false
# frozen_string_literal: true

require_relative "../lib/changelog/repo_resolver"

module Homebrew
  module Changelog
    module RepoResolverTest
      module_function

      Head = Struct.new(:url)
      Stable = Struct.new(:url)
      FormulaLike = Struct.new(:head, :stable, :homepage)
      CaskLike = Struct.new(:homepage, :url)

      def assert(condition, message)
        raise message unless condition
      end

      def test_formula_prefers_head_homepage_stable_order
        target = FormulaLike.new(
          Head.new("https://github.com/git/git.git"),
          Stable.new("https://github.com/git/git/archive/refs/tags/v2.0.0.tar.gz"),
          "https://github.com/git/git",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "formula source refs count is incorrect")
        assert(refs.first.kind == :git, "formula source ref kind is incorrect")
        assert(refs.first.location == "https://github.com/git/git.git", "formula URL order/dedup is incorrect")
      end

      def test_formula_can_extract_gitlab_repo_from_stable_archive
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/proj/-/archive/v1.2.3/proj-v1.2.3.tar.gz"),
          "https://example.com/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "stable archive source refs count is incorrect")
        assert(refs.first.kind == :git, "stable archive source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/proj.git", "stable archive extraction failed")
      end

      def test_formula_can_extract_gitlab_subgroup_repo_from_stable_archive
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/subgroup/proj/-/archive/v1.2.3/proj-v1.2.3.tar.gz"),
          "https://example.com/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "subgroup stable archive source refs count is incorrect")
        assert(refs.first.kind == :git, "subgroup stable archive source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/subgroup/proj.git",
               "subgroup stable archive extraction failed")
      end

      def test_formula_can_extract_gitlab_nested_subgroup_repo_from_stable_archive
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/platform/tools/proj/-/archive/v2.0.0/proj-v2.0.0.tar.gz"),
          "https://example.com/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "nested subgroup stable archive source refs count is incorrect")
        assert(refs.first.kind == :git, "nested subgroup stable archive source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/platform/tools/proj.git",
               "nested subgroup stable archive extraction failed")
      end

      def test_gitlab_repo_named_archive_is_supported
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/archive"),
          "https://example.com/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "archive repo source refs count is incorrect")
        assert(refs.first.kind == :git, "archive repo source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/archive.git", "archive repo extraction failed")
      end

      def test_gitlab_subgroup_repo_named_archive_is_supported
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/subgroup/archive"),
          "https://example.com/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "subgroup archive repo source refs count is incorrect")
        assert(refs.first.kind == :git, "subgroup archive repo source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/subgroup/archive.git",
               "subgroup archive repo extraction failed")
      end

      def test_cask_can_extract_from_download_url
        target = CaskLike.new(
          "https://example.com/app",
          "https://downloads.bitbucket.org/team/tool/tool-1.0.0.zip",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs == [], "non-repo cask URLs should not resolve")
      end

      def test_cask_can_extract_gitlab_repo_from_raw_download_url
        target = CaskLike.new(
          "https://bztsrc.gitlab.io/usbimager/",
          "https://gitlab.com/bztsrc/usbimager/raw/binaries/usbimager_1.0.10-arm-macosx-cocoa.zip",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "gitlab raw download source refs count is incorrect")
        assert(refs.first.kind == :git, "gitlab raw download source ref kind is incorrect")
        assert(refs.first.location == "https://gitlab.com/bztsrc/usbimager.git",
               "gitlab raw download extraction failed")
      end

      def test_formula_can_extract_gitlab_repo_from_tree_ref_url
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/proj/tree/main"),
          "",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "gitlab tree ref source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/proj.git",
               "gitlab tree ref extraction failed")
      end

      def test_formula_can_extract_gitlab_repo_from_short_raw_ref_url
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/proj/raw/main/README.md"),
          "",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "short gitlab raw ref source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/proj.git",
               "short gitlab raw ref extraction failed")
      end

      def test_formula_can_extract_gitlab_repo_from_subgroup_raw_ref_url
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/org/sub/proj/raw/main/README.md"),
          "",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "subgroup gitlab raw ref source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/org/sub/proj.git",
               "subgroup gitlab raw ref extraction failed")
      end

      def test_cask_ignores_gitlab_api_package_url
        target = CaskLike.new(
          "https://rnote.flxzt.net/",
          "https://gitlab.com/api/v4/projects/44053427/packages/generic/rnote_macos/0.13.1+215/Rnote-0.13.1+215_arm64.dmg",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.empty?, "gitlab api package URL should be ignored")
      end

      def test_formula_allows_gitlab_api_namespace_repo
        target = FormulaLike.new(
          nil,
          nil,
          "https://gitlab.com/api/myproj",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "api namespace repo source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/api/myproj.git",
               "api namespace repo should not be filtered as API endpoint")
      end

      def test_gitlab_subgroup_named_like_route_marker_is_not_truncated
        target = FormulaLike.new(
          nil,
          Stable.new("https://gitlab.com/group/tags/proj/-/archive/v1.2.3/proj-v1.2.3.tar.gz"),
          "",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "route-like subgroup name source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/group/tags/proj.git",
               "route-like subgroup name should not be truncated")
      end

      def test_gitlab_nested_root_path_with_route_like_names_is_supported
        target = FormulaLike.new(
          nil,
          nil,
          "https://gitlab.com/org/releases/tools/project",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.size == 1, "nested root path source refs count is incorrect")
        assert(refs.first.location == "https://gitlab.com/org/releases/tools/project.git",
               "nested root path should preserve all namespace segments")
      end

      def test_unsupported_host_url_is_ignored
        target = FormulaLike.new(
          nil,
          Stable.new("https://git.sr.ht/~sircmpwn/scdoc/archive/1.11.3.tar.gz"),
          "",
        )

        refs = RepoResolver.new(target).source_refs

        assert(refs.empty?, "unsupported hosts should be ignored")
      end

      def run_all
        test_formula_prefers_head_homepage_stable_order
        test_formula_can_extract_gitlab_repo_from_stable_archive
        test_formula_can_extract_gitlab_subgroup_repo_from_stable_archive
        test_formula_can_extract_gitlab_nested_subgroup_repo_from_stable_archive
        test_gitlab_repo_named_archive_is_supported
        test_gitlab_subgroup_repo_named_archive_is_supported
        test_cask_can_extract_from_download_url
        test_cask_can_extract_gitlab_repo_from_raw_download_url
        test_formula_can_extract_gitlab_repo_from_tree_ref_url
        test_formula_can_extract_gitlab_repo_from_short_raw_ref_url
        test_formula_can_extract_gitlab_repo_from_subgroup_raw_ref_url
        test_cask_ignores_gitlab_api_package_url
        test_formula_allows_gitlab_api_namespace_repo
        test_gitlab_subgroup_named_like_route_marker_is_not_truncated
        test_gitlab_nested_root_path_with_route_like_names_is_supported
        test_unsupported_host_url_is_ignored
      end
    end
  end
end

Homebrew::Changelog::RepoResolverTest.run_all
puts "repo_resolver_test.rb: OK"
