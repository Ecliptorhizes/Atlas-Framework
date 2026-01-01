# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

# 1.0.0 (2026-01-01)

### Features

* Initial release of ResourceManager
* Add deterministic cleanup of disposable resources
* Support cleanup for:
  * RBXScriptConnection
  * Instance
  * thread (via task.cancel)
  * cleanup callbacks
  * tables exposing Destroy() or Disconnect()
* Safe, idempotent Destroy() behavior
* Selene-compatible runtime implementation
* Nevermore-style package structure
