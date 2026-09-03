# api.textmate3.com

Everything a running TextMate asks for over the network, served as static files by GitHub Pages from `docs/`, with the tooling that produces them beside it.

## The served surface

| Path             | What it is                                                                          |
| ---------------- | ----------------------------------------------------------------------------------- |
| `/bundles`       | the signed bundle index the application fetches                                     |
| `/bundles.sig`   | detached base64 Ed25519 signature over the exact bytes of `/bundles`                |
| `/bundles.pub`   | the base64 Ed25519 public key that verifies `/bundles.sig` and every archive        |
| `/bundles.pub.txt` | byte-identical twin of `/bundles.pub`, viewable in a browser                      |
| `/bundles.xml`   | byte-identical twin of `/bundles`, viewable in a browser                            |
| `/downloads/…`   | one archive per bundle, addressed by the index and signed inside its entry          |
| `/appcast.xml`   | the Sparkle feed for application updates; release archives live on GitHub Releases |

Future concepts repeat the same shape: a signed index, its detached signature, and viewable twins, for themes, grammars, and whatever else the catalog grows.

## How it is produced

`script/publish` builds the archives from the bundle sources, signs the index and every tarball with the production Ed25519 key on the maintainer's machine, writes the result into `docs/`, and pushes. The private key lives only in the maintainer's login keychain, so nothing that can push to this repository can forge a catalog: the application verifies both the index and each tarball against the public key compiled into it, and modified content fails verification rather than installing.

`docs/` is the folder name GitHub Pages requires for serving a subdirectory of `main`; here it is the site, not documentation.

## Local development

`script/server` runs the same catalog dynamically at `http://localhost:3000`, rebuilding tarballs from the bundle sources so edits are immediately reflected, and signing with a development key created by `script/generate_bundle_signing_key`. Development builds of the application trust the development key and this origin, so the full install and update loop runs offline against the exact verification path production uses.
