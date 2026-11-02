# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A top-down, grid-based (Pokemon-style) 2D mobile game built with **Godot 4.7** and **GDScript**,
targeting **Android**. Landscape orientation, Mobile renderer (`renderer/rendering_method="mobile"`),
base viewport **320×180** with integer scaling (`window/stretch/scale_mode="integer"`).

Art is **authored assets**, not generated at runtime: pixel-art character sprite sheets
(`assets/characters/*.png` sliced by `SpriteFrames` resources) and a `TileSet`
(`assets/world/level.tres`) built from tileset PNGs. The only runtime-drawn rectangles are the
**debug pathfinding overlay** in `levels/Overworld.gd::_draw_debug_grid()` (red = solid, green = free,
blue = patrol, cyan = target) — off by default; enable `debug_draw_grid` on the level root. It draws on
a high-z child node, since the level root itself draws underneath its `TileMapLayer`s.

The Godot project lives in the `vulny-view/` subdirectory (that folder is the project root Godot opens).
The `run/main_scene` is `res://core/main/main.tscn`.

The game is multiplayer: ENet **server-authoritative** movement (with client-side prediction +
interpolation), a networked **character-select lobby**, **drop-in joins**, a **headless
dedicated-server** mode, and its **Linux / AWS EC2** deployment. See **Multiplayer** below.

## Commands

The engine is **Godot 4.7.1**, which is usually **not on PATH**. Machine-specific executable paths
belong in `CLAUDE.local.md` (gitignored). On Windows, run headless checks from **PowerShell**, not
the Bash tool. Below, `$godot` stands for the Godot executable:

```powershell
# Open in the editor / play (F5 inside the editor)
& $godot --path vulny-view

# Import assets + compile all scripts, report parse/compile errors, then quit
& $godot --headless --path vulny-view --editor --quit

# Run the game headless for ~90 frames (surfaces runtime errors in _ready/wiring)
& $godot --headless --path vulny-view --quit-after 90

# Run as a headless, player-less DEDICATED SERVER (hosts + simulates; clients drop in).
# Note the `--` : everything after it is passed to the game, which is how --server is read.
& $godot --headless --path vulny-view -- --server
```

Benign output to ignore: "Unable to open Android 'build-tools' directory" (no export tooling) and
"ObjectDB instances were leaked at exit / resources still in use at exit" (normal on `--quit-after`).

There is no test framework. **Verification workflow** = the two headless commands above (grep the
output for `SCRIPT ERROR` / `Parse Error` / `Compile Error` / `Failed to load`) followed by a manual
`F5` playtest. Headless uses the dummy renderer, so it validates parsing, imports, `_ready()` wiring
and node-path resolution **only** — it cannot exercise input, movement feel, on-screen UI, or
**networking/replication**. Always say so when reporting results. Multiplayer specifically requires a
**two-instance playtest** (Host + Join). The `--server` launch is the one networking path that *can*
be smoke-tested headless (it boots, hosts, and loads the world with no client).

Android builds (the `Android` preset in `export_presets.cfg`) require external tooling not in this
repo: export templates + SDK/JDK + keystore. See `vulny-view/README.md`.

**Networking on Android needs the `INTERNET` permission** (`permissions/internet=true` in
`export_presets.cfg`). Without it the OS blocks socket binding, so `create_server()` fails with
"Could not create server" (and joins fail too) — permission changes only take effect after a
**re-export + reinstall**, not on the already-installed APK.

## Repository layout

