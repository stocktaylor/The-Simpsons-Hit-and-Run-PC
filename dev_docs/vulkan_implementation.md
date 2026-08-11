# Vulkan Renderer — Implementation Plan

Goal: stand up a new `pddi` backend targeting Vulkan. Milestone 1 gets real
2D/UI rendering working everywhere the game calls it — frontend, bootup, and
in-game HUD/pause-over-3D — by implementing the 2D draw path for real while
**stubbing** the 3D draw path (see below). Milestone 2 replaces the 3D stub
with an actual wireframe implementation. Full shaded/textured/lit 3D is a
later milestone, not covered by this document yet.

This plan is derived from reading the existing `pddi` abstraction
(`libs/pure3d/pddi/`) and the 2D/UI draw call sites; see citations inline.
Nothing here has been implemented yet.

## Why stub 3D instead of excluding it

`RenderManager.cpp:553-556` renders all layers every frame, and the GUI
layer (`RenderEnums::GUI`) sits alongside the 3D world layers — in-game HUD
draws as an overlay in the same frame as an active 3D scene
(`guimanageringame.cpp:932`). Only `code/presentation/gui/bootup/` and
`code/presentation/gui/frontend/` are genuinely 3D-free, because no world
layer is populated before a level loads.

Rather than restrict Milestone 1 to those screens, `pddi` is just an
interface — the game calling a method has no way to know whether that method
actually touched the GPU. So instead of *excluding* 3D, Milestone 1 *stubs*
it: 3D draw calls (`DrawPrimBuffer`, real lighting/fog/stencil/z-buffer
state) validate their inputs, update whatever tracked state other code
depends on, and return success without submitting anything to the GPU.
Object-creation calls (`NewTexture`, `NewPrimBuffer`, `NewShader` for 3D
content) still need to hand back a valid object — the game holds onto that
pointer and calls `AddRef`/`Release`/`GetLastError` on it — so these become
small dummy classes that satisfy the interface contract without allocating
GPU resources.

This is a standard technique (sometimes called a "null renderer") and it
happens to map cleanly onto `pddi`'s existing structure: 3D world geometry
already goes through a different call path (retained-mode `pddiPrimBuffer` /
`DrawPrimBuffer`) than 2D/UI/movies (immediate-mode `BeginPrims`/`EndPrims`
only) — see the architecture recap below. The practical payoff: in-game HUD
and the pause menu render correctly over a blank/uninitialized-looking 3D
world in Milestone 1, instead of being deferred until 3D exists.

**Caveat not yet verified:** this assumes no *gameplay* logic (as opposed to
rendering) ever reads back render state — e.g. performance-stat-driven LOD
decisions, or picking/occlusion queries feeding into simulation. Worth a
targeted grep before leaning on the stub approach fully; see Open Questions.

## Architecture recap

- `pddi` is one fat interface, not several: `pddiDevice` (~10 pure-virtual
  methods), `pddiDisplay` (~12), `pddiRenderContext` (~60 — matrices,
  lighting, fog, stencil, z-buffer, prim submission), `pddiTexture` (~13),
  `pddiShader`/`pddiBaseShader` (~7). Declared in `libs/pure3d/pddi/pddi.hpp`.
- A shared `pddi/base/` layer (2190 lines) already implements state-tracking
  bookkeeping (dirty flags, stacks) that every existing backend
  (GL/GLES2/DX8/GXM) builds on — a new backend translates *tracked* state
  into native calls rather than re-deriving it.
- Backend selection is a CMake string, `SRR2_P3D_PDDI` (`OpenGL` / `GLES1` /
  `GLES2` / `GXM`), branched in `libs/pure3d/CMakeLists.txt:116-159` and the
  top-level `CMakeLists.txt:28-33`. GXM (Vita, ~3868 lines total) is the
  closest precedent for "bolt on a new graphics API from scratch."
