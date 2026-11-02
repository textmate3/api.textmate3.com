# frozen_string_literal: true

require "shellwords"

# The bundle checkouts the catalog is built from, as git sees them.
#
# The archives are built from the checkouts beside this repository as they are on disk, so a
# checkout with edits not committed, commits not pulled, or a branch other than main checked out,
# publishes something other than what its repository's main holds, and nothing says so. This finds such checkouts by name before anything is
# built. The fetch is what makes "behind" knowable, and it runs a few at a time, since there are a
# couple of hundred checkouts.
class Checkouts
  def initialize(root:, workers: 8)
    @root    = root
    @workers = workers
  end

  # The names of every checkout under the root that is a bundle and a git repository.
  def names
    Dir.children(@root)
      .select { |name| name.end_with?(".tmbundle") || name.end_with?("-tmbundle") }
      .select { |name| File.directory?(File.join(@root, name, ".git")) }
      .sort
  end

  # One line per problem, naming the checkout, or none when every checkout is clean and current.
  def problems
    queue = Queue.new
    names.each { queue << it }
    queue.close

    found = Queue.new
    threads = Array.new(@workers) do
      Thread.new do
        while (name = queue.pop)
          problems_with(name).each { found << it }
        end
      end
    end
    threads.each(&:join)

    lines = []
    lines << found.pop until found.empty?
    lines.sort
  end

  # Aborts with every problem listed when there is one, and with the ways out
  # for each checkout that is not on main.
  def refuse_stale!
    lines = problems
    return if lines.empty?

    message = "publish: refusing to build from these checkouts\n  #{lines.join("\n  ")}"
    off_main = names.reject { on_main?(it) }
    message += "\n#{off_main_help(off_main)}" if off_main.any?
    abort message
  end

  private

  # The archive is built from whatever branch is checked out, so a checkout
  # left on a feature branch would publish that branch's work, or miss what
  # main has.
  def on_main?(name) = branch(name) == "main"

  def branch(name)
    directory = File.join(@root, name)
    `git -C #{directory.shellescape} branch --show-current`.strip
  end

  # A detached HEAD has no branch name.
  def branch_label(name)
    current = branch(name)
    current.empty? ? "no branch, a detached HEAD" : "branch #{current}"
  end

  def off_main_help(off_main)
    sections = off_main.map do |name|
      directory = File.join(@root, name).shellescape
      <<~HELP

        #{name} is on #{branch_label(name)}. Ways back to main, from simplest:

          1. Switch to main, when nothing on this branch needs publishing:
               git -C #{directory} switch main

          2. Switch to main and pull, when main is behind its remote:
               git -C #{directory} switch main
               git -C #{directory} pull

          3. Land this branch first, when its work should be published:
             push it, open a pull request, merge it, then
               git -C #{directory} switch main
               git -C #{directory} pull

          4. Put uncommitted changes aside, when they stop the switch:
               git -C #{directory} stash push --include-untracked
             then switch as above, and later, back on #{branch_label(name)}, bring them back with
               git -C #{directory} stash pop
             Or commit them to this branch instead of stashing.
      HELP
    end
    sections.join + "\nThen run script/publish again."
  end

  def problems_with(name)
    directory = File.join(@root, name)
    lines     = []

    lines << "#{name} is on #{branch_label(name)}, not main" unless on_main?(name)

    dirty = `git -C #{directory.shellescape} status --porcelain`.strip
    lines << "#{name} has uncommitted changes" unless dirty.empty?

    unless system("git", "-C", directory, "fetch", "--quiet", out: File::NULL, err: File::NULL)
      lines << "#{name} could not fetch its remote"
      return lines
    end

    behind = `git -C #{directory.shellescape} rev-list --count HEAD..@{upstream} 2>/dev/null`.strip
    lines << "#{name} is #{behind} commits behind its remote, pull it first" if behind.to_i.positive?
    lines
  end
end
