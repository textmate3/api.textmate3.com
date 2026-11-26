#!/usr/bin/env ruby
# script/update_bundles — bring every bundle checkout to main and pull it, before a publish.
#
# script/publish refuses a checkout that is off main, has uncommitted changes,
# or is behind its remote. This fixes the ones it safely can and names the
# rest: a checkout with uncommitted changes, or on a branch with commits main
# does not have, is left as it is for a person to decide. Exits nonzero when it
# left any, so `script/update_bundles && script/publish` stops there.

Dir.chdir(File.expand_path("..", __dir__))
require_relative "../lib/checkouts"

checkouts = Checkouts.new(root: File.expand_path("../bundles"))
left = checkouts.update

if left.empty?
  puts "Every checkout is on main and up to date."
else
  puts "Left these checkouts as they were:\n  #{left.join("\n  ")}"
  exit 1
end
