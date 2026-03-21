# Contributing to Kickback

Thanks for your interest in contributing! Here's how to get started.

## Setup

1. **Fork and clone** the repository
2. **Install Godot 4.6.1+** from [godotengine.org](https://godotengine.org/download)
3. **Enable Jolt Physics**: Project Settings > Physics > 3D > Physics Engine > Jolt Physics
4. **Enable the plugin**: Project > Project Settings > Plugins > Kickback > Enable
5. **Run a demo**: Open any scene from `demo/` to verify setup

## Running Tests

```bash
godot --headless --path . --script test/run_all_tests.gd
```

All 167 assertions should pass. Tests run without rendering (headless mode).

## Code Conventions

- **GDScript** — all plugin code
- All scripts use `class_name` with `@icon()` annotations (where applicable)
- All `@export` properties have `##` doc comments
- Controllers use the `configure(profile, tuning)` pattern
- Controllers emit signals, never play animations directly
- All root movement and rotation in `_physics_process`, not `_process`
- Resources use `create_*_default()` factory methods

## Pull Request Workflow

1. Create a feature branch from `main`
2. Make your changes
3. Run the test suite (see above)
4. Run at least one demo scene to verify behavior
5. Open a PR with the template filled out

## What Makes a Good PR

- **Focused**: one feature, one fix, or one refactor per PR
- **Tested**: new functionality has tests, existing tests still pass
- **Documented**: new `@export` properties have `##` comments, new signals are listed in REFERENCE.md
- **No breaking changes** without discussion first

## Project Structure

```
addons/kickback/     # The plugin (this is what users install)
demo/                # Demo scenes (not part of the plugin)
test/                # Unit tests
docs/                # Technical documentation
```

## Areas Where Help Is Wanted

- Non-Mixamo skeleton testing (Rigify, Unreal Mannequin, custom rigs)
- Performance profiling with 10+ simultaneous active ragdolls
- New demo scenes showcasing specific use cases
- Documentation improvements

## Questions?

Open a [Discussion](https://github.com/blugart-dev/kickback/discussions) for questions, ideas, or help.
