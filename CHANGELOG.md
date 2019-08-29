## 0.35.2 (unreleased)

- added: render values from kong.ctx.shared

## 0.35.1

### Fixed

- Correct logic error when determining whether to transform querystring
- Fix a bug where the code does not allow adding and appending a body
parameter if there is no body in the POST request
- Change the priorities for the transformations to allow the
headers to be transformed before the body

## 0.35

### Changed

- Convert to new dao

## 0.34.0

### Changed
 - Internal improvements

## 0.1.0

- `pre-function` and `post-function` enterprise plugins added
