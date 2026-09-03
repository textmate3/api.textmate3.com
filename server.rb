# api.textmate3.com — local-development stand-in for the production catalog,
# which GitHub Pages serves from docs/ of this repository.
#
# Endpoints:
#   GET /              — sanity check; lists available routes
#   GET /bundles       — XML plist index of all exposed bundles
#                        (consumed by Frameworks/updater + Frameworks/BundlesManager)
#   GET /bundles.sig   — detached base64 Ed25519 signature over the exact bytes of /bundles
#   GET /bundles.pub   — the base64 Ed25519 public key that verifies it (also as /bundles.pub.txt)
#   GET /downloads/:name.tbz
#                      — serves the prebuilt bundle archive
#   GET /appcast.xml   — Sparkle feed for application updates; script/appcast writes it
#   GET /releases/:file
#                      — serves the update archives the appcast points at
#
# Everything is signed with Ed25519, the same scheme production uses, through
# the shared Catalog class in lib/catalog.rb. The signing key is the
# development keypair created by script/generate_bundle_signing_key: private
# half in the login keychain, public half compiled into local builds through
# BUNDLE_PUBLIC_ED_KEY in local.rave. Production publishing is script/publish,
# which uses the same Catalog with the production key and a fixed origin.
# Application updates in the appcast are signed the same way: script/appcast
# produces Sparkle's EdDSA signature with its own development key.

require "digest"
require "sinatra/base"
require_relative "lib/catalog"

class Server < Sinatra::Base
  REPO_ROOT     = File.expand_path("..", __dir__)
  RELEASES_ROOT = File.expand_path("releases", __dir__)

  # One catalog, and with it one signing key, for the process lifetime. The
  # keychain read aborts loudly when the development key is missing, which
  # beats serving an unsigned catalog the app would reject one request later
  # with a less helpful error.
  def self.catalog
    @catalog ||= Catalog.new(
      bundles_root:  File.join(REPO_ROOT, "bundles"),
      catalog_path:  File.expand_path("data/catalog.yml", __dir__),
      signing_key:   Catalog.signing_key_from_keychain("TextMate bundle signing (development)"),
      tarballs_root: File.expand_path("tarballs", __dir__)
    )
  end

  helpers do
    def base_origin
      "#{request.scheme}://#{request.host_with_port}"
    end
  end

  get "/" do
    content_type :text
    routes = ["GET /", "GET /bundles", "GET /bundles.sig", "GET /bundles.pub", "GET /bundles.pub.txt", "GET /downloads/:name.tbz", "GET /appcast.xml", "GET /releases/:file"]
    "api.textmate3.com — local dev\n\n" + routes.join("\n") + "\n"
  end

  get "/appcast.xml" do
    path = File.expand_path("appcast.xml", RELEASES_ROOT)
    halt 404, "no appcast; run script/appcast" unless File.exist?(path)
    send_file path, type: "application/xml"
  end

  get "/releases/:file" do
    path = File.expand_path(params[:file], RELEASES_ROOT)
    halt 404, "no such release" unless path.start_with?(RELEASES_ROOT + "/") && File.exist?(path)
    send_file path, type: "application/octet-stream"
  end

  # Building the index parses every bundle's info.plist and grammar files,
  # which takes seconds across 200+ bundles. Cache the rendered result
  # briefly (the app polls, and the dev loop rebuilds tarballs at most every
  # few seconds) and derive the ETag from the content so a client honoring
  # If-None-Match sees updates instead of the previous constant tag.
  INDEX_CACHE_SECONDS = 10
  INDEX_CACHE = { mutex: Mutex.new, at: nil, body: nil, etag: nil, signature: nil }

  # The signature is computed when the body is cached, over those exact bytes,
  # so /bundles and /bundles.sig can never disagree within a cache window.
  def cached_index
    INDEX_CACHE[:mutex].synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if INDEX_CACHE[:at].nil? || now - INDEX_CACHE[:at] > INDEX_CACHE_SECONDS
        body = Server.catalog.index_plist(origin: base_origin)
        INDEX_CACHE.merge!(at: now, body: body, etag: Digest::SHA1.hexdigest(body), signature: Server.catalog.sign(body))
      end
      INDEX_CACHE.dup
    end
  end

  get "/bundles" do
    content_type "text/plain; charset=utf-8"
    cached = cached_index
    etag cached[:etag]
    cached[:body]
  end

  get "/bundles.sig" do
    content_type :text
    cached_index[:signature]
  end

  get %r{/bundles\.pub(\.txt)?} do
    content_type :text
    Server.catalog.public_key + "\n"
  end

  get "/downloads/:name.tbz" do
    path = Server.catalog.tarball_path(params[:name])
    halt 404, "no such tarball" unless File.exist?(path)
    send_file path, type: "application/x-bzip-compressed-tar"
  end
end
