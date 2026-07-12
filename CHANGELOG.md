# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.5

### Fixed

- Expired process cleanup now uses the Redis server clock instead of the client clock,
  so clock skew between application hosts can no longer reap active locks or allow the
  limit to be exceeded.
- `release!` now always returns a boolean; previously it could return a truthy `0` with
  Redis clients that return integer replies from `ZREM`.
- The Lua script SHA1 is now precomputed as a constant. Previously each `Restrainer`
  instance loaded the script on its first lock because the intended class level cache
  was never populated.
- The sorted set key is now passed to the Lua script via `KEYS` instead of `ARGV`,
  making the script compatible with Redis Cluster slot routing.
- The `NOSCRIPT` recovery path now retries only once instead of retrying indefinitely.
- Fixed constructor examples in the README that raised `ArgumentError`.

## 1.1.4

### Removed

- Removed unimplemented method stub.

## 1.1.3

### Added

- Support for using fractional seconds in the lock timeout.

## 1.1.2

### Changed

- Redis instance will now default to a Redis instance with the default options
  instead of throwing an error if it was not set.
- Minumum Ruby version set to 2.5

## 1.1.1

### Fixed

- Circular reference warning

## 1.1.0

### Added

- Expose manually locking and unlocking processes.
- Allow passing in a redis connection in the constructor.

## 1.0.1

### Fixed

- Use Lua script to avoid race conditions and ensure no extra processes slip through.

## 1.0.0

### Added

- Initial release.
