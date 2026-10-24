# frozen_string_literal: true

require "shellwords"

# The bundle checkouts the catalog is built from, as git sees them.
#
# The archives are built from the checkouts beside this repository as they are on disk, so a
# checkout with edits not committed, or commits not pulled, publishes something other than what
# its repository holds, and nothing says so. This finds such checkouts by name before anything is
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

  # Aborts with every problem listed when there is one.
  def refuse_stale!
    lines = problems
    return if lines.empty?

    abort "publish: refusing to build from these checkouts\n  #{lines.join("\n  ")}"
  end

  private

  def problems_with(name)
    directory = File.join(@root, name)
    lines     = []

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
