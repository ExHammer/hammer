# Changelog

## 7.1.0 - 2025-07-18

- Fix key type inconsistency in backend implementations - all backends now accept `term()` keys instead of `String.t()` (#143)
- Add comprehensive test coverage for various key types (atoms, tuples, integers, lists, maps)
- Fix race conditions in atomic backend tests (FixWindow, LeakyBucket, TokenBucket)
- Replace timing-dependent tests with polling-based `eventually` helper for better CI reliability
- Add documentation warning about Redis backend string key requirement
- Fix typo in `inc/3` optional callback documentation (#142)

## 7.0.1 - 2025-03-04

- Fix race condition in Atomic backends during creation of key.

## 7.0.0 - 2025-02-06

- Release candidate for 7.0.0. See [./guides/upgrade-v7.md] for upgrade instructions.

## 7.0.0-rc.4 - 2025-01-06

- Fix Token bucket to respect custom cost

## 7.0.0-rc.3 - 2024-12-18

- Fix regression to support other backends

## 7.0.0-rc.2 - 2024-12-17

- Fix type specs for ETS backends
- Adds Atomic backends and possible algorithms
- Added `:algorithm` option to the Atomic backend with support for:
  - `:fix_window` (default) - Fixed time window rate limiting
  - `:leaky_bucket` - Constant rate limiting with burst capacity
  - `:token_bucket` - Token-based rate limiting with burst capacity
- Add benchmarks file and run them with `bench`

## 7.0.0-rc.1 - 2024-12-13

- Improved API a little more. Should be compatibe with previous RC
  - Made ETS backend more flexible with `:algorithm` option
  - Added `:key_older_than` option to the ETS backend
- Added `:algorithm` option to the ETS backend with support for:
  - `:fix_window` (default) - Fixed time window rate limiting
  - `:sliding_window` - Sliding time window for smoother rate limiting
  - `:leaky_bucket` - Constant rate limiting with burst capacity
  - `:token_bucket` - Token-based rate limiting with burst capacity

## 7.0.0-rc.0 - 2024-12-13

- Breaking change. Completely new API. Consider upgrading if you are experiencing performance or usability problems with Hammer v6. See [./guides/upgrade-v7.md] for upgrade instructions. https://github.com/ExHammer/hammer/pull/104
- Hammer.Plug has been removed. See documentation for using Hammer as a plug in Phoenix.

## 6.2.1 - 2024-02-23

- Fix issue in OTP 26 and Elixir 1.15 by not using to_existing_atom in configuration

### Changed

## 6.2.0 - 2024-01-31

- Ensure Elixir version is ~> 1.13 https://github.com/ExHammer/hammer/pull/79.

## 6.1.0 - 2022-06-13

### Changed

- Updgrade dependency packages
- Merged https://github.com/ExHammer/hammer/pull/41 resulting in ETC without GenServer (and therefore better performance)
- Merged https://github.com/ExHammer/hammer/pull/46 remove additional whitespace
- Updated Docs based on https://github.com/ExHammer/hammer/pull/45
- Adds CREDITS.md

## 6.0.0 - 2018-10-12

### Changed

- Change the `ETS` backend to throw an error if either `expiry_ms` or
  `cleanup_interval_ms` config values are missing. This should have been fixed
  ages ago.
- Default `:pool_max_overflow` changed to `0`. It's a better default, given
  that some users have seen weird errors when using a higher overflow.
  In general, capacity should be increased by using a higher `:pool_size` instead
- Changed how the ETS backend does cleanups of data, should be more performant.


## 5.0.0 - 2018-05-18

### Added

- A new `check_rate_inc` function, which allows the caller to specify the
  integer with which to increment the bucket by. This is useful for limiting
  APIs which have some notion of "cost" per call.


## 4.0.0 - 2018-04-23

### Changed

- Use a worker-pool for the backend (via poolboy),
  this avoids bottle-necking all traffic through a single hammer
  process, thus improving throughput for the system overall

### Added

- New configuration options for backends:
  - `:pool_size`, determines the number of workers in the pool (default 4)
  - `:pool_max_overflow`, maximum extra workers to be spawned when the
    system is under pressure (default 4)
- Multiple instances of the same backend! You can now have two ETS backends,
  fifteen Redis's, whatever you want


## 3.0.0 - 2018-02-20

### Changed

- Require elixir >= 1.6
- Use a more sane supervision tree structure


## 2.1.0 2017-11-25

### Changed

- Add option to use more than one backend
- Add option to suppress all logging


## 2.0.0 - 2017-09-24

### Changed

- New, simpler API
  - No longer need to start backend processes manually
  - Call `Hammer.check_rate` directly, rather than `use`ing a macro
- Hammer is now an OTP application, configured via `Mix.Config`


## 1.0.0 - 2017-08-22

### Added
- Formalise backend API in `Hammer.Backend` behaviour


## 0.2.1 - 2017-08-10

### Changed

- Minor fixes
