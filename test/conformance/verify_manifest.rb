# frozen_string_literal: true

# Proves this gem's copy of the shared files is identical to the canonical copy. Shared verbatim by the three
# sibling gems.
#
#   ruby test/conformance/verify_manifest.rb           # exit 1 when a shared file differs from MANIFEST
#   ruby test/conformance/verify_manifest.rb --write   # rewrite MANIFEST (only when all three gems change together)
#
# MANIFEST lists the SHA-256 of every file under test/conformance/ (except MANIFEST itself), CONTRACT.md,
# .rubocop.yml, Rakefile, Gemfile and test/support/fake_transport.rb. Compare MANIFEST across the three sibling
# checkouts at review time: a shared-file change is valid only when all three carry the same MANIFEST.
require "digest"

module VerifyManifest
  SUITE_VERSION = "2"
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(ROOT, "test/conformance/MANIFEST")
  SHARED = %w[CONTRACT.md .rubocop.yml Rakefile Gemfile test/support/fake_transport.rb].freeze

  module_function

  def files
    suite = Dir.glob("test/conformance/**/*", File::FNM_DOTMATCH, base: ROOT)
               .select { |path| File.file?(File.join(ROOT, path)) }
               .reject { |path| path == "test/conformance/MANIFEST" }
    (SHARED + suite).sort
  end

  def expected
    lines = files.map { |path| "#{Digest::SHA256.file(File.join(ROOT, path)).hexdigest}  #{path}" }
    "suite #{SUITE_VERSION}\n#{lines.join("\n")}\n"
  end

  def run(argv)
    if argv.include?("--write")
      File.write(MANIFEST, expected)
      puts "wrote #{MANIFEST.delete_prefix("#{ROOT}/")} (#{files.size} files)"
      return 0
    end
    actual = File.exist?(MANIFEST) ? File.read(MANIFEST) : ""
    return 0.tap { puts "conformance manifest OK (#{files.size} shared files)" } if actual == expected

    warn "conformance manifest MISMATCH: a shared file differs from test/conformance/MANIFEST"
    diff(actual, expected).each { |line| warn "  #{line}" }
    1
  end

  def diff(actual, expected)
    have = actual.lines.map(&:chomp)
    want = expected.lines.map(&:chomp)
    (have - want).map { |l| "manifest: #{l}" } + (want - have).map { |l| "on disk:  #{l}" }
  end
end

exit(VerifyManifest.run(ARGV)) if $PROGRAM_NAME == __FILE__
