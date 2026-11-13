# Handoff: original Joy-Cons as motion input for the Mac host

## Next action

Get a runnable Resort build again, then play the Boxing round. The app bundle's shader
libraries are chain `3856a9225d68` and the tree's chain is `6832d4cf829f`, and the host loads
only libraries of its own chain version, so the current tree's host cannot use the app as it
stands; its `dmhost` also predates the still-offset change. Rebuild with
`scripts/build_ipa_from_nsp.py "/Volumes/Segan/TheSources/Nintendo Switch Sports Resort
[04008E001F098000][v65536].nup" --platform mac --work-dir /Volumes/X9BS/resort` (11,062
shaders; `/Volumes/X9BS/resort/shader/cache/cas.db` should let the Metal compiles be reused),
then either run `/Volumes/X9BS/resort/tools/dmhost` with the command the script prints, or
re-pack the app with `--platform mac-app`. Play one Boxing round with `DM_JC1_LOG=2`, hands
still at the end, and read the host's stream (|acc| and rotation) against what the avatar does.

## Goal

Original (Switch 1) Joy-Cons working as motion input for the Mac host. Proven in Nintendo Switch
Sports Resort, profile `dm/games/04008E001F098000`.

## Why this was needed

macOS's GameController driver presents a paired L+R as one `GCController` (`productCategory`
"Nintendo Switch Joy-Con (L/R)") with NO `GCMotion` object, and its HID report 0x30 arrives at
~60 Hz with the IMU fields zeroed. The host therefore had no orientation until it enabled the
sensor itself. This was verified with standalone probes before any host change was made.

## What was built

All Mac-only, IOKit.

### `dm/host/pad_jc1.h` (new, pure C)

- 49-byte report 0x30 decode; three 12-byte IMU samples at offset 13 (accel XYZ then gyro XYZ,
  int16 LE, 5 ms apart, third newest).
- Chip axes: +X along the controller toward its top, +Y short axis, +Z out of the face on the left
  Joy-Con and out of the back on the right. Mapping to the host's Switch frame is (-Y,+X,+Z) for
  the left and (+Y,+X,-Z) for the right, then negated, because the host wants the gravity
  direction, not the accelerometer's specific force. The gyro uses the same rotation, in radians/s.
- Subcommand output report 0x01 builder: id, rolling counter, 8 neutral rumble bytes, subcommand,
  up to 38 argument bytes.
- SPI 0x6020 IMU calibration parse: 4 groups of 3 int16 (accel origin, accel coeff, gyro origin,
  gyro coeff). Accel scale 4/(coeff-origin) G per count. Gyro scale is 816/(coeff-origin)
  (accurate at +/-2000 dps) or 936/(coeff-origin) (saturation-free), choosing whichever lands
  nearest the part's measured 0.061 deg/s/count, because the units encode the coefficient in
  either scheme. Gyro origin is the still offset.
- Sample clock: the newest sample is min(clock, arrival), the clock advances 15 ms per report and
  slews a quarter toward the arrival, samples within a report are 5 ms apart, and samples at or
  before the last emitted one are skipped, so an early report delivers fewer samples instead of
  out-of-order ones.

### `dm/host/pad_jc1_mac.h` (new, Objective-C header)

- `IOHIDManager` matching 0x057E:0x2006 (left) and 0x057E:0x2007 (right); skips
  `kIOHIDGCSyntheticDeviceKey` devices.
- Opens nonexclusively (`IOHIDDeviceOpen`, `kIOHIDOptionsTypeNone`) so macOS keeps the pad,
  buttons, sticks and rumble.
- Handshake sends output report 0x01 with subcommands 0x02 (device info), 0x03/0x30 (standard full
  mode), 0x40/0x01 (EnableIMU), then SPI read 0x10 of 0x6020 length 0x18, 60 ms apart; parses 0x21
  replies.
- Feeds each Joy-Con's own samples with `dm_motion_set_joy(pad, side, ...)` and the merged stream
  with `dm_motion_set_hid(...)` from the chosen side.
- A 1 Hz dispatch timer re-sends the handshake when a controller has no live IMU for a second.
- Logs only with `DM_JC1_LOG` (1 = handshake/calibration/first report, 2 = one per-side frame line
  a second). `DM_JC1=0` disables. `DM_JC1_SIDE=L|R` picks the merged stream's side (default: the
  right of a pair, a left Joy-Con alone).

### `dm/host/hle_hid.c` and `dm/host/dm_input.h`

- New `dm_joy_motion(int pad, uint32_t sides)` and `g_joy_wide` (declared in `dm/host/dm_input.h`).
- `six_stream`, for a whole pad the game is shown as JoyDual (`kind_style(...) == STYLE_JOYDUAL`),
  serves each handle from that Joy-Con's own stream by handle device (0 left, 1 right) when its
  side bit is in `g_joy_wide`. A side attached without its own stream falls back to the pad's
  merged stream, so one Joy-Con alone drives both handles.
