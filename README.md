# bigfile-tools.nvim

Early large/minified buffer protection.

## Features

- Classify large/minified files before FileType consumers run.
- Detect current buffer size, including unsaved edits.
- Stop highlighting and apply configurable buffer flags/window options.
- Restore only resources still owned by the protection instance.

## Requirements

Neovim 0.11+. No external tools or runtime plugin dependencies.

## Installation

Mount the checkout on runtimepath before filetype consumers, or declare it with
plugin-tools.nvim and ensure its setup runs early:

```lua
{ id = "bigfile-tools.nvim", source = "Jacky-Lzx/bigfile-tools.nvim", main = "bigfile_tools" }
```

## Usage

```lua
require("bigfile_tools").setup({
  max_bytes = 1.5 * 1024 * 1024,
  max_line_length = 1000,
  buffer = { completion = false },
})
```

Large buffers become `bigfile` before their FileType event. Native highlighting
stops and configured window options degrade. The mean line threshold also catches
small minified files. Startup redraw orchestration and integration choices belong
to the configuration.

## Documentation

- [API, options and lifecycle](doc/guide.md)
- `:help bigfile-tools` for the in-editor reference.
- `:BigfileToolsInfo` and `:checkhealth bigfile_tools` inspect without activation.

## Development

Run `python3 tests/run.py` for the [isolated tests](tests/README.md).
Run `stylua --check lua plugin tests` before committing.
