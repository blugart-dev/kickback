## Centralized collision-layer convention for Kickback physics rigs.
## Single source of truth for the layer numbers used across the plugin, so the
## 4/5 ragdoll convention isn't re-spelled as magic numbers (8, 16, 24, 18...).
##
## Naming: *_BIT is the 0-based shift; *_LAYER is the bitmask (1 << BIT), which
## equals the (BIT + 1)-th layer in the Godot inspector UI.
class_name KickbackLayers

## Active-ragdoll RigidBody3D bodies (Active Ragdoll mode). UI layer 4.
const ACTIVE_RAGDOLL_BIT := 3
const ACTIVE_RAGDOLL_LAYER := 1 << ACTIVE_RAGDOLL_BIT   # 8

## Godot PhysicalBoneSimulator3D bones — used by the built-in-ragdoll comparison
## demo (Kickback itself is the active spring ragdoll). UI layer 5.
const PARTIAL_RAGDOLL_BIT := 4
const PARTIAL_RAGDOLL_LAYER := 1 << PARTIAL_RAGDOLL_BIT  # 16

## Combined mask matching either ragdoll layer (used by hit raycasts).
const BOTH_RAGDOLL_MASK := ACTIVE_RAGDOLL_LAYER | PARTIAL_RAGDOLL_LAYER  # 24

## Environment / world geometry that PhysicalBone3D bodies collide against. UI layer 2.
const ENVIRONMENT_BIT := 1
const ENVIRONMENT_LAYER := 1 << ENVIRONMENT_BIT          # 2
