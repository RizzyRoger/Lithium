# Lithium

A macOS menu bar app that puts a daily time limit on any website, or bans it for
the day outright. Sites with no rule are never restricted.

Lithium is an app rather than a browser extension so limits apply across every
browser and are not trivially removed.

## How blocking works

Two layers, working together:

1. **Redirect layer.** Once a second, Lithium asks the frontmost browser for its
   active tab. If that tab is on a site that has run out of time, the tab is sent
   to a local page that says "Site Blocked for the day". This is what makes the
   block instant and legible.
2. **Hosts layer (optional, needs your admin password once).** Blocked domains
   are mirrored into `/etc/hosts` by a small root helper, so they fail to resolve
   in *every* browser, including ones that cannot be scripted.

Only the redirect layer is on by default. The hosts layer is enabled from the
"Hard blocking is off" prompt in the popover, which asks for your password once
and never again.

## Requirements

- macOS 13 or later (developed and tested on macOS 26)
- Swift toolchain from either Xcode or the Command Line Tools
  (`xcode-select --install`) — full Xcode is not required
- A browser Lithium can script: Safari, Chrome, Chromium, Brave, Edge, Vivaldi,
  Opera, or Arc

Time is measured only for the active tab of the frontmost browser, so limits
track attention rather than merely having a tab open.

## Build and run

```bash
./Scripts/build-app.sh
open dist/Lithium.app
```

The app has no dock icon or window; look for the hourglass in the menu bar.

To install it properly, drag `dist/Lithium.app` to `/Applications`, then turn on
"Launch at login" in the popover's gear menu.

## First launch

1. macOS asks whether Lithium may control your browsers. **Allow this** — without
   it Lithium cannot see which site you are on and cannot count time. If you
   dismiss the prompt, the popover shows a warning with a button that opens
   System Settings › Privacy & Security › Automation.
2. Optionally click **Enable** on "Hard blocking is off" and enter your admin
   password to install the `/etc/hosts` helper.

## Using it

**Set restrictions** (top section) takes a site and an allowance:

- Type a partial name and pick from the suggestions; "tik" offers `tiktok.com`.
  Arrow keys move through suggestions, Return accepts one.
- Set hours and minutes for a daily allowance, or check **Ban for the whole day**.
- The list below shows each site's usage against its limit. Hovering a row
  reveals buttons to edit, pause, reset today's usage, or delete the rule.

A rule for `youtube.com` also covers `m.youtube.com` and any other subdomain. If
two rules could match, the more specific one wins, so `docs.google.com` can have
a different allowance from `google.com`.

**Presets** (bottom section) saves the current rule set under a name. Apply a
preset to swap the whole configuration, for example a strict "work" set and a
looser "weekend" set. Applying is one click, or double-click the row.

Counters reset at local midnight, which also removes the `/etc/hosts` entries.

## Where things live

| Path | Purpose |
| --- | --- |
| `~/Library/Application Support/Lithium/config.json` | Rules, presets, settings |
| `~/Library/Application Support/Lithium/usage.json` | Today's counters |
| `~/Library/Logs/Lithium.log` | App log |
| `/Library/Application Support/Lithium/blocklist.txt` | Domains published to the root helper |
| `/usr/local/libexec/lithium-hostsd` | Root helper that edits `/etc/hosts` |
| `/Library/LaunchDaemons/com.lithium.hostsd.plist` | Runs the helper when the blocklist changes |
| `/var/log/lithium-hostsd.log` | Helper log |
| `~/Library/LaunchAgents/com.lithium.app.plist` | Launch at login |

Lithium only ever writes `blocklist.txt`; the helper is the only thing that
touches `/etc/hosts`, and it only rewrites lines between its
`# BEGIN LITHIUM` and `# END LITHIUM` markers.

## Removing it

Use the gear menu's "Remove hard blocking helper…" to take the root pieces out
and restore `/etc/hosts`, turn off "Launch at login", then quit and delete the
app. To also discard your rules:

```bash
rm -rf ~/Library/Application\ Support/Lithium ~/Library/Logs/Lithium.log
```

## Troubleshooting

Watch what the app is deciding, moment to moment:

```bash
tail -f ~/Library/Logs/Lithium.log
```

For per-tick detail, launch with verbose logging:

```bash
LITHIUM_VERBOSE=1 ./dist/Lithium.app/Contents/MacOS/Lithium
```

**Time is not being counted.** The log will say `Automation access denied`. Grant
access in System Settings › Privacy & Security › Automation, then click "Recheck"
in the popover.

**Sites are not hard-blocked.** Check `/var/log/lithium-hostsd.log` and confirm
the daemon is loaded:

```bash
sudo launchctl print system/com.lithium.hostsd
grep -A5 'BEGIN LITHIUM' /etc/hosts
```

**macOS keeps re-asking for Automation access.** Expected during development: the
app is ad-hoc signed, so its signature changes on every rebuild and macOS treats
it as a new app.

**Check the popover layout** without opening it. A menu bar popover cannot be
screenshotted by tooling, so the app can render its own contents:

```bash
./dist/Lithium.app/Contents/MacOS/Lithium --render-ui /tmp/popover.png
```

`ImageRenderer` cannot draw AppKit-backed controls, so text fields, checkboxes,
steppers and progress bars appear as yellow placeholders in that PNG. They render
normally in the running app.

**Verify the helper's `/etc/hosts` logic** without touching your real one:

```bash
LITHIUM_SUPPORT_DIR=/tmp/lt LITHIUM_HOSTS_FILE=/tmp/lt/hosts \
LITHIUM_LOG_FILE=/tmp/lt/log LITHIUM_LOCK_DIR=/tmp/lt/lock \
LITHIUM_SKIP_DNS_FLUSH=1 ./Scripts/lithium-hostsd
```

## Limits worth knowing

- Firefox cannot be scripted for its active tab, so time on Firefox is not
  counted. The hosts layer still blocks sites there.
- The redirect happens within about a second of landing on a spent site.
- Anyone with admin rights can edit `/etc/hosts` or quit the app. Lithium is a
  self-control tool, not a security boundary.
