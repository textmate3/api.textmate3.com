#!/usr/bin/env ruby
# script/build — produce one .tbz tarball per bundle into tarballs/.
#
# Reads from ../bundles/*.tmbundle and ../bundles/*-tmbundle, honors the
# `exclude` list in data/catalog.yml, and writes tarballs/<dir-name>.tbz.
# Skips bundles whose contents are unchanged since the last build (tarball
# mtime newer than every file under the bundle dir and than this script).
#
# Each tarball carries a Changes.json at the top of the bundle, written from
# the checkout's git history, which the application's About window reads for
# its Bundles tab. The file is staged outside the checkout so the checkout
# stays clean.

require "cgi"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

API_ROOT      = File.expand_path("..", __dir__)
REPO_ROOT     = File.expand_path("..", API_ROOT)
BUNDLES_ROOT  = File.join(REPO_ROOT, "bundles")
TARBALLS_ROOT = File.join(API_ROOT, "tarballs")
CATALOG_PATH  = File.join(API_ROOT, "data", "catalog.yml")

# The About window keeps commits from the current year and the two before it.
# Older ones would only make the file bigger.
CHANGES_SINCE = "#{Time.now.year - 2}-01-01"

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

# The bundle's display name from its info.plist, or the directory name without its suffix.
def bundle_name(source_dir)
  info_path = File.join(source_dir, "info.plist")
  if File.exist?(info_path)
    name, status = Open3.capture2("plutil", "-extract", "name", "raw", "-o", "-", info_path, err: File::NULL)
    return name.strip if status.success? && !name.strip.empty?
  end
  File.basename(source_dir).sub(/[.-]tmbundle\z/, "")
end

# The checkout's recent commits, newest first, as the About window's Bundles tab expects them.
# Fields are separated by a NUL and commits by a record separator, neither of which a commit message can hold.
# Summary and body are inserted into the page as HTML, so they are escaped here.
def recent_commits(source_dir)
  format = "%aI%x00%an%x00%s%x00%b%x1e"
  log, status = Open3.capture2("git", "-C", source_dir, "log", "--since=#{CHANGES_SINCE}", "--format=#{format}", err: File::NULL)
  return [] unless status.success?

  log.split("\x1e").filter_map do |record|
    date, author, summary, body = record.sub(/\A\n/, "").split("\x00", 4)
    next if date.nil? || date.empty?
    {
      date: date,
      author: author,
      summary: CGI.escapeHTML(summary.to_s),
      body: CGI.escapeHTML(body.to_s.strip),
    }
  end
end

def write_changes_json(source_dir, staging_dir)
  changes = { name: bundle_name(source_dir), commits: recent_commits(source_dir) }
  File.write(File.join(staging_dir, "Changes.json"), JSON.pretty_generate(changes) + "\n")
end

rebuilt   = 0
unchanged = 0
script_mtime = File.mtime(__FILE__).to_i

Dir.mktmpdir("textmate-bundle-build") do |staging_root|
  bundle_dirs.each do |name|
    source_dir   = File.join(BUNDLES_ROOT, name)
    tarball_path = File.join(TARBALLS_ROOT, "#{name}.tbz")

    source_mtime  = [newest_mtime_under(source_dir), script_mtime].max
    tarball_mtime = File.exist?(tarball_path) ? File.mtime(tarball_path).to_i : 0

    if tarball_mtime >= source_mtime && tarball_mtime > 0
      unchanged += 1
      next
    end

    staging_dir = File.join(staging_root, name)
    FileUtils.mkdir_p(staging_dir)
    write_changes_json(source_dir, staging_dir)

    # The checkout provides the bundle, the staging directory provides the one generated file beside it.
    command = [
      "tar", "--no-mac-metadata", "--exclude=.git", "-cjf", tarball_path,
      "-C", BUNDLES_ROOT, name,
      "-C", staging_root, File.join(name, "Changes.json")
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
end

puts "Built #{rebuilt} new/updated tarball(s); #{unchanged} unchanged."
