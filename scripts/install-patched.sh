#!/usr/bin/env bash
# Swap the noruntime-patched agent-browser-linux-x64 (PATCHED.md) into an npm
# install of agent-browser. Refuses unless the installed package version is the
# patch's base version.
#
# Usage: install-patched.sh [options] <tag>      e.g. v0.41.1-noruntime.1
#        install-patched.sh [options] --restore
# Options:
#   --prefix DIR   npm prefix: DIR/node_modules/agent-browser (npm install --prefix DIR)
#                  or DIR/lib/node_modules/agent-browser (npm -g --prefix DIR).
#   --path DIR     the agent-browser package directory itself.
#                  Default for both: "$(npm root -g)/agent-browser".
#   --repo O/R     GitHub repo with the releases (default AzureDominus/agent-browser).
#   --file FILE    use this local binary instead of downloading the release asset
#                  (its --version must still match <tag>).
#   --dry-run      download and check, but don't touch the install.
#   --restore      put back the stock binary saved by an earlier install.
#
# The stock binary is kept once as bin/agent-browser-linux-x64.stock-<version>
# (never overwritten by later patch revisions). The swap is a rename, so running
# processes keep their old binary. Because the patched binary reports a different
# version, the next agent-browser command restarts daemons started by the old one.
set -euo pipefail

REPO=AzureDominus/agent-browser
ASSET=agent-browser-linux-x64
pkg="" tag="" file="" dry=0 restore=0

die() { echo "install-patched: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; exit "${1:-0}"; }

while (($#)); do
  case $1 in
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a value"
      if [[ -d $2/node_modules/agent-browser ]]; then pkg=$2/node_modules/agent-browser
      elif [[ -d $2/lib/node_modules/agent-browser ]]; then pkg=$2/lib/node_modules/agent-browser
      else die "no agent-browser package under prefix $2"; fi
      shift 2 ;;
    --path) [[ $# -ge 2 ]] || die "--path needs a value"; pkg=$2; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die "--repo needs a value"; REPO=$2; shift 2 ;;
    --file) [[ $# -ge 2 ]] || die "--file needs a value"; file=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --restore) restore=1; shift ;;
    -h|--help) usage ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ -z $tag ]] || die "only one tag allowed"; tag=$1; shift ;;
  esac
done

if [[ -z $pkg ]]; then
  root=$(npm root -g 2>/dev/null) || die "npm root -g failed; pass --prefix or --path"
  pkg=$root/agent-browser
fi
[[ -f $pkg/package.json ]] || die "$pkg is not an agent-browser package (no package.json)"
pkg=$(cd "$pkg" && pwd -P)
installed=$(sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$pkg/package.json" | head -1)
grep -q '^  "name": "agent-browser"' "$pkg/package.json" || die "$pkg/package.json is not the agent-browser package"
target=$pkg/bin/$ASSET
stock=$target.stock-$installed

if ((restore)); then
  [[ -f $stock ]] || die "no saved stock binary $stock"
  ((dry)) && { echo "would restore $stock -> $target"; exit 0; }
  cp -p "$stock" "$target.restore.$$" && mv -f "$target.restore.$$" "$target"
  echo "restored stock agent-browser $installed: $("$target" --version)"
  exit 0
fi

[[ -n $tag ]] || usage 2
[[ $tag == v* ]] || tag=v$tag
[[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-noruntime\.[0-9]+$ ]] || die "tag must look like v0.41.1-noruntime.1, got $tag"
base=${BASH_REMATCH[1]}
version=${tag#v}

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die "only Linux x86_64 is built (this is $(uname -sm))"
if ldd --version 2>&1 | grep -qi musl; then die "musl libc: the launcher would use agent-browser-linux-musl-x64, which isn't built"; fi
[[ $installed == "$base" ]] || die "installed agent-browser is $installed but $tag patches $base; install agent-browser@$base first (or use a patch tag for $installed)"
[[ -f $target ]] || die "missing $target"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
new=$work/$ASSET
if [[ -n $file ]]; then
  cp "$file" "$new"
else
  url=https://github.com/$REPO/releases/download/$tag
  echo "downloading $url/$ASSET"
  curl -fsSL --retry 3 -o "$new" "$url/$ASSET" || die "download failed: $url/$ASSET"
  curl -fsSL --retry 3 -o "$new.sha256" "$url/$ASSET.sha256" || die "download failed: $url/$ASSET.sha256"
  (cd "$work" && sha256sum -c --quiet "$ASSET.sha256") || die "sha256 mismatch for $ASSET"
fi
chmod 755 "$new"
got=$("$new" --version 2>&1) || die "downloaded binary doesn't run: $got"
[[ $got == "agent-browser $version" ]] || die "downloaded binary reports '$got', expected 'agent-browser $version'"
grep -q AGENT_BROWSER_CAPTURE_CONSOLE "$new" || die "downloaded binary lacks the noruntime patch marker"
echo "checked: $got"

current=$("$target" --version 2>&1 || true)
if ((dry)); then
  echo "dry run: would replace $target ($current) with $got"
  exit 0
fi
if [[ ! -f $stock ]]; then
  if grep -q AGENT_BROWSER_CAPTURE_CONSOLE "$target"; then
    die "$target is already patched ($current) but $stock is missing; reinstall agent-browser@$installed first"
  fi
  cp -p "$target" "$stock"
  echo "saved stock binary: $stock"
fi
cp "$new" "$target.new.$$"
chmod 755 "$target.new.$$"
mv -f "$target.new.$$" "$target"
echo "installed $got -> $target (was: $current)"
echo "undo: $0 --path '$pkg' --restore"
