# Nintendo Switch Sports (`0100D2F00D5C0000`)

Update 1.5.0 (`v589824`) over the base game, played on the Mac. The profile registers the base build (`v0`, 1.0.0) only: packing derives a profile for 1.5.0 at each run, so the build prints the "[RED] this Mac app uses v589824 … was not brought up on (v0 1.0.0)" line, and the fixes kept for a registered build's fixed addresses do not apply there. The game reaches its menus and plays.

## What it needs

- The base profile's tables (`game.tsv`, the shader map and its variants, `pso_pairs.tsv`, `pso_manifest.tsv`), no `patches.py`.
- `DM_LANG` decides the language; the UI text comes from the shared font (below).
- The Mac app's own Mac route: `~/Library/Application Support/nxnative/0100D2F00D5C0000/` (save), `~/Library/Logs/nxnative/0100D2F00D5C0000.log` (log). Headless runs use the repo host with `DM_MSL_DIR`/`DM_NVN_SHMAP` pointing at the app's or a build's library.

## Text: the shared font atlas (resolved)

- The UI text is rasterized by the game into a **32 MiB R8 atlas, 1024×32768 rows**, which Metal cannot hold as one 2D texture (its limit is 16,384 rows); the CPU writes it, so the host keeps it as a 2D array of equal pages (two of 16,384 rows).
- The font engine's pixel shader (`090670f92da91812`) samples it with `TEXS`/`Texture2DArray`, but the game's own glyph records address it as a **plain 2D texture**: `u0,v0,u1,v1` at record bytes +16..+28 (e.g. `u` 0.3096..0.3638, `v` 0.9822..0.9804 — a 55×59 texel glyph) with `v` over all 32,768 rows, and 0 at +40, the array coordinate. So the console's 2D descriptor wins and the shader must fold `v` into page + row; that is the general mechanism in [rendering.md](../../../docs/reference/rendering.md#a-texture-taller-than-metals-2d-limit), and its last defect was the fold helper's argument order.
- How the font draw can be read, since it is the one place this game's shaders are odd: `DM_NVN_KEYDUMP=090670f92da91812:2` logs the draw's vertex streams and every uniform buffer, which showed the quad's four corners at the attribute words 0,1 and the glyph rect exactly as the records above have it. The font vertex shader is `e7752a065d0df227` (64-byte records, quad corners as the attribute's x and y); `7022f0d73d38001a` is the same shader's other variant and takes 96-byte records, with the corners in the attribute's y.
- `vp_c1` for that vertex shader is the record's own constant segment, not the game's: 256 bytes, whose words at 64+32i and 80+32i are the per-corner `u` and `v` selector values (0,2,0,2 and 1,1,3,3) and whose words at 192..212 the selector codes (888, 912, 928 / 1104, 1072, 1088) map to record fields `u0,v0,u1,v1`. The translator's indexing of it is right, which is why the earlier "u does not vary" reading was wrong: a debug pixel shader that wrote the interpolated `m_33.xy` out showed `u` sweeping each quad normally, and the single column per glyph came from the sample, not the interpolated coordinate.
- **Always true:** the game's glyph atlas is written by the font engine on the CPU as it rasterizes, so the host's re-upload must re-protect the pages after each one (`nvn_dirty_protect` before the copy, as a packaged texture's upload does). Without it the picture stays at the first upload: letters missing and letters that look like other letters, on every screen reached after the first few — the two symptoms that took this the longest to find.
- The atlas as the host holds it can be read back with `texraw 36 <path>` (33,554,432 bytes, 32,768 rows of 1024); the glyph band at the opening is rows 32,095..32,747.
- **Open:** the "+ Select" prompt at the bottom right of the title screen draws as "elect" — the first glyph of that one string never appears, in every run, and it is the only text that is wrong. It is not the atlas (the rest of that screen's glyphs arrive); the next step is `DM_NVN_KEYDUMP=090670f92da91812:40` over the title screen to name the draw that produces it, its instance count and its vertex streams.

## Found on this game

- [A texture taller than Metal's 2D limit](../../../docs/reference/rendering.md#a-texture-taller-than-metals-2d-limit)