```
core/       App shell & shared singletons
  main/       Main, Session, GameManager, Initializer, UIRoot (the $UI CanvasLayer)
  events/     Events.gd — global signal bus
  scene_router/  SceneRouter + TransitionLayer (fade in/out between levels)
  Modules.gd  GRID_SIZE, Vector2<->Vector2i grid converters, tile collider query, is_authority() peer guard
  CharacterRegistry.gd  int character-id -> PackedScene map (autoload)
  CharacterLobby.gd     replicated character-claim state for the lobby (autoload)
gameplay/
  entities/   Player, NPC, and the SHARED components CharacterInput / CharacterMovement / CharacterAnimation
  entities/player/characters/  Mimi/Sisi/Riri/Prannu/Rara — one Player-variant scene per character
  entities/states/  PlayerRoam/Message, NPCRoam/Message state scripts
  gamemodes/  GameMode base + NormalMode (the only mode)
  world/      World, SpawnManager, SpawnPoint, scene_trigger
  utilities/  State, StateMachine
network/    NetworkManager (ENet host/join autoload)
levels/     Overworld.gd (level script), overworld.tscn (the whole map: outside + every house floor), Interactable
ui/         menus/ (Main/Options/Pause/PopupBox), messages/ (MessageManager),
            controls/ (touch controls; controls.gd edge-anchors them + runs the D-pad virtual joystick),
            emotes/ (EmoteContainer), chat/ (ChatBubble + ChatInput),
            character select/ (CharacterSelect lobby + CharacterButton)
data/configs/  ConfigFileHandler (user://settings.ini persistence)
config/     server.example.cfg (template); server.cfg (gitignored) holds the Play Online address
deploy/     vulny-view-server.service (systemd unit for the Linux dedicated server)
assets/     characters/ (sprite sheets + SpriteFrames), world/ (tileset), controls/, fonts/, message box/, music and sounds/
audio/      music.tscn (global AudioStreamPlayer autoload)
```

**Autoloads** (`project.godot`, in order): `Music` (a scene — `audio/music.tscn`), `ConfigFileHandler`,
`Initializer`, `GameManager`, `Events`, `Modules`, `NetworkManager`, `CharacterRegistry`, `CharacterLobby`.

## Architecture

**Composition over inheritance for entities.** Both `Player` (each `gameplay/entities/player/characters/*.tscn`)
and `NPC` (`gameplay/entities/npc/npc.tscn`) are `CharacterBody2D` roots whose behavior lives in
**child nodes**, not the root script:
- `Input` — a `CharacterInput` subclass (`PlayerInput` / `NPCInput`): holds `direction`,
  `target_position`, the `walk_event_handler`/`turn_event_handler` signals, and (player) `wish_direction`.
- `Movement` — `CharacterMovement`: the actual grid stepper. Exports the live `is_walking` /
  `facing_direction`, the replicated mirror `sync_position` / `sync_walking` / `sync_facing`, and
  `simulate_only_on_authority` (true on both player and NPC scenes; see Multiplayer).
- `Sprite` — `AnimatedSprite2D` + `CharacterAnimation`: picks directional idle/turn/walk clips.
- `StateMachine` — a `Roam` state and a `Message` state.
- Players also have `Camera`, a state `MultiplayerSynchronizer` (the `sync_*` mirror), and
  `Input/InputSynchronizer`. NPCs have a `MultiplayerSynchronizer` too (see Multiplayer).

**Characters are per-character Player scenes, chosen via a registry.** There is no longer a single
`player.tscn`; each character (`Mimi`, `Sisi`, `Riri`, `Prannu`, `Rara`) is its own scene — identical
`Player.gd` + component wiring, differing only by `SpriteFrames`. `CharacterRegistry` (autoload) is the
single source of truth: `CHARACTERS: Array[PackedScene]` indexed by an **int `character_id`**, with
`get_scene(id)`, `is_valid_id(id)`, `count()`, and `DEFAULT_ID = 0` (Mimi). The id is what travels over
the network; both peers resolve it back to a scene through the registry. Keep the ids in sync with the
`character_id` exports on the buttons in `ui/character select/character_select.tscn`.

**Grid movement is physics-free stepping, not `move_and_slide`.** Despite the `CharacterBody2D` base,
`velocity` is never used. `CharacterMovement` (`gameplay/entities/CharacterMovement.gd`) steps between
**16px** tile centres with `position.move_toward(target, delta * GRID_SIZE * 4)`. Collision is a
**`PhysicsPointQueryParameters2D` point query** at the target tile (`is_target_occupied`), plus a
per-level **tile-reservation dictionary** (`Overworld.reserve_tile/release_tile`) so two movers can't
claim the same tile. The tile size lives in one place, **`Modules.GRID_SIZE`** (16) — use it, don't
redeclare a local `GRID_SIZE`.

