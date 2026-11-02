# agent-browser, noruntime patch

This fork carries one commit on top of an upstream
[vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) release
tag. Branch: `noruntime`. Releases: `v<upstream>-noruntime.<n>`, Linux x86_64
(glibc) only.

## What the patch does

agent-browser normally sends the CDP command `Runtime.enable` to every page
it attaches to. Pages can detect that (the "Runtime.enable leak" checked by
rebrowser's bot detector, deviceandbrowserinfo.com and Fingerprint's
DevTools signal). The patch sends it only when the daemon starts with
`AGENT_BROWSER_CAPTURE_CONSOLE=1` (`true`/`yes` also work).

- Gated sites: `prepare_domains` and `enable_domains_direct` in
  `cli/src/native/browser.rs`, `prepare_auto_attached_session` in
  `cli/src/native/actions.rs`. The helper is `cli/src/native/noruntime.rs`.
  `cli/src/native/state.rs` still enables Runtime on its own throwaway blank
  tab during state save; no site sees that.
- Without the variable, `console` and `errors` return nothing (they
  need `Runtime.consoleAPICalled`/`Runtime.exceptionThrown`), and the
  dashboard stream shows no console output. Everything else (`eval`,
  `snapshot`, clicks, `fill`, screenshots, tabs, iframes, `expose`) works
  without it.
- The variable is read by the daemon, so it must be set in the environment
  that starts it. A daemon that is already running keeps its setting; close
  that session (or kill its daemon PID) to change it.
- Tests: the upstream "`Runtime.enable` failure disconnects" cases are
  replaced by `test_runtime_enable_only_sent_when_capturing_console`.
- The binary reports `agent-browser <upstream>-noruntime.<n>`. The CLI
  restarts a daemon whose version differs, so after a swap the next command
  replaces daemons left by the stock binary.

## Install

Needs the matching upstream npm package; the script refuses otherwise.

```sh
npm install -g agent-browser@0.41.1          # if not already that version
curl -fsSLO https://raw.githubusercontent.com/AzureDominus/agent-browser/noruntime/scripts/install-patched.sh
bash install-patched.sh v0.41.1-noruntime.1  # global install; see --help
agent-browser --version                      # agent-browser 0.41.1-noruntime.1
```

Options: `--prefix DIR` for `npm install --prefix DIR` installs, `--path DIR`
for a package directory, `--dry-run`, `--restore` (puts back the stock binary
saved as `bin/agent-browser-linux-x64.stock-<version>`). `npm update`,
`npm install -g agent-browser` or `agent-browser upgrade` bring back the stock
binary; run the script again afterwards.

## Sync to a new upstream release

```sh
git fetch upstream --tags
git switch noruntime
git rebase --onto v0.42.0 v0.41.1 noruntime   # old base -> new upstream tag
git push --force-with-lease origin noruntime
git tag v0.42.0-noruntime.1
git push origin v0.42.0-noruntime.1           # CI tests, builds, releases
```

If the rebase conflicts, re-apply the `if
super::noruntime::runtime_enable_wanted() { ... }` wrapper around each
`Runtime.enable` send. CI's "Every Runtime.enable send is gated" step fails if
upstream added a new ungated send; gate it the same way. A fix to the patch on
the same upstream base gets the next number (`v0.41.1-noruntime.2`). The
workflow can also be run by hand (Actions → Patched release (noruntime) → Run
workflow) with a tag, or with no tag for a test build whose binary is an
artifact of the run.

Upstream's own `ci.yml` and `release.yml` are disabled in this fork's Actions
settings, so syncing `main` doesn't publish anything.
