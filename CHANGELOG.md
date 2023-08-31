# Changelog

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
