#!/usr/bin/env ruby
# script/build — produce one .tbz tarball per bundle into tarballs/.
#
# Reads from ../bundles/*.tmbundle and ../bundles/*-tmbundle, honors the
# `exclude` list in data/catalog.yml, and writes tarballs/<dir-name>.tbz.
# Skips bundles whose contents are unchanged since the last build (tarball
# mtime newer than every file under the bundle dir).

require "fileutils"
require "yaml"

API_ROOT      = File.expand_path("..", __dir__)
REPO_ROOT     = File.expand_path("..", API_ROOT)
BUNDLES_ROOT  = File.join(REPO_ROOT, "bundles")
TARBALLS_ROOT = File.join(API_ROOT, "tarballs")
CATALOG_PATH  = File.join(API_ROOT, "data", "catalog.yml")

FileUtils.mkdir_p(TARBALLS_ROOT)

catalog  = (YAML.load_file(CATALOG_PATH) rescue {}) || {}
excluded = Array(catalog["exclude"])

bundle_dirs = Dir.children(BUNDLES_ROOT)
  .select  { |name| name.end_with?(".tmbundle") || name.end_with?("-tmbundle") }
  .select  { |name| File.directory?(File.join(BUNDLES_ROOT, name)) }
  .reject  { |name| excluded.include?(name) }
  .sort

def newest_mtime_under(directory)
  newest = 0
  Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).each do |path|
    next if File.basename(path).start_with?(".git")
    next unless File.file?(path)
    mtime = File.mtime(path).to_i rescue 0
    newest = mtime if mtime > newest
  end
  newest
end

rebuilt   = 0
unchanged = 0

bundle_dirs.each do |name|
  source_dir   = File.join(BUNDLES_ROOT, name)
  tarball_path = File.join(TARBALLS_ROOT, "#{name}.tbz")

  source_mtime  = newest_mtime_under(source_dir)
  tarball_mtime = File.exist?(tarball_path) ? File.mtime(tarball_path).to_i : 0

  if tarball_mtime >= source_mtime && tarball_mtime > 0
    unchanged += 1
    next
  end

  command = [
    "tar", "--no-mac-metadata", "--exclude=.git", "-cjf",
    tarball_path, "-C", BUNDLES_ROOT, name
  ]
  status = system(*command, out: File::NULL, err: File::NULL)
  unless status
    warn "FAILED to build tarball for #{name}"
    next
  end

  File.utime(Time.now, Time.now, tarball_path)
  puts "  built  #{name}.tbz"
  rebuilt += 1
end

puts "Built #{rebuilt} new/updated tarball(s); #{unchanged} unchanged."
