# Builds the signed bundle catalog: the index plist over every exposed bundle
# checkout, a per-tarball Ed25519 signature inside each entry, and the detached
# signature over the index bytes. Shared by server.rb, which serves it live
# with the development key, and script/publish, which writes it into docs/ with the production key for GitHub Pages to serve.
require "base64"
require "cfpropertylist"
require "ed25519"
require "uri"
require "yaml"

class Catalog
  def self.signing_key_from_keychain(service)
    seed_base64 = `security find-generic-password -s '#{service}' -w 2>/dev/null`.strip
    abort "No keychain entry ‘#{service}’. Run script/generate_bundle_signing_key first." if seed_base64.empty?
    Ed25519::SigningKey.new(Base64.strict_decode64(seed_base64))
  end

  def initialize(bundles_root:, catalog_path:, signing_key:, tarballs_root:)
    @bundles_root = bundles_root
    @catalog_path = catalog_path
    @signing_key = signing_key
    @tarballs_root = tarballs_root
    @tarball_signature_cache = {}
    @tarball_signature_mutex = Mutex.new
  end

  def sign(bytes) = Base64.strict_encode64(@signing_key.sign(bytes))

  def tarball_path(dir_name) = File.join(@tarballs_root, "#{dir_name}.tbz")

  def bundle_dirs
    excluded = Array(configuration["exclude"])
    Dir.children(@bundles_root)
      .select { |name| name.end_with?(".tmbundle") }
      .select { |name| File.directory?(File.join(@bundles_root, name)) }
      .reject { |name| excluded.include?(name) }
      .sort
  end

  # The rendered index for the given origin, as XML plist bytes. XML rather
  # than OpenStep ASCII: TextMate's ASCII parser (Frameworks/plist/src/ascii.rl)
  # requires `@`-prefixed dates which CFPropertyList does not emit. XML
  # round-trips cleanly through both.
  def index_plist(origin:)
    bundles = bundle_dirs.filter_map { |dir_name| build_bundle_dict(dir_name, origin: origin) }
    plist = CFPropertyList::List.new
    plist.value = CFPropertyList.guess({ "bundles" => bundles })
    plist.to_str(CFPropertyList::List::FORMAT_XML)
  end

  private

  def configuration
    @configuration ||= YAML.load_file(@catalog_path) || {}
  end

  def defaults = Hash(configuration["defaults"])

  def per_bundle_overrides(dir_name) = Hash(configuration.dig("bundles", dir_name))

  def bundle_info(dir_name)
    info_path = File.join(@bundles_root, dir_name, "info.plist")
    return nil unless File.exist?(info_path)
    CFPropertyList.native_types(CFPropertyList::List.new(file: info_path).value)
  rescue CFFormatError, IOError
    nil
  end

  def grammar_entries(dir_name)
    syntaxes_dir = File.join(@bundles_root, dir_name, "Syntaxes")
    return [] unless File.directory?(syntaxes_dir)
    Dir.children(syntaxes_dir).filter_map do |file|
      next unless file.end_with?(".tmLanguage", ".plist")
      path = File.join(syntaxes_dir, file)
      next unless File.file?(path)
      parsed = CFPropertyList.native_types(CFPropertyList::List.new(file: path).value) rescue nil
      next unless parsed.is_a?(Hash)
      entry = {
        "name"  => parsed["name"],
        "scope" => parsed["scopeName"],
        "uuid"  => parsed["uuid"],
      }
      entry["firstLineMatch"] = parsed["firstLineMatch"] if parsed["firstLineMatch"]
      entry["fileTypes"]      = parsed["fileTypes"]      if parsed["fileTypes"].is_a?(Array)
      entry.compact
    end.compact
  end

  def tarball_meta(dir_name, origin:)
    path = tarball_path(dir_name)
    return nil unless File.exist?(path)
    stat = File.stat(path)
    {
      url:     "#{origin}/downloads/#{URI.encode_www_form_component(dir_name)}.tbz",
      updated: stat.mtime.utc,
      size:    stat.size,
    }
  end

  # mtime-keyed so the 200+ tarballs are read and signed once, not on every
  # index rebuild.
  def tarball_signature(path)
    mtime = File.mtime(path)
    @tarball_signature_mutex.synchronize do
      entry = @tarball_signature_cache[path]
      if entry.nil? || entry[:mtime] != mtime
        entry = { mtime: mtime, signature: sign(File.binread(path)) }
        @tarball_signature_cache[path] = entry
      end
      entry[:signature]
    end
  end

  def build_bundle_dict(dir_name, origin:)
    info = bundle_info(dir_name)
    return nil unless info && info["uuid"]

    meta = tarball_meta(dir_name, origin: origin)
    overrides = per_bundle_overrides(dir_name)
    signature = meta ? tarball_signature(tarball_path(dir_name)) : nil

    entry = {
      "uuid"        => info["uuid"],
      "name"        => info["name"]          || dir_name,
      "category"    => overrides["category"] || defaults["category"] || "Languages",
      "isDefault"   => overrides.fetch("isDefault",   defaults.fetch("isDefault",   false)),
      "isMandatory" => overrides.fetch("isMandatory", defaults.fetch("isMandatory", false)),
    }
    entry["description"]       = info["description"]       if info["description"]
    entry["contactName"]       = info["contactName"]       if info["contactName"]
    entry["contactEmailRot13"] = info["contactEmailRot13"] if info["contactEmailRot13"]
    entry["requires"]          = info["requires"]          if info["requires"].is_a?(Array)

    grammars = grammar_entries(dir_name)
    entry["grammars"] = grammars unless grammars.empty?

    if meta
      entry["versions"] = [
        { "url" => meta[:url], "signature" => signature, "updated" => meta[:updated], "size" => meta[:size] },
      ]
    end

    entry
  end
end
