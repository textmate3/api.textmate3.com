source "https://rubygems.org"

ruby file: ".ruby-version"

gem "puma"
gem "sinatra"

# Plist parsing + generation (matches the gem vendored in bundle-support).
gem "CFPropertyList"

# Signs the bundle catalog index and tarballs, the same scheme the app verifies
# with SecKeyVerifySignature and Sparkle uses for application updates.
gem "ed25519"