**The world/level is a real TileSet, edited in the scene, not a text grid.** There is one level,
`levels/overworld.tscn` (script `Overworld.gd`): the outside **and** every house floor, laid out in
separate regions of the same canvas and connected by `scene_trigger` doors that teleport between
spawn tags. Its `TileMapLayer`s (`Ground`/`Trees`/`FirstFloor`) use `assets/world/level.tres`, plus:
- `SpawnPoints/PlayerPoints/*` — `SpawnPoint` markers (`Marker2D` + `spawn_id`/`spawn_tag`); looked up
  by `Overworld.get_spawn_point_by_tag("PlayerPoints", tag)`.
- `Boundaries` — invisible `StaticBody2D` walls.
- `NPCs` — `npc.tscn` instances placed directly (each with an inline `NPCInputConfig`).
- `Interactables` — invisible `interactable.tscn` tiles over objects drawn in the map art; `Triggers` — `scene_trigger` door/area transitions.
- `Overworld` builds an `AStarGrid2D` for NPC patrol pathing **on first use** (`get_grid()`, server-only in
  practice), sized from the union of every `TileMapLayer`'s used rect — the house floors are laid out
  far from the outside area (y ≈ 1100–1850, some at negative x), so never hand-enter bounds.

**State machine gates `_process`.** `StateMachine` (`gameplay/utilities/StateMachine.gd`) enables
`_process` **only on the current state** (`set_process(child == current_state)`); `change_state` runs
`exit_state`/`enter_state`. `Roam` reads input and drives movement; `Message` handles dialogue. The
**`Events.message_box_open(bool)`** signal (the one live signal on the `Events` bus) drives the
`Roam ↔ Message` transitions for both player and NPCs — never change those states directly, emit through
the message flow.

**Input is polled inside states and dual-driven.** Actions `interact`, `cancel`, `pause`, and the
`emote_one`…`emote_four` actions (`project.godot [input]`; emotes on keyboard **1**–**4**)
are bound to **both** the keyboard **and** `TouchScreenButton`s in `ui/controls/controls.tscn` (via their
`action` property; the buttons carry no per-button scripts). The `move_up/down/left/right` actions are
keyboard-bound too, but on **touch** they are driven by the **virtual D-pad** (see below), not buttons.
`emulate_touch_from_mouse` makes the touch controls work on desktop. `PlayerRoamState` polls actions with
`Input.is_action_*` in `_process` (interact/emote) and `_physics_process` (movement) — it never handles
raw `_input` itself.

**Touch controls anchor to the live screen edges (`controls.gd`).** The touch elements are
`Node2D`s (no anchors), authored in the 320×180 base canvas, but `display/window/stretch/aspect =
"expand"` grows the canvas past that on non-16:9 phones (extra space added at the right/bottom,
top-left origin fixed) — so the right/bottom ones would drift inward. `controls.gd` (on the
`Controls` root) captures each element's authored position at `_ready`, then on `resized` re-pins the
right-edge buttons (`A`/`B`/`Menu` + the emote column) and bottom-edge ones (`A`/`B` + the D-pad arrows)
to the current viewport edge, preserving each one's designed margin; left/top-anchored ones (D-pad x)
are left alone. The emote **backgrounds** (`NinePatchRect`s) hug the right edge under the Menu button via
Control anchors, matching their fixed-position emote buttons at any resolution.

**The D-pad is a virtual joystick, not buttons (`controls.gd`).** The four arrows (`Up`/`Down`/`Left`/`Right`)
are visual-only `Sprite2D`s; `A`/`B`/`Menu`/emotes stay `TouchScreenButton`s. `controls.gd._input`
captures a touch that starts within `DPAD_CAPTURE_RADIUS` of the pad centre (the centroid of the four arrow
origins, recomputed live so it follows the edge-anchoring), then holds a cardinal `move_*` action chosen by
the finger's angle from centre (dominant axis = 45° sectors) via `Input.action_press`/`action_release`. The
direction keeps holding as the finger slides — even off the arrows — switches when it crosses a sector
boundary, and releases only when the finger lifts. Capture is gated to a visible HUD (so it can't swallow a
menu touch behind a hidden `HUDLayer`), but release is always processed so a direction can't stick. It must
use `_input` (not `_unhandled_input`) and the `Controls` root sets `mouse_filter = ignore`, because a
full-rect `Control` otherwise swallows the pointer event in the GUI phase before `_unhandled_input` runs.
The same `expand` trap bites `Control`-based UI that mixes anchor styles: in the `PopupBoxLayer`
(`main.tscn`) the box and label use **proportional** anchors (they scale/re-centre with the screen),
so the **X cancel button** must use proportional anchors too — it was on fixed pixel offsets and drifted
out of the box's corner on non-16:9 screens until re-anchored to match.