- Buttons, sticks, player slot and rumble stay with GameController.

### `dm/host/front_mac.m`

Includes the transport, adds `jc1_pad_player(GCController *)` (`g_merge ? 0 : pad_slot_of(...)`) and
calls `dm_jc1_start(jc1_pad_player)` in `pads_start()`.

### Tests

- `dm/host/tests/t_jc1.c` (new): output report bytes, SPI parse in both encodings, left/right frame
  signs, duplicate counter, free fall after live, jitter monotonicity with early and late arrivals.
- `dm/host/tests/t_hid.c`: gained `t_joy_motion_wide` (5 checks).
- Both registered in `dm/host/tests/Makefile`.

## Hardware evidence

Mac, macOS 27.2, Nintendo Switch Sports Resort.

- Both Joy-Cons accepted the handshake; 49-byte reports; factory IMU calibration read.
- Flat on the desk, both halves report the same gravity: left +0.01 -0.06 -1.04, right
  +0.02 -0.06 -1.01.
- Archery starts and can shoot: the game's own orientation gate (buttons facing inward) passes.
  Thumb Wrestling and Bowling work; Tennis worked before the per-side change and has not been
  retested since.
- Boxing (two-handed): fine at first, then the avatar throws punches while the player is still.
  After the round, with the controllers at rest, the host's stream was clean (|acc| 1.00-1.02 G,
  rotation under 1.1 deg/s on both sides). That rules out jitter at rest; whether the transport
  drifts the game's fusion during motion is NOT established.
- One mid-session dropout: `controller 'Joy-Con (L/R)' disconnected: player 1 (npad 0) is free`,
  then `controller connected: Joy-Con (R) (no extended gamepad profile: not used)`. Pressing + on
  the controller brought it back (a button press wakes a dropped Joy-Con). Right Joy-Con RSSI was
  -77; battery/Bluetooth suspected; the user was advised to charge.
- Raw stream measurements: report rate ~60-67 Hz, three samples per report 5 ms apart; real
  punches reached 9.9 G and 18 rad/s; arrival lag p50 6-9 ms, max ~68 ms.

## Last change: the gyro's still offset (played, did not fix Boxing)

The gyro-scale normalization went first: the left unit's stored coefficient was 0x3BE7 (15335)
against the right's default 0x343B (13371), the 936/816 ratio, so with one constant the left
integrated 13% slow (0.0532 against the part's 0.0610 deg/s per count). Normalized, both read
0.0611/0.0611/0.0610 (left) and 0.0610/0.0609/0.0610 (right). A round played with it still had
the avatar punching while the player was still, so the scale was not the cause.

The still offset came next: the factory origin is close but not the unit's own (the left read
5/25/2 counts against a rest offset of tens), so the host now learns the controller's own offset
from a second of near-constant samples, as the Switch 2 transport does. Measured residuals 11/-3/-7
counts on the left and 4/2/4 on the right. **Not yet played**: this is the round the next action
asks for.

## Open questions

1. ~~Does the gyro-scale normalization stop the boxing phantom punches?~~ Answered: no. The still
   offset is the next cause taken off, and its round is the next action.
2. Why did the combined pad disconnect mid-session (battery? macOS pairing?) and why does a lone
   Joy-Con arrive with no extended gamepad profile and get ignored by the front end?
3. Should a pair's two sensor frames be common or per-device? A flat pose agrees on both; mirrored
   hand poses read mirrored x, which is physically expected and passed archery.
4. Rumble still goes through GameController haptics (per side), not the transport; it is untested
   as a cause of IMU feedback.
5. iOS is not supported (IOKit).

## Second game: Splatoon Raiders (done — motion aiming works)

`/Volumes/X9BS/splatoon-raiders` holds the dump folder's build
(`0400380020056000_build`, chain `6832d4cf829f`, all 27,192 shaders) and
`README-validation.md`. Its host is current: the Joy-Con code and the still-offset change are in
it.

**Answer: the game reads motion every frame and acts on it.** A 7 minute session with a left and
a right original Joy-Con aimed cleanly and 1 to 1; the game called `GetSixAxisSensorStates`
30,400 times (1.16 a frame) and never the npad IMU API, so the SDK fusion that over-samples the
stream in Sports Resort is not in this game's path. Transport peaks 444 deg/s (left) and 484
deg/s (right) against 1.27 rev/s handed to player 1, no `[RED]` line, frame p50 16.8-21.2 ms,
GPU p50 9.2-13.3 ms.

It is one full-key npad here (the game supports FullKey | Handheld | JoyDual, 0x7), so its single
six-axis handle carries the pair's merged stream, the right half; `DM_JC1_SIDE=L` picks the left.
A Joy-Con's own stream goes unread by that handle.