- All 2D/UI/movie drawing is **immediate-mode only** —
  `BeginPrims`/`EndPrims`, never `pddiPrimBuffer` (retained/static geometry
  is exclusively a 3D-world thing). Two vertex formats cover everything:
  `PDDI_V_CT` (textured quads — sprites, glyphs, movie frames) and
  `PDDI_V_C` (flat-color triangles — UI shapes), both driven through a
  single `"simple"` shader material (`libs/pure3d/p3d/shader.cpp:16`).
- Matrix stack use in 2D is limited to orthographic projection
  (`SetProjectionMode(PDDI_PROJECTION_ORTHOGRAPHIC)`); lighting is only ever
  forced full-bright; fog/stencil are never touched by 2D content.
- Movie frames (`libs/radmovie/src/common/ffmpegmovieplayer.cpp:213-220`)
  arrive pre-converted to BGRA on the CPU via `sws_scale`, then get
  `Lock`/`Unlock`'d into a `tTexture` and drawn as a textured quad
  (`binkrenderstrategy.cpp:343`) — same draw path as sprites, no special
  handling needed.

## Milestone 1 — 2D/UI real, 3D stubbed

### Phase 0 — Spikes / unblockers
- [ ] Confirm (or build) a way to boot straight to the frontend without
      loading a level, so this milestone can be validated in isolation.
      Not confirmed to exist yet — check before relying on it.
- [ ] Decide the dynamic-vertex-buffer strategy for immediate-mode
      `BeginPrims`/`EndPrims` (single large per-frame ring buffer with
      host-visible/coherent memory, sized generously, reset each frame) —
      this is the one piece of real design work; everything else in this
      phase is mechanical translation of already-tracked state.

### Phase 1 — Build plumbing
- [ ] Add `"Vulkan"` as a valid `SRR2_P3D_PDDI` value in the top-level
      `CMakeLists.txt` and `libs/pure3d/CMakeLists.txt`, mirroring the GXM
      branch (new `pddi/vulkan/` source set, new
      `display_*/vkdisplay.cpp`).
- [ ] Find/vendor a Vulkan loader (volk or direct `vulkan.h` + SDL's
      loader) and wire it into the CMake build only when
      `SRR2_P3D_PDDI STREQUAL "Vulkan"`.
- [ ] Get a window + `SDL_Vulkan_CreateSurface` + instance + physical/logical
      device selection + swapchain + render pass + framebuffers compiling
      and creating a window that clears to a solid color and presents
      (replaces the GL-context/`SDL_GL_SwapWindow` logic in
      `gldisplay.cpp:148-256,338`).
- [ ] Frame-in-flight sync (2-3 frames), acquire/submit/present loop.
- [ ] When selecting/enabling physical device features, enable
      `fillModeNonSolid` now even though Milestone 1 doesn't use it — it's
      needed for Milestone 2's wireframe pipeline and is cheap to request
      upfront rather than revisit device creation later.

### Phase 2 — Device & textures
- [ ] `pddiDevice` factory methods for display/context/texture/shader
      creation (~10 methods).
- [ ] `pddiTexture`: staging-buffer upload path for `PDDI_TEXTYPE_RGB`
      (16/32bpp) and `PDDI_TEXTYPE_PALETTIZED` only — covers UI and movie
      textures. DXT/compressed and platform-specific formats
      (`pddiTexture::SetCompressedData`, `pddi/pddienum.hpp:291-315`) can
      assert/stub — nothing in 2D/UI/movie content uses them.
