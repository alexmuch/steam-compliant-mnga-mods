# steam-compliant-mnga-mods

Natural Selection 2 server mods for the MNGA (manga) community, packaged for the Steam Workshop.

## Mods

| Folder | Workshop name | Description |
| --- | --- | --- |
| [`mnga_admin/`](mnga_admin) | manga admin | Server administration, voting, ready-room queue, ready check, gags/mutes, multi-ping, radio commands, bot brains, weekly quests, and QoL tweaks (Shine extensions + game hooks). |
| [`shimizu_scoreboard/`](shimizu_scoreboard) | shimizu quick score | Extended scoreboard with skill display, player aliases, voice/chat mute controls, and tech map. |

Each mod folder follows the standard NS2 Launch Pad layout:

```
<mod>/
  mod.settings   # Launch Pad project settings
  preview.jpg    # Workshop preview image
  output/        # Files published to the Workshop (lua/, ui/, locale/, ...)
```

## Building / publishing

Open the mod folder in the NS2 Launch Pad (or use the `builder` tool) and publish `output/` to the Steam Workshop.

## Configuration

Server-side settings live in the Shine config generated on first run. `mnga_admin` defaults `xpCentralURL` to `http://127.0.0.1:25386` and `xpSharedSecret` to empty — set these in your server's Shine config, never in this repo.

## Requirements

- [Shine](https://github.com/Person8880/Shine) administration mod

## License

MIT — see [LICENSE](LICENSE). Files carrying Unknown Worlds Entertainment copyright headers remain under their original terms; see [NOTICE](NOTICE).