**Dialogue flows through `MessageManager`.** `PlayerRoamState.get_interact_input()` point-queries the
faced tile; a `Interactable` → `play_message()`, an `NPC` → `play_message(facing)`. Both call
`MessageManager.play_text([...])` (`ui/messages/MessageManager.gd`, a node exposing a `static var
instance`), which types text char-by-char into a `RichTextLabel` inside a `NinePatchRect` box and emits
`Events.message_box_open`. `PlayerMessageState` advances lines on `interact`/`cancel`. Dialogue content
is authored inline: `Interactable.messages` and `NPCInputConfig.messages` (`Array[String]`) — there are
no `.tres` dialogue files. (Interact/dialogue is currently local-only, not networked.)

**Emotes are server-authoritative (unlike dialogue).** Each player scene carries an
`EmoteAnchor` (a `Marker2D` above the head) with a hidden `EmoteContainer` child
(`ui/emotes/emote_container.tscn` + `EmoteContainer.gd`), wired to the `Roam` state's
`emote_container` export. Pressing `emote_one`…`emote_four` on the owning client runs
`PlayerRoamState.get_emote_input()` → `_request_emote(name)`. Because an emote is a **one-shot
event** (not replicable state), it flows through RPCs rather than a `MultiplayerSynchronizer`:
solo calls `EmoteContainer.play_emote(name)` directly; multiplayer does
`request_emote.rpc_id(1, name)` (`any_peer, call_local` — `call_local` lets the host, peer 1, send
it to itself). The server rebroadcasts `play_emote.rpc(name)` (`authority, call_local`), which sets
the sprite (`heart`/`smile`/`sad`/`yippie`) and shows the box on **every** peer; each peer's own `Timer`
hides it after 2s. `get_emote_input()` no-ops if `emote_container` is null, so a character scene
without the emote nodes wired won't error.

**The yippie emote also dances.** `play_emote("yippie")` calls `CharacterAnimation.play_yippie(DISPLAY_TIME)` on
the player's `Sprite`, on every peer. It plays the `yippie` animation and hops the **sprite** (not the body, so
the grid position is untouched) up 1px on every odd frame via `frame_changed`. It ends after 2s; any walk or turn
animation replaces it sooner. It is skipped mid-step and for a character whose `SpriteFrames` lacks `yippie`
(currently only Mimi has it), and that character still gets the emote box.