- [ ] `Lock`/`Unlock` support for per-frame texture updates (needed for
      movie playback, which re-uploads a frame's pixels every tick).

### Phase 3 — Pipelines
- [ ] One graphics pipeline for `PDDI_V_CT` (textured, alpha blend, no
      depth test/write) — sprites, glyphs, movie quads.
- [ ] One graphics pipeline for `PDDI_V_C` (flat-color triangles, alpha
      blend, no depth test/write) — UI shapes (`FePolygon.cpp:370`).
- [ ] Descriptor set layout for a single bound texture + sampler
      (nearest/linear per existing texture filter settings).
- [ ] `pddiShader`/`pddiBaseShader` implementation mapping `SetTexture`/
      `SetColour`/etc. onto push constants or a per-draw uniform buffer.

### Phase 4 — Render context / immediate mode + 3D stub objects
- [ ] `pddiRenderContext` subclass: implement `BeginPrims`/`EndPrims`
      writing into the Phase 0 dynamic vertex buffer, for real.
- [ ] Orthographic projection matrix handling — the only matrix-stack path
      2D content exercises.
- [ ] Stub the ~26 real lighting/fog/stencil/z-buffer methods on
      `pddiRenderContext` as no-ops that just satisfy the call (return
      success / update no real GPU state) — 2D content never calls them for
      anything but the forced-full-bright ambient light case.
- [ ] Stub `DrawPrimBuffer` as a no-op (validate args, return success, draw
      nothing) — this is the actual "3D drawing" entry point being stubbed.
- [ ] Dummy `pddiPrimBuffer` implementation: `NewPrimBuffer` returns a small
      object satisfying `pddiObject` refcounting (`AddRef`/`Release`/
      `GetLastError`) and any `Lock`/`Unlock`/`SetUsedSize` calls the game
      makes while loading level geometry, without allocating GPU buffers.
- [ ] Confirm 3D-content texture creation (world/character textures loaded
      even though nothing 3D renders yet) doesn't require formats beyond
      what Phase 2 already covers, or extend the dummy-object pattern to
      texture creation too if it does.

### Phase 5 — Validate against real content
- [ ] Boot to frontend (per Phase 0 spike) and get boot logos rendering.
- [ ] Main menu, language select, load/save, options screens rendering and
      interactive.
- [ ] Text rendering (`texturefont.cpp:215,239`) — should fall out of
      Phase 3's textured pipeline for free; verify glyph atlases look
      correct.
- [ ] Movie playback (intro/logos) rendering via the same textured-quad
      path — verify BGRA upload/orientation is correct.
- [ ] Load into an actual level and confirm in-game HUD/pause menu render
      correctly over the (blank, stubbed) 3D world — this is the payoff of
      stubbing rather than excluding 3D, and is worth explicitly testing
      rather than assuming it falls out for free.

## Explicitly out of scope for Milestone 1

- Any real 3D drawing — deferred to Milestone 2 (wireframe) below.
- Compressed (DXT) and platform-specific texture formats.
- Anything under `RenderManager`'s non-GUI layers actually *rendering* —
  the layers still run (so gameplay/simulation isn't blocked), they just
  produce no pixels.

## Milestone 2 — Wireframe 3D

Goal: replace the Milestone 1 3D stub with a real, minimal 3D draw path —
world/level geometry rendered as unlit wireframe with correct camera
perspective and depth occlusion. This validates the geometry pipeline
(vertex buffers, transforms, camera, depth) before taking on the much larger
scope of real shading, texturing, and lighting.

### Phase 6 — Wireframe geometry pipeline
- [ ] Implement `pddiPrimBuffer` for real: `NewPrimBuffer`, `Lock`/`Unlock`,
      actual GPU vertex/index buffer allocation and upload — replacing the
      Phase 4 dummy object.
- [ ] Implement `DrawPrimBuffer` for real: issue draw calls against a new
      wireframe pipeline — replacing the Phase 4 no-op.
- [ ] New wireframe pipeline: `VK_POLYGON_MODE_LINE` (requires enabling the
      `fillModeNonSolid` physical device feature at device-creation time,
      back in Phase 1), flat/unlit solid-color shading — no texture
      sampling needed yet. Decide whether backface culling stays on or off
      for wireframe (off shows more edges, useful for debugging geometry;
      on is closer to how the real renderer will eventually look).
- [ ] Real perspective projection and camera matrix path through the matrix
      stack (`PDDI_PROJECTION_PERSPECTIVE` — Milestone 1 only implemented
      orthographic) — `LoadMatrix`/`PushMatrix`/`MultMatrix` for
      world/view/projection matrices with real 4x4 data.
- [ ] Real depth buffer: add a depth attachment to the render pass/
      framebuffers (Milestone 1's 2D-only pipelines had no need for one),
      implement `EnableZBuffer`/`SetZCompare`/related methods for real so
      3D geometry occludes correctly.
- [ ] Validation target: load into an actual level and see world geometry
      (roads, static buildings/level meshes first — skinned/animated
      characters can come later) rendered as wireframe with correct camera
      perspective and depth occlusion, while GUI/HUD continues rendering
      normally on top via the Milestone 1 2D path.

### Explicitly out of scope for Milestone 2
- Real per-vertex/per-pixel lighting, fog, stencil — still stubbed/no-op,
  same as Milestone 1.
- Texturing/materials on 3D geometry — wireframe is flat-color only.
- Skinned/animated character rendering — static level geometry first.
- Particle systems, road-specific rendering features beyond basic geometry,
  any LOD/culling optimization — later milestones.

## Open questions

- No confirmed "boot directly to frontend" dev path yet — needs checking
  before Phase 0 can be marked done.
- Vulkan loader choice (volk vs. raw `vulkan.h` vs. something SDL already
  provides) not yet decided.
- Whether validation targets desktop Vulkan only for this phase, or also
  needs to consider the Vita/mobile angle from `dev_docs/portmaster.md` —
  assuming desktop-only for now since PortMaster targets are GLES-only
  anyway and wouldn't use this backend.
- Whether any gameplay/simulation logic reads back render state (perf
  stats, picking/occlusion queries) in a way the stub-3D approach in
  Milestone 1 would break — not yet checked, worth a targeted grep before
  relying on the stub fully.

## Nice to have: side-by-side GL/Vulkan debug backend

Idea: a `pddi` backend that's a multiplexing/fan-out proxy over the two
*real* backends — every call forwards to both the existing GL backend and
the new Vulkan backend, each driving its own SDL window, both fed by the
same game state in the same process. The payoff would be visually comparing
"known good" (GL) against "in progress" (Vulkan) side by side while
navigating to specific game states, without needing two independently-driven
processes to somehow stay in sync.

This is not scheduled as a phase — it's a testing/debug tool, not a
prerequisite for the plan above, and it's most useful (and least confusing
to build) once there's something on the Vulkan side worth comparing.

**Roughly what it would take:**
- Every `pddi` object type (`pddiTexture`, `pddiPrimBuffer`, `pddiShader`,
  the render context itself) needs a thin wrapper holding *two* underlying
  objects — one GL, one Vulkan — that forwards each call to both and unwraps
  the right handle per-backend when one object gets passed into another call
  (e.g. `SetTexture(shader, wrapperTexture)`).
- This has to be done consistently across the full interface (~90+ methods
  across `pddiDevice`/`pddiDisplay`/`pddiRenderContext`/`pddiTexture`/
  `pddiShader`), including refcounting, so a leak/mismatch on one side
  doesn't happen silently.
- No new threading model needed — calls can forward to both backends
  synchronously, one after the other, on the same thread that's already
  driving rendering today.
- `pddiDisplay`/`InitDisplay` would create two SDL windows and drive two
  present loops in one process; GL and Vulkan can coexist fine in the same
  process address space.

**Why it's deliberately not scheduled yet:**
- Building the mux layer and a brand-new backend at the same time makes
  every visual discrepancy ambiguous — is it a Vulkan bug, or a mux-layer
  bug? Better to prove the Vulkan backend correct solo first (per the
  milestones above), then add the mux layer as a pure debugging aid on top
  of two already-working backends.
- Until Milestone 2+ gives the Vulkan side real 3D output, a side-by-side
  window mostly shows identical 2D/HUD content and a blank Vulkan viewport
  where GL shows the 3D world — informative for validating 2D, not for the
  comparison this idea is really aimed at.

**Cheaper alternative that gets partway there sooner:** run two separate
existing builds (`SRR2_P3D_PDDI=OpenGL` and `=Vulkan`) as two independent
processes, each with its own window — no new `pddi` code at all. "Same game
state" isn't automatic across two processes (nondeterminism in AI/physics/
input timing would let them drift), but a recorded input replay (capture
inputs+timing once, feed identically into both processes) sidesteps that
without needing a live shared-state renderer. Worth doing this first if
side-by-side comparison is needed before the full mux backend is worth
building.
