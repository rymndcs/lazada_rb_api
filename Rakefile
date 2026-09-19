# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/unit/**/*_test.rb", "test/conformance/**/*_test.rb"]
end

Rake::TestTask.new("test:live") do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/live/**/*_test.rb"]
end

RuboCop::RakeTask.new

namespace :conformance do
  desc "Fail if test/conformance, CONTRACT.md or .rubocop.yml differ from test/conformance/MANIFEST"
  task :verify do
    ruby "test/conformance/verify_manifest.rb"
  end

  desc "Rewrite test/conformance/MANIFEST from the shared files (only when all three gems change together)"
  task :manifest do
    ruby "test/conformance/verify_manifest.rb --write"
  end
end

task default: %i[test rubocop conformance:verify]
