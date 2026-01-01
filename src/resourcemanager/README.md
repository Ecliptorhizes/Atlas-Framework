## ResourceManager

A lightweight cleanup utility for managing disposable resources in Roblox Luau.

## Overview

`ResourceManager` provides a simple and deterministic way to track and clean up
resources such as connections, instances, tasks, and callbacks.

It is designed as a **framework-level primitive**, similar in scope to `Maid`,
`Trove`, or `Janitor`, and is suitable for use in both client and server
environments.

Cleanup is explicit, predictable, and safe to call multiple times.

---

## Features

- Tracks common disposable Roblox resources
- Deterministic cleanup order (reverse insertion)
- Safe, idempotent destruction
- Supports both static and dynamic cleanup patterns
- No side effects on require
- No external dependencies

---

## Supported Resource Types

- `RBXScriptConnection` → `:Disconnect()`
- `Instance` → `:Destroy()`
- `thread` → `task.cancel`
- `function` → invoked via `pcall`
- Tables exposing `Destroy()` or `Disconnect()`

---

## Installation

