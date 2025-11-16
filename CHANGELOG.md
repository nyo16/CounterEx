# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-11-16

### Added

- **Pluggable Backend Architecture**: Three backend implementations
  - `CounterEx.Backend.ETS` - Unlimited dynamic counters
  - `CounterEx.Backend.Atomics` - Fixed capacity, ultra-fast (291K ops/s on M4 Max)
  - `CounterEx.Backend.Counters` - Write-optimized (269K ops/s on M4 Max)
- **Namespace Support**: Organize counters into logical groups
  - All operations now support namespaces as an optional first parameter
  - `delete_namespace/1` to clear entire namespaces
  - `all/1` to get all counters in a specific namespace
- **Enhanced API Operations**:
  - `delete/1-2` - Delete individual counters
  - `compare_and_swap/3-4` - Atomic compare-and-swap operations
  - `info/0` - Get backend information and statistics
- **Telemetry Integration**: All backend operations emit telemetry events
  - Events: `[:counter_ex, :backend, :ets/:atomics/:counters, :operation]`
  - Enables monitoring and observability
- **Comprehensive Test Suite**: 900+ lines of tests
  - Unit tests for all three backends
  - Concurrency tests
  - Integration tests
  - Property-based testing with StreamData
- **Professional Documentation**:
  - Migration guide (`guides/migration.md`)
  - Backend comparison guide (`guides/backends.md`)
  - Complete README rewrite with real benchmarks
- **Code Quality**:
  - Credo configuration (`.credo.exs`)
  - ExCoveralls for test coverage
  - Modern CI/CD with GitHub Actions matrix testing

### Changed

- **BREAKING**: Return values now use `{:ok, value}` tuples for consistency
  - `inc/1-4` returns `{:ok, integer()}` instead of `integer()`
  - `get/1-2` returns `{:ok, integer() | nil}` instead of `integer() | nil`
  - `set/2-3` returns `{:ok, integer()}` instead of `integer()` or `boolean()`
  - `reset/1-3` returns `{:ok, integer()}` instead of `boolean()`
- **BREAKING**: `all/0-1` now returns `{:ok, map()}` instead of list or nil
  - Map keys are counter keys, values are their current values
- **BREAKING**: Minimum Elixir version raised to 1.17
- **BREAKING**: Minimum OTP version raised to 26
- Refactored `CounterEx.Keeper` to use pluggable backends
- Updated all dependencies to latest versions
  - `telemetry ~> 1.3`
  - `ex_doc ~> 0.35`
  - `benchee ~> 1.3`
  - `credo ~> 1.7`

### Improved

- **Performance**: Backend-specific optimizations
  - Atomics: 291K get ops/s, 253K inc ops/s
  - ETS: 270K get ops/s, 256K inc ops/s
  - Counters: 269K get ops/s, 248K inc ops/s
  - (Benchmarked on Apple M4 Max with 4 parallel workers)
- **CI/CD**: Modern GitHub Actions workflow
  - Test matrix: Elixir 1.15.8, 1.16.3, 1.17.3
  - OTP versions: 26.2, 27.1
  - Code formatting checks
  - Credo static analysis
  - Coverage reporting
- **Architecture**: Clean separation of concerns with behaviour pattern
- **Documentation**: Comprehensive guides and API documentation

### Deprecated

- `start_keeper/0` and `start_keeper_with_sweep/1` still work but using `{CounterEx, opts}` in supervision trees is now preferred

### Migration Guide

See `guides/migration.md` for detailed migration instructions from v0.1.x.

**Quick Migration:**
1. Update all function calls to pattern match on `{:ok, value}` tuples
2. Update `all/0` calls to handle map instead of list
3. Consider using namespaces to organize counters
4. Choose appropriate backend for your use case

## [0.1.0] - 2020-01-27

### Added

- Initial release
- Basic counter operations: `inc/1-3`, `get/1`, `set/1-2`, `reset/1-2`, `all/0`
- ETS-based storage
- Periodic sweep functionality
- Benchmark utilities

[0.2.0]: https://github.com/nyo16/CounterEx/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/nyo16/CounterEx/releases/tag/v0.1.0
