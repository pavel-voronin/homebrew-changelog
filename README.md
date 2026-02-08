# `brew changelog`

Instant access to changelogs for Homebrew packages.

## Install

```bash
brew tap pavel-voronin/changelog
brew changelog node | more
brew changelog node -o
```

## Usage

```text
Usage: brew changelog [options] formula|cask

Display changelog for a formula or cask.

      --formula                    Treat the named argument as a formula.
      --cask                       Treat the named argument as a cask.
      --pattern                    Comma-separated wildcard patterns to match
                                   changelog filenames.
  -o, --open                       Open found changelog in browser and print its
                                   URL.
      --print-url                  Print found changelog URL without opening
                                   browser.
      --allow-missing              Exit successfully if no changelog is found.
  -d, --debug                      Display any debugging information.
  -q, --quiet                      Make some output more quiet.
  -v, --verbose                    Make some output more verbose.
  -h, --help                       Show this message.
```

## Examples

```bash
# Find and print changelog content
# Tip: pipe to `less`/`more` for large output
brew changelog codex

# Override filename patterns (first match wins)
brew changelog --pattern='doc/APIchanges,changelog*' ffmpeg

# Open changelog in browser and print URL
brew changelog -o codex

# Hooligan mode: show a LICENSE URL instead
brew changelog --pattern='LICENSE*' --print-url git
```

## License

MIT. See [LICENSE](LICENSE).