To run it again:
`sh /Volumes/X9BS/splatoon-raiders/0400380020056000_build/run/play-motion.sh`
(it sets `DM_JC1_LOG=2 DM_MOTION_LOG=1 DM_HLECOUNT=…` and tees to `logs/playtest-motion.log`;
`DM_JC1_SIDE=L sh …` switches the merged side). Do not write `B=…` and `DM_ROOT=$B` in one
command: `$B` expands before the assignment applies.

## Verification state

- The whole host suite passes on the branch head (`make -C dm/host/tests GAME=04008E001F098000 run`,
  0 failed), run for both `fde4adb2` and `835196d9`; `t_jc1` and `t_hid` (463 checks) included.
- **PR #4's red checks are main's, not the branch's.** `clang-tidy (ratchet)` fails on 5 new
  findings in `dm/gfx/tests/*.m` under LLVM 23.1.4, and "Host unit tests" fails `t_save_sync`'s
  "both changed: the report says conflict, with the cloud's device". Origin/main's own runs
  (`43397483765`, `43397483755` at `b5150895`) fail on exactly those two.
- `regress.py check --games` could not run on this machine: no local game has a Mac build.

## Before the pull request

- Run the full host suite: `make -C dm/host/tests GAME=04008E001F098000 run`.
- Add the finding once, as a mechanism entry in `docs/reference/services.md` in the repository's
  Symptom / Cause / Fix / Found on format.
- Regenerate `docs/agents/symptoms.md` with `python3 dm/tools/docs_symptoms.py`.
- Add one line under "Found on this game" in `dm/games/04008E001F098000/README.md`.
- Document `DM_JC1`, `DM_JC1_SIDE` and `DM_JC1_LOG` in the Input row of `docs/development.md`.
- Run `scripts/regress.py check --games` on the five local games that `scripts/regress.py impact`
  names as most likely reached, and put its report in the PR. The only cross-game surface is the
  new `six_stream` branch in `dm/host/hle_hid.c`, which is inert unless `g_joy_wide` is set by the
  new transport.
- Do not include `.gitignore` in the commit: its change (`./.rnsk-memory`) predates this work.
- Commit only when asked, with `git -c user.name=seedds -c user.email=seedds@gmail.com commit`.
  No `Front-ends:` line is needed: the change adds a host API and Mac front-end behaviour that the
  in-tree front end already uses (see `docs/frontends.md`, "Following main", for when one is).
- The local app bundle `/Volumes/X9BS/Nintendo Switch Sports Resort.app/Contents/MacOS/dmhost`
  currently holds a development build; the original is `dmhost.orig` beside it. Restore it or leave
  it, but say which in the PR.

## Reproduction environment

Build:

```
make -C dm/host GAME=04008E001F098000
```

Run (working directory `/Volumes/X9BS/resort`):

```
DM_SAVE=/tmp/macsave DM_FOCUS_KEEP=1 DM_WINDOW=1 DM_AUDIO=1 DM_ROMFS=/Volumes/X9BS/resort/extract/v65536/RomFS.img DM_NVN_SHMAP=/Users/kaicherry/nxnative/dm/games/04008E001F098000/shader_map.tsv DM_MSL_DIR="/Volumes/X9BS/Nintendo Switch Sports Resort.app/Contents/Resources/msl" DM_JC1_LOG=2 "/Volumes/X9BS/Nintendo Switch Sports Resort.app/Contents/MacOS/dmhost" /Volumes/X9BS/resort/patched_v65536
```

- The Joy-Cons are paired in System Settings > Bluetooth (Bluetooth Classic HID); macOS combines a
  pair into one GCController. They must be awake; a press of any button wakes them.
- Diagnostics: `DM_JC1_LOG=2` (per-side frame once a second), `DM_MOTION_LOG=1` (player 1's merged
  stream), `DM_IMU_LOG=10` (every 10th raw sample and its arrival lag).
- `DM_PROBE=sdk:6d7118@x22+0x40` is the documented probe for this game's SDK sensor-fusion output.

## Current tree state

- Branch `feature/joycon1-motion`, head `ca1f06b9` (pushed), **PR #4** open.
- Committed since this handoff was written: `5fb1e8db` (host build depends on the Joy-Con
  headers), `835196d9` (the still offset), `e77298c1`, `804d6b96` (docs and the game note),
  `ca1f06b9` (Splatoon Raiders' shader build).
- Uncommitted (this session): `dm/games/0400380020056000/README.md` (motion controls),
  `docs/reference/services.md` (Splatoon Raiders in Found on and Open), `docs/agents/symptoms.md`
  (regenerated), plus the pre-existing `.gitignore` change (`./.rnsk-memory`).
- The host binary `dm/host/dmhost` is untracked build output and predates the still offset; the
  next action rebuilds through the NSP script anyway.
