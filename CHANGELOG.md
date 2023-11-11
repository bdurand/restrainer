# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
