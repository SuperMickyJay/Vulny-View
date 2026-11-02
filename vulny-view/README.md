# Vulny View

A small top-down, grid-based movement game (Pokemon-style) built with **Godot 4.7**
and **GDScript**, targeting **Android**. You pick a character, walk one tile at
a time around a town, a camera follows you, and you can face NPCs / objects and press the
action button to read dialogue. It supports single-player and **multiplayer** (host/join on
the same network, or a dedicated server), with emotes and overhead chat bubbles.

The visuals use pixel-art character sprite sheets and a tile-based town map built from a
Godot `TileSet` — landscape orientation, 320×180 base resolution scaled up
with integer scaling.

## Controls

| Action    | Keyboard          | Touch                         |
|-----------|-------------------|-------------------------------|
| Move      | WASD / Arrows     | On-screen D-pad, drag to steer (bottom-left) |
| Interact  | Space / Enter / Z | "A" button                    |
| Cancel    | Backspace         | "B" button                    |
| Pause     | Escape            | "Menu" button                 |
| Emote     | 1 / 2 / 3 / 4     | Four emote buttons            |
| Chat      | T                 | "Chat" button (top-left)      |

The on-screen touch controls and the keyboard drive the same input actions, and mouse
clicks act as touch (`emulate_touch_from_mouse`), so everything is testable on desktop.
The D-pad works like a joystick: touch it and it holds whichever direction your finger
points (by angle), keeping that direction even if your finger slides off the arrows, and
switching direction as you move — it only lets go when you lift your finger.
The touch controls anchor to the screen edges, so they stay in the corners on any phone
aspect ratio (D-pad bottom-left; the menu, emote, and A/B buttons on the right).
Pop-up dialogs (e.g. a connection error) scale with the screen too, so the message box and
its close button stay correctly placed at any resolution.

Face an NPC or an object and press **Interact** to talk; press Interact/Cancel again to
advance the dialogue. It closes after the last line, and you can't move while it is open.

Press **1**, **2**, **3** or **4** (or the on-screen emote buttons) to pop an emote — a heart,
a smile, a sad face or a yippie — above your character. Yippie also plays a dance on characters
that have the animation (currently Mimi). In multiplayer everyone sees it: the emote
is sent to the server and shown on every player's screen, then fades on its own after a moment.

Press **T** (or the on-screen **Chat** button) to type a short message (up to 60 characters).
It opens at the top of the screen so a phone keyboard can't cover it; **Enter** / **Send**
shows it in a speech bubble over your character for everyone, and **Escape** / **X** cancels.

## Playing: Solo, Host, or Join

From the main menu, **Play** opens the game screen with these options:

- **Solo Game** — single player.
- **Host Game** — start a server others on your network can join.
- **Join Game** — type the host's IP into the **Host IP** field, then join.
- **Play Online** — connect to a preconfigured dedicated server (its address is read from
  `config/server.cfg`, which is gitignored — copy `config/server.example.cfg` to create it), no IP
  typing needed.

Any of these drops you into a **lobby** where you **choose your character**. Characters
another player has already taken are greyed out, so no two players share one. Then:

- **Solo / Host** press **Start Game** to begin (Host starts the match for everyone in the lobby).
- A **client** either waits for the host to start, or — if it joined a game that's already
  running — picks a free character and presses **Enter Game** to drop straight in.

A game holds at most **5 players**, one per character. A host counts as one of them, so a
hosted game takes 4 more players and a dedicated server takes 5. Anyone joining a full game sees
**"Server is full (5 players max)"**.

### Multiplayer on the same Wi-Fi

1. On the host device, tap **Host Game** — the lobby shows **Your IP: `192.168.x.y`**.
2. On another device on the **same Wi-Fi**, tap **Join Game**, type that IP into the Host
   IP field, and join.

Everyone must be on the same router/subnet (guest networks and "AP isolation" block it).
Leaving the Host IP blank connects to `localhost`, handy for testing two windows on one PC.
Playing across *different* networks needs the host reachable from outside (port forwarding,
a dedicated server on a public host, or a VPN mesh); phone mobile-data hosting won't work
because carriers use CGNAT.

### Dedicated server

You can run a **player-less server** (it just hosts and simulates; clients drop in and pick
characters). Launch the game with the `--server` flag, e.g. headless on a spare PC/laptop:

```
godot --headless --path . -- --server
```

(The `--` matters — everything after it is passed to the game.)

#### Deploying to a Linux host / AWS EC2

`export_presets.cfg` includes a **Linux Server** preset (x86_64, dedicated-server, single
self-contained binary). Install the Linux x86_64 export templates, then export and run:

