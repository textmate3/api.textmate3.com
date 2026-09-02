#!/usr/bin/env ruby
# script/publish — sign the catalog with the production key and publish it.
#
# GitHub Pages serves docs/ as https://api.textmate3.com, so publishing is
# writing the signed artifacts into docs/ and pushing. Signing happens here,
# on the maintainer's machine: the private key never leaves the login
# keychain, and docs/ only ever receives already-signed artifacts, so nothing
# that can push to this repository can forge a catalog.
#
# The index is written three times: `bundles` is the URL the application
# fetches, and `bundles.xml` is a byte-identical twin whose extension lets
# a browser display the content for debugging. The detached signature covers
# the bytes, so it covers both. `bundles.pub` is the public key that verifies
# the signature, the same key the application is built with, so anyone can
# check the catalog without the application.

require "fileutils"

Dir.chdir(File.expand_path("..", __dir__))
require "bundler/setup"
require_relative "../lib/catalog"

SITE_ROOT         = File.expand_path("docs")
PRODUCTION_ORIGIN = "https://api.textmate3.com"

Bundler.with_unbundled_env { system("script/build") } or abort "script/build failed"

catalog = Catalog.new(
  bundles_root:  File.expand_path("../bundles"),
  catalog_path:  File.expand_path("data/catalog.yml"),
  signing_key:   Catalog.signing_key_from_keychain("TextMate bundle signing (production)"),
  tarballs_root: File.expand_path("tarballs")
)

index = catalog.index_plist(origin: PRODUCTION_ORIGIN)
# One isMandatory key per bundle entry. The uuid key would overcount, because
# every grammar inside an entry carries one too.
bundle_count = index.scan("<key>isMandatory</key>").size

%w[bundles bundles.xml].each do |name|
  File.write(File.join(SITE_ROOT, name), index)
end
File.write(File.join(SITE_ROOT, "bundles.sig"), catalog.sign(index) + "\n")
File.write(File.join(SITE_ROOT, "bundles.pub"), catalog.public_key + "\n")

destination = File.join(SITE_ROOT, "downloads")
FileUtils.mkdir_p(destination)

published = catalog.bundle_dirs.map { |dir_name| "#{dir_name}.tbz" }
Dir.children(destination).each do |name|
  FileUtils.rm(File.join(destination, name)) unless published.include?(name)
end
published.each do |name|
  source = File.expand_path("tarballs/#{name}")
  FileUtils.cp(source, File.join(destination, name)) if File.exist?(source)
end

system("git", "add", "docs") or abort "git add failed"
if `git status --porcelain docs`.strip.empty?
  puts "Catalog unchanged. Nothing to publish."
else
  system("git", "commit", "-m", "Publish #{bundle_count} bundles") or abort "git commit failed"
  system("git", "push") or abort "git push failed"
  puts "Published #{bundle_count} bundles to #{PRODUCTION_ORIGIN}."
end