**Overhead chat bubbles follow the emote path.** Each player scene has `EmoteAnchor/ChatBubble`
(`ui/chat/chat_bubble.tscn` + `ChatBubble.gd`). The HUD's `ChatInput` (`ui/chat/`, under
`UI/HUDLayer`) opens a text bar at the **top** of the screen (so the phone keyboard can't cover it)
via its Chat button or the `chat` action (**T**), then calls the local player's `ChatBubble.say()`.
Multiplayer: `request_say.rpc_id(1, text)` (`any_peer, call_local`) — the server checks the sender
owns that player, rate-limits (1/s), re-sanitizes (control chars stripped, 60-char cap) and
rebroadcasts `show_message.rpc(text)`; solo shows locally. Text goes in a plain `Label` (no BBCode
injection). Bubble and emote share the above-head spot — showing either hides the other.
While typing, **`GameManager.chat_open`** makes `PlayerRoamState` ignore movement / interact / emote
input (they're polled, so keys would still fire); it's cleared only once `interact`/`cancel` are
released, because **Enter = interact** and **Backspace = cancel**.

**Boot flow.** `core/main/Main.gd` (root of `main.tscn`) wires the menu + `CharacterSelect` + `NetworkManager`
signals, preloads the `normal_mode` + `overworld` scenes (so the TileSet build happens behind the menu),
then `_boot_game`: if the process was launched with `--server` it starts a **dedicated server** (no menu);
otherwise it shows the main menu. `UIRoot` (the `$UI` CanvasLayer) owns the menu / character-select /
HUD / message / popup layers (`show_main_menu` / `show_character_select` / `show_game_hud` /
`show_message_layer` / `show_popup_box` / `hide_all`).

**World loading and player spawning are DECOUPLED** (this is the core of the current session flow — see
Multiplayer for why). `Session.start_session` only instantiates `world.tscn` + `NormalMode` and runs
`SceneRouter.transition_to_level` (`fade_out → world.load_level → mode.setup_match → await setup_finished
→ fade_in`). It spawns **nobody**. Spawning is a separate, explicit step triggered later on Start/Enter
via `Session.spawn_local_player()` (host/solo) or the `Session.request_spawn` RPC (clients).

**Settings persistence.** `ConfigFileHandler` (`data/configs/`) reads/writes `user://settings.ini`
(`audio` + `display` sections). `Initializer` applies them to the engine at boot (master-bus volume,
window mode); `OptionsMenu` edits them live.

## Multiplayer (server-authoritative, ENet)

`NetworkManager` (`network/NetworkManager.gd`) is the ENet host/join autoload. `SERVER_PORT = 8080`
(**UDP** — ENet). `create_server(port, host_is_player = true)` / `create_client(host_ip = "localhost", port)`,
`is_hosting_game`, and `get_local_ip()` (best-effort LAN IPv4 for the host to display). Signals: `server_created`,
`client_connected`, `connection_failed(text, show_close)`, `cant_create_server(text, show_close)`,
`peer_connected(id)` / `peer_disconnected(id)`, `server_disconnected`.

### Player cap: `NetworkManager.MAX_PLAYERS` = 5

No server ever holds more than **5 players**, counting a playing host. The number matches the five
characters and `world.tscn`'s `MultiplayerSpawner.spawn_limit` (5) — **change all three together**.
It is enforced in layers:

- **ENet:** `create_server` sets the client slots to `MAX_PLAYERS - 1` for a playing host (the Host button)
  or `MAX_PLAYERS` for the dedicated server (`create_server(SERVER_PORT, false)`), and gives ENet **one
  spare connection**.
- **"Server is full":** `NetworkManager._peer_connected` counts clients (minus any already being rejected);
  a peer over the limit is recorded in `_rejected_peers`, sent `_server_full` (the client clears its peer and
  emits `connection_failed("Server is full (5 players max)")`, so `Main` tears down the half-loaded world
  and `UIRoot` shows the popup), and disconnected after `REJECT_DELAY` (0.5 s). It is never announced via
  `peer_connected`. A further simultaneous joiner past the spare slot is refused by ENet and just sees
  "Failed to join server".
- **Server-side request guards:** `Main._request_join`, `CharacterLobby._request_pick` and
  `Session.request_spawn` ignore peers where `NetworkManager.is_peer_rejected(id)` — those RPCs are
  `any_peer`, so a modified client could call them directly.
- **`SpawnManager.add_player`** refuses to create a body once `World/Players` holds `MAX_PLAYERS`.

### Session flow: load-on-connect, spawn-on-command

The order matters and is deliberate. `MultiplayerSpawner` replicates already-spawned players to a peer
the instant it connects; if that peer hasn't loaded its `World` yet, those spawns land on missing nodes
(the classic "spawner null / node not found" errors, and existing players never appear). So **every peer
loads its world before it can receive players, and spawning happens afterwards:**

- **Solo:** `Solo → Main._on_solo_requested → _load_world(false) → CharacterSelect.enter_lobby(solo)`.
- **Host:** `Host → NetworkManager.create_server → server_created → Main._on_server_created →
  _load_world(true) → enter_lobby(host)`.
- **Join:** `Join(ip) → Main._on_join_requested → _load_world(true) FIRST → NetworkManager.create_client(ip)`.
  Loading before connecting is what makes drop-in joins work.
- **Spawning:** host `Start` → `Session.spawn_local_player()` + `_begin_match_remote.rpc()` (waiting
  clients call `Session.request_spawn`); a drop-in/dedicated-server client `Enter Game` → `request_spawn`.
  On the server, `NormalMode.add_player → SpawnManager.add_player` resolves the `character_id` via
  `CharacterRegistry`, spawns the scene under `World/Players` (named by peer id, set before `add_child`),
  and the `MultiplayerSpawner` replicates it. `SpawnManager` **de-dupes** character ids server-side as a
  safety net (reassigns to the first free id) and enforces **one player per peer** — it ignores a
  `request_spawn` for a peer that already has a body (that RPC is `any_peer`, so an untrusted client
  could otherwise spam it) — and the `MAX_PLAYERS` cap (see Player cap above).

### Character-select lobby

The character screen is a **connected lobby**. Before choosing a mode it shows only Solo/Host/Join and a
**Host IP** field; the character row appears once you're in a lobby.

- `CharacterLobby` (autoload) holds the authoritative `taken` map (`character_id -> peer_id`), replicated
  to every peer via RPC. `pick(id)` claims (offline/solo → local; host → direct; client → server RPC); the
  server rejects collisions, releases a peer's old pick, syncs a fresh joiner on connect, and frees a claim
  on disconnect. `taken_changed` drives the UI.
- `CharacterButton` carries a `character_id` and draws hover / selected / **taken** (greyed + disabled)
  borders. `CharacterSelect._refresh_characters` rebuilds all buttons from the synced map, so a character
  another player owns is greyed out — **duplicate prevention lives in the UI.**
- Lobby roles: **solo/host** get a "Start Game" button (enabled once a character is picked); a **drop-in**
  client gets "Enter Game"; a normal waiting client just shows "Waiting for host…". The **host lobby shows
  its LAN IP** (`get_local_ip()`) so a client on the same Wi-Fi can type it into the Join field.

### Movement is server-authoritative with client-side prediction + interpolation

- Body/root `MultiplayerSynchronizer` stays owned by the **server (peer 1)**; the `Input` subtree (incl.
  `InputSynchronizer`) is owned by the **controlling client** (`Player._enter_tree` sets `$Input`
  authority from the name). Never call `set_multiplayer_authority` recursively on the whole player — it
  clobbers this split.
- The client writes only its held direction into `CharacterInput.wish_direction`; the `InputSynchronizer`
  replicates it to the server. `PlayerRoamState` splits `capture_input()` (owning client) from
  `simulate()` (reconstructs tap/hold/turn from `wish_direction`), both moved to **`_physics_process`**
  for a fixed, jitter-free timestep. `StateMachine` gates `set_physics_process` in lockstep with
  `set_process`, so movement still freezes during the `Message` state.
- **The server's authoritative state travels in a separate mirror, not the live fields.** Replicating
  `position`/`is_walking`/`facing_direction` directly would clobber a predicting client, so
  `CharacterMovement` exports **`sync_position` / `sync_walking` / `sync_facing`** (server → all) that the
  server writes each frame via `_publish_state()`; the live fields stay code-controlled on every peer.
- **`CharacterMovement.is_simulating()`** = server (authoritative) **or** owning client (client-side
  prediction) **or** solo. Those peers run `walk()` locally; the owning client predicts its own movement
  from its own input with no round-trip lag, then `_reconcile()`s against `sync_position` — hard-snapping
  on a big divergence (spawn / area-transition teleport / hard misprediction) and otherwise only
  correcting at rest, so an in-flight step never rubber-bands. Every other (pure remote) copy runs
  `_interpolate()`, easing toward `sync_position` (`INTERP_RATE`, hard-snap past `SNAP_DISTANCE` = 2
  tiles) so it never snaps between packets. Remote copies animate from `sync_walking`/`sync_facing` in
  `CharacterAnimation._process`; simulating copies (incl. the predicting client) use the event-driven
  animation path.
- Each peer marks only **its own** player's camera `current` and sets `GameManager._player`.

### NPCs are server-authoritative and replicated

NPCs are static nodes in the level (loaded on every peer), but they are **simulated only on the server**
(`NPCRoamState._process` is gated to the authority; `npc.tscn` sets `simulate_only_on_authority = true`)
and replicated via a `MultiplayerSynchronizer` using the same mirror fields as players
(**`sync_position` / `sync_walking` / `sync_facing`**), so clients **interpolate** them smoothly too
(there is no prediction for NPCs — no controlling client). To avoid sending NPC state to a peer that
hasn't loaded the level yet, NPC synchronizers start with `public_visibility = false`; the server calls
`Session.reveal_npcs_for(peer)` (from `Main._request_join`) once that peer is loaded. `NPCInputConfig`
(a `Resource`) selects `movement_type` (`STATIC` / `PATROL` / `WANDER` / `LOOK_AROUND`) with per-type
params. NPCs are in the `"npc"` group.

### Dedicated server (`--server`)

Launching with `--server` boots straight into a **player-less headless server**: `Main` creates the
server, loads the world, spawns **no** host player, and shows no menus. It sets `_match_started = true`
so the world is live immediately — every client that connects is routed as a **drop-in** (picks a
character, presses Enter Game), since there is no host to press Start. Hosting from a phone via the
**Host button** is unchanged and still spawns a host player.

### Deploying the dedicated server (Linux / AWS EC2)

`export_presets.cfg` has a **`Linux Server`** preset (`preset.1`): `platform="Linux"`,
`binary_format/architecture="x86_64"`, `dedicated_server=true`, `binary_format/embed_pck=true` (a single
self-contained `vulny-view.x86_64`, no separate `.pck`). It needs the Linux x86_64 export templates
installed (Editor → Manage Export Templates); the target is an **AWS EC2 x86_64** instance (t2/t3/…). For
a Graviton (arm64) instance, add an arm64 preset instead.

```bash
# Export (from vulny-view/) — the preset's export_path is ./vulny-view.x86_64 (project root)
godot --headless --path . --export-release "Linux Server" ./vulny-view.x86_64
# On the instance
chmod +x vulny-view.x86_64 && ./vulny-view.x86_64 --headless -- --server
```

Exported builds (`*.apk`, `*.x86_64`, `*.pck`, …) are **gitignored, never committed** — the server binary
is copied to the instance by hand with `scp` (e.g. `scp vulny-view.x86_64 <user>@<elastic-ip>:~/`).

Run it under systemd for auto-restart / boot-start — a ready unit is at
`deploy/vulny-view-server.service` (its header has the install steps). Two AWS gotchas: open **inbound
UDP 8080** in the **EC2 Security Group** (separate from the OS firewall; ENet is UDP, the #1 reason a
running server is unreachable), and give the instance an **Elastic IP** so its address survives
stop/start, then put that IP in `vulny-view/config/server.cfg` (see below) and re-export the client so
**Play Online** points at it. Restrict the Security Group's **SSH (TCP 22)** rule to your own IP ("My IP"),
not `0.0.0.0/0` — only the game port needs to be open to the world. A minimal AMI may need a few shared libs before the binary runs — check with
`ldd vulny-view.x86_64`.

### LAN / internet reachability

Same-Wi-Fi play works out of the box: the host reads its IP off the lobby, the client types it into the
Join field, `create_client(ip)` connects (a blank field falls back to `localhost` for same-machine
testing). `create_server` binds all interfaces, so no server-side change is needed. For a fixed
dedicated server, the **Play Online** button connects to `NetworkManager.server_address` so players don't
type an IP. That address is **never committed**: it's read at startup from `res://config/server.cfg`,
which is **gitignored** (copy `config/server.example.cfg` to create it) and packed into the Android
build by its export `include_filter`. If it's missing or blank, Play Online shows "Online server not
configured" (it must not fall through to `create_client("")`, which would mean `localhost`). The address
is still visible to anyone who unpacks the APK or watches traffic — it's public-to-players by nature;
the protection is the locked-down Security Group, not secrecy. Play across different networks needs the host
reachable from outside (port-forwarding / a dedicated server on a public host / a VPN mesh); mobile-data
hosting is blocked by carrier CGNAT.

### `Modules.is_authority(node)` — null-peer-safe authority check

`Node.is_multiplayer_authority()` calls `get_unique_id()` internally, which **errors when there is no
multiplayer peer** (offline/solo, or a world loaded before a client has connected). All per-frame
authority checks (`CharacterMovement`, `CharacterAnimation`, `NPCRoamState`, `PlayerRoamState`,
`SceneTrigger`) go through `Modules.is_authority(node)`, which treats "no peer" as **local authority**.
Prefer it over calling `is_multiplayer_authority()` directly in any code reachable with no peer.

## Gotchas / known rough edges

- **At most 5 players** (`NetworkManager.MAX_PLAYERS`), including a playing host, so a phone host takes
  4 clients and the dedicated server 5. Raising it means raising `MultiplayerSpawner.spawn_limit` in
  `world.tscn` and adding characters (more players than characters would share the default one).
- **Host shares peer id 1 with the server**, so a phone-host's own player never exercises the replication
  path — always test networking with a real second (client) instance.
- **Never load-then-connect out of order for a join.** The client must `_load_world()` *before*
  `create_client()`, or the `MultiplayerSpawner` catch-up fails and existing players won't appear.
- **Replicated node paths must match exactly on every peer.** `Session.shutdown_session` detaches
  (`remove_child`) the `World`/mode before `queue_free`, because a session restarted in the same frame
  (e.g. a retried join) would otherwise get an auto-renamed `@World@N` and every `MultiplayerSpawner`
  spawn would silently fail on that peer. `Main` also locks the mode buttons while Solo / Host / Join is
  setting up (`_busy`) and tears a half-loaded join down on `connection_failed`.
- **Global signals reach every peer's copy of every player/NPC.** `Events.message_box_open` is
  heard by all player nodes on a peer — on the host that includes every client's server-simulated
  body. Only the local player (`state_owner == GameManager._player`) enters `Message`, and Message
  states only return to Roam if they're the current state; otherwise the host reading a sign
  would stop the server simulating everyone.
- **Pause only freezes the tree solo.** In multiplayer `Session.set_paused` just shows the menu
  (the host is the server — pausing the tree would freeze every player); `PlayerRoamState` ignores
  local input while `is_paused`, and `pause_menu.tscn` is `process_mode = Always` so its buttons
  work with the tree running. `shutdown_session` clears `is_paused` and calls
  `MessageManager.reset()` (static; outlives the session) so a mid-dialogue quit can't leave a
  stuck box.
- **Never set body/root multiplayer authority recursively** — it re-clobbers the client-owned `Input`
  split. The Player scene body stays at the spawner's server default.
- A **dedicated server has no host player and never presses Start**, so a client on it never "waits" —
  everyone drops in independently. A phone-host's *waiting* client that never picks a character before the
  host hits Start spawns with the default (`DEFAULT_ID` = Mimi), reassigned if that id is taken.
- `NetworkManager.get_local_ip()` is a heuristic (first private `192.168.`/`10.`/`172.16–31.` address);
  it can pick the wrong adapter on a machine with VPN/virtual NICs. Same-subnet only (guest networks /
  AP isolation block it).
- `GameplayHUD` (under `UI/HUDLayer`) is an empty placeholder. `gdscript/warnings/unused_signal=0` is set
  project-wide, so an unused signal won't warn — grep before assuming one is live.
- Interact/dialogue text is **local-only**, but the NPC's *facing + roaming hold* is networked: on a
  client, `NPC.play_message` sends `_start_talk.rpc_id(1, dir)` (server turns the NPC and
  `NPCRoamState` pauses while `is_held_by_remote_talker()`), pins the talk facing locally via
  `CharacterAnimation.facing_override` (a remote copy otherwise redraws from `sync_facing` every
  frame, snapping the turn back), and sends `_end_talk` when its message box closes (also cleared on
  peer disconnect, and a hold lapses after `TALK_HOLD_TIMEOUT` = 30s so a backgrounded phone can't
  freeze an NPC; the server only accepts cardinal directions). Turning locally on a client never sticks — always go through the server.
