# DJ Amp

An AI agent DJ for [Omarchy Quattro](https://omarchy.org) that runs
[cliamp](https://github.com/bjarneo/cliamp) for you.

Not a shuffle button. DJ Amp watches the deck through cliamp's IPC socket, and
about twenty seconds before a track runs out it asks your coding agent what
should go on next — given the hour, what's in your crate, what you've already
heard, and anything you told it you wanted. Then it puts the record on and
tells you why, in one line, the way a DJ talks over an intro.

You can also just ask. Open the panel, type _"nothing with words, I'm
debugging"_, and it goes and finds something.

## What it looks like

One icon in the bar with a scrolling now-playing label, and one panel behind
it:

- **The deck** — title, artist, playlist, position, and a scrubbable progress
  bar.
- **The spectrum** — a Winamp-style ten-band analyzer with falling peak caps,
  fed by `cliamp visstream`, painted in your Omarchy theme's colors.
- **The DJ** — an autopilot switch, the last call it made, and the reason
  behind it.
- **Requests** — a line you type into.
- **The set list** — the last dozen calls, marked by who made them: the agent,
  or the rule-based DJ that stands in when no agent answered.

## Install

DJ Amp needs `cliamp` and `jq`. Everything else it uses (`hyprctl`,
`notify-send`, an agent CLI) it does without when absent.

```bash
git clone https://github.com/MatrixJockey/MatrixJockey.git
./MatrixJockey/dj-amp/install.sh
omarchy plugin enable matrixjockey.dj-amp
```

`install.sh` validates the manifest, copies the plugin into
`~/.config/omarchy/plugins/matrixjockey.dj-amp/`, links `dj-amp` onto your
PATH, and asks the shell to rescan.

> The plugin lives in a subdirectory of this repository, so
> `omarchy plugin add <git-url>` — which expects `manifest.json` at the
> repository root — won't reach it. That's what `install.sh` is for.

The widget lands on the right of the bar; move it with `omarchy bar move`. It
stays out of the bar entirely until cliamp is actually running, so a machine
that never plays music never grows an icon.

## The DJ

The part that decides is `bin/dj-amp-brain`, a standalone script. It gathers
the context, asks an agent, and prints one JSON object. It never touches
cliamp — it returns intentions, and the shell plugin is what applies them.

That split is deliberate. The brain may only answer in a fixed vocabulary of
moves (`load`, `search`, `queue`, `next`, `volume`, `shuffle`, …), each with at
most one argument. Anything outside the vocabulary is dropped. A `load` naming
a playlist you don't have is dropped. Every surviving move is executed as its
own argv element with no shell in the path, so nothing a model writes can
become a second command. If a plan loses all its moves that way, the
rule-based DJ puts a record on instead.

You can run the brain by hand to see what it would do:

```bash
dj-amp-brain --reason handoff --agent off | jq .
dj-amp-brain --reason request --request "something with a beat"
```

### Which agent

By default DJ Amp asks whichever agent you set with `omarchy default agent`,
in that CLI's one-shot print mode — `claude -p`, `codex exec`, `opencode run`,
and so on. No API key of its own, no second subscription.

Set the `agent` setting to name one explicitly, or to `off` to skip the agent
entirely and run only the rules below. To wire up something else — a local
model through Ollama, say — point `DJ_AMP_AGENT_CMD` at any command that takes
a prompt as its last argument and prints an answer.

### When there's no agent

The fallback DJ isn't a placeholder; it's what runs whenever the agent is off,
times out, or answers with something unusable. It knows two things:

- **The clock.** It scores your playlist names against the hour — `Late Night
  Chill` reads as a night record, `Morning Coffee` as a morning one — and picks
  the best-scoring playlist that isn't the one that just finished.
- **Your words.** A request is read as an instruction first (_louder_,
  _skip_, _quiet_, _shuffle_), then matched word-by-word against your crate,
  and only then handed to `cliamp search`.

It also knows when to do nothing: a handoff partway through a playlist that
still has tracks left leaves the deck alone and says so.

## Settings

Under _Setup > Plugins_, or on the widget's entry in
`~/.config/omarchy/shell.json`:

| Setting | Default | What it does |
|---|---|---|
| `autopilot` | `true` | Let the DJ mix on its own. Off means it only answers requests. |
| `vibe` | `""` | A standing brief — "instrumental while I'm working, louder after 9pm". |
| `crate` | `Playlists + search` | How far the DJ may reach: your playlists only, playlists plus network search, or search only. |
| `agent` | `auto` | Which agent CLI thinks. `auto` follows `omarchy default agent`; `off` runs the rules. |
| `handoffSeconds` | `25` | How long before a track ends the DJ is asked for the next one. `0` disables the handoff. |
| `pollMs` | `1000` | How often the deck is read while playing. Idle polling backs off to 5s on its own. |
| `announce` | `true` | Send a desktop notification on each call. |
| `showSpectrum` | `true` | Draw the analyzer. |
| `spectrumFps` | `30` | Analyzer frame rate, 1–60. |
| `maxLabelWidth` | `200` | Width of the bar's now-playing label. `0` hides it. |

```bash
omarchy bar set matrixjockey.dj-amp vibe 'instrumental, nothing with words'
omarchy bar set matrixjockey.dj-amp handoffSeconds 40 --json
```

## Controls

**Bar icon** — left click opens the panel, right click skips, middle click
toggles autopilot.

**Panel** — `j`/`k` skip, `h`/`l` volume, `Enter` play/pause, `/` jump to the
request line, `m` mix now, `a` autopilot, `Tab` to the neighboring panel, `Esc`
closes. Click the progress bar to seek.

**Terminal and keybinds** — `dj-amp`:

```bash
dj-amp                              # what's on, and what the DJ last said
dj-amp request "wind it down"
dj-amp mix                          # pick the next record right now
dj-amp autopilot off
dj-amp skip
```

Straight to the shell if you'd rather:

```bash
omarchy-shell dj-amp status
omarchy-shell dj-amp request 'something with a beat'
omarchy-shell shell toggle matrixjockey.dj-amp '{}'
```

Which makes a Hyprland binding a one-liner:

```
bind = SUPER SHIFT, M, exec, dj-amp mix
```

## What gets sent to the agent

Each call sends the current track, the playlist you're on, your playlist
_names_, your last fifteen plays from `cliamp history`, the time of day, your
standing brief, and your request. Plus the class of your foreground window —
`Alacritty`, `firefox` — because a DJ that knows you're in a terminal picks
differently. Never the window title, where file names and page titles live.

`DJ_AMP_PRIVATE=1` drops the foreground app too. Setting `agent` to `off`
sends nothing anywhere; the rules run locally.

## Notes

Plugins run as unsandboxed code inside the long-lived `omarchy-shell` process.
This one shells out to `cliamp`, `notify-send`, `hyprctl`, and your agent CLI,
and reads nothing but cliamp's own output. It's short enough to read before you
enable it, which is the recommendation for any plugin.

MIT licensed. cliamp is by [@bjarneo](https://github.com/bjarneo); Omarchy is
by [Basecamp](https://github.com/basecamp/omarchy).
