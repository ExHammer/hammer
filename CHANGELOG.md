# Changelog

## 2.1.0

### Changed

- Add option to use more than one backend
- Add option to suppress all logging


## 2.0.0

### Changed

- New, simpler API
  - No longer need to start backend processes manually
  - Call `Hammer.check_rate` directly, rather than `use`ing a macro
- Hammer is now an OTP application, configured via `Mix.Config`


## 1.0.0

### Added
- Formalise backend API in `Hammer.Backend` behaviour


## 0.2.1

### Changed

- Minor fixes
