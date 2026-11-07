# API and lifecycle

`setup(opts)` enables protection; repeated equal setup retains existing state.
Invalid options are rejected before releasing protections. Defaults:

- `max_bytes = 1572864`, `max_line_length = 1000`: positive limits; false disables either test.
- `filetype = "bigfile"`: false retains the native filetype.
- `buffer = {}`: buffer variables to set alongside `bigfile = true`.
- `window = { foldmethod = "manual", foldexpr = "0", conceallevel = 0, statuscolumn = "" }`.
- `exclude = nil`: optional `function(buf, path)` returning true to exclude a buffer.

Provided buffer/window tables replace their defaults. No UI plugin is required.
`detect(buf, path)` reads buffer size and mean line length without applying changes.
`protect(buf)` applies protection explicitly; `release(buf)` restores only flags,
filetypes and window options still owned by this instance. A subsequent size event
may protect a released large buffer again. Later user changes are preserved.
`info()` returns detached options and protected buffer names. `dispose()` removes
owned events and releases all protections; call setup to enable again.
The registered filetype classifier remains inert after disposal because Neovim
has no public API to unregister an individual filetype pattern. The Info entrypoint
is retained to inspect disabled state. Buffer contents are never changed.

Run `python3 tests/run.py --check` and `python3 tests/run.py` for isolated regression
coverage. The configuration repository additionally tests actual startup rendering.