```
godot --headless --path . --export-release "Linux Server" ./vulny-view.x86_64
# copy vulny-view.x86_64 to the server, then:
chmod +x vulny-view.x86_64
./vulny-view.x86_64 --headless -- --server
```

To keep it running (auto-restart, start on boot) use the systemd unit at
`deploy/vulny-view-server.service` — its header has the install steps.

On **AWS EC2** specifically:
- Open **inbound UDP 8080** in the instance's **Security Group** (this is separate from the
  OS firewall, and is the most common reason a running server can't be reached — ENet is UDP).
- Attach an **Elastic IP** so the address survives stop/start, then put that IP in
  `config/server.cfg` (gitignored — never commit it) and re-export the client so **Play Online**
  connects to it.
- Restrict the **SSH (TCP 22)** inbound rule to your own IP ("My IP"), not `0.0.0.0/0`; only
  UDP 8080 needs to be open to everyone.
- A `micro` instance is plenty (the server is lightweight). Use an **x86_64** instance (t2/t3/…)
  to match the binary; for a Graviton (arm64) instance you'd export an arm64 build instead.

## Project layout

The project root is this `vulny-view/` folder. Main scene: `core/main/main.tscn`.

```
core/       App shell + shared singletons (Main, Session, GameManager, UIRoot,
			SceneRouter, Events bus, Modules helpers, CharacterRegistry, CharacterLobby)
gameplay/   Player & NPC entities (composed from Input / Movement / Animation /
			StateMachine child nodes), per-character player scenes, game modes, world spawning
network/    NetworkManager (ENet host/join)
levels/     Overworld.gd (level script), overworld.tscn (the whole map), interactables
ui/         menus (Main / Options / Pause / popup), the dialogue message box, emote popups,
			chat bubbles + chat bar, the edge-anchored touch controls (D-pad + buttons),
			the character-select lobby
data/       configs/ — settings persistence (user://settings.ini)
config/     server.example.cfg — template for the gitignored Play Online address file
assets/     character sprite sheets, world tileset, fonts, UI art, music
audio/      background music player
deploy/     vulny-view-server.service — systemd unit for the Linux dedicated server
```

Entities favor **composition**: a `Player`/`NPC` is a `CharacterBody2D` whose behavior
lives in child nodes (`Input`, `Movement`, `Sprite`, `StateMachine`). Movement is a
physics-free 16px grid step (tween-like `move_toward` + point-query collision + per-tile
reservation), not `move_and_slide`. Multiplayer is **server-authoritative**: the server
simulates movement and NPCs and replicates them to clients.

### Characters

Each selectable character (Mimi, Sisi, Riri, Prannu, Rara) is its own scene under
`gameplay/entities/player/characters/` — identical logic, different sprite sheet. They're
registered in `core/CharacterRegistry.gd`, which maps a numeric id to each scene. To add or
change a character, add its scene there and give the matching button a `character_id` in the
character-select scene.

### Editing the world

Edit the level directly in Godot: `levels/overworld.tscn` holds the outside and every house
floor (in separate regions of the same canvas, joined by door triggers), as stacked
`TileMapLayer`s painted with `assets/world/level.tres`. NPCs are `npc.tscn`
instances placed in the scene, each carrying an inline `NPCInputConfig` (movement type +
dialogue). Inspectable objects (signs, furniture, …) are invisible `interactable.tscn`
tiles placed over the map art; their lines live in the instance's
`messages` array. Player start positions are `SpawnPoint` markers under
`SpawnPoints/PlayerPoints`.

## Running

Open this folder in Godot 4.7 and press **F5**, or from a terminal:

```
godot --path .
```

See `../CLAUDE.md` for the headless verification commands and a detailed architecture guide.

## Building for Android

`export_presets.cfg` ships an **Android** preset as a starting point. Actual
builds need tooling that is **not** part of this repo:

- **Android**: install the matching Godot **export templates**
  (Editor > Manage Export Templates), the **Android SDK + a JDK**, and a debug keystore,
  then set their paths in **Editor > Editor Settings > Export > Android**. Build via
  **Project > Export > Android**. Multiplayer needs the **INTERNET permission** enabled in the
  preset (`permissions/internet=true`) — without it hosting/joining fails with "Could not create
  server". Toggling a permission requires a re-export + reinstall to take effect.

Open **Project > Export** once so Godot fills in every remaining default for each preset.

## Credits

- Music: 'Pixeltown' by Color Parade on #Uppbeat — https://uppbeat.io/c/color-parade
  (License code: YXVNQMD9JQP5I1K2)
- Font: Pixel Operator 8 — [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
