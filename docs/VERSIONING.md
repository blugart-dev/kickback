# Versioning

Kickback uses [Semantic Versioning](https://semver.org/) with one project-specific
convention:

> **`1.0.0` means full [Euphoria](EUPHORIA_COMPARISON.md) parity** — a character that
> *actively tries to survive* (steps to catch its balance, braces with its arms, grabs
> the environment, generates its own recovery poses), not just a ragdoll that gets
> pushed around.

That is a deliberately high bar. Everything before `1.0.0` is the road toward it.

## What the numbers mean

- **`0.x` (pre-1.0)** — the journey to parity. The **minor** version tracks *rough,
  difficulty-weighted* progress toward the 1.0 objective: `0.3.x` ≈ "about a third of
  the way." It is recomputed from the [scorecard](ROADMAP.md) at each milestone, not
  chosen by feel.
- **patch (`0.3.1`)** — fixes, polish, and hardening within a milestone; no new
  objective progress.
- **pre-release tags (`0.4.0-alpha`, `-beta`, `-rc`)** — in-progress milestones.
- **`1.0.0`** — full Euphoria parity **plus** a committed, stable public API.

Because `1.0` is the *vision*, Kickback will stay `0.x` for a long time even though it
is already usable today. That is intentional: the number reflects distance to the
goal, not whether the plugin works.

## The 2026-06-19 recalibration

Kickback previously climbed to `0.8.5`, which read as ~85% complete. Against the
objective above that was misleading — the entire active self-preservation layer (the
part that *is* Euphoria) was unbuilt (~0%). Difficulty-weighted, the project was closer
to **~30%**.

To make the number honest, the project was **re-baselined `0.8.5` → `0.3.0`**:

- The `v0.7.0` / `v0.8.0` / `v0.8.5` GitHub releases and git tags were deleted. (Kickback
  was never published to the Godot Asset Library and had no forks, so the blast radius
  was effectively zero.)
- `CHANGELOG.md` preserves the old entries under **Legacy history (deprecated
  numbering)** — those numbers are **not comparable** to current ones.
- A few numbers (`0.3.0`, `0.7.0`, `0.8.0`) are reused under the new scheme; the
  originals are deleted and clearly marked legacy.

This is a one-time correction, permissible precisely because we are pre-1.0 — SemVer
makes no compatibility guarantee below `1.0.0`.

## Cutting a release

1. Update `version=` in `addons/kickback/plugin.cfg`.
2. Update `CHANGELOG.md`.
3. Tag with a `v` prefix and push: `git tag v0.3.0 && git push origin v0.3.0`.
4. One-time, so tags sort by version not lexically: `git config tag.sort version:refname`.
