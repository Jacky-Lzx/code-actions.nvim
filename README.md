# code-actions.nvim

A small Snacks-only picker with asynchronous LSP code action previews.

Neovim handles action requests, cursor/Visual ranges, diagnostics, filters and
`apply = true`. This plugin adapts its code action selection UI, resolves actions
once per item, previews standard workspace edits, and applies the cached result.
Normal `vim.ui.select` requests continue through your existing provider.

## Requirements

- Neovim 0.12 (tested with 0.12.6)
- [snacks.nvim](https://github.com/folke/snacks.nvim), with picker enabled
- An attached language server supporting code actions

No plenary or external diff executable is required.

## Local installation with lazy.nvim

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/code-actions.nvim"),
  name = "code-actions.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "LspAttach",
  opts = {},
  config = function(_, opts)
    require("code_actions").setup(opts)
  end,
  keys = {
    { "<leader>a", function() require("code_actions").code_action() end,
      mode = { "n", "x" }, desc = "Code action" },
  },
}
```

After setup, `vim.lsp.buf.code_action()` and the default `gra` mapping also show
the preview picker. Confirm with Enter, cancel with Escape. These keys are set
on picker input and list windows; the rest follows your Snacks configuration.

Options:

```lua
require("code_actions").setup({
  resolve_timeout = 3000, -- milliseconds; no synchronous waits
  backend = "vim", -- "vim" (default) or "delta"
  delta = {
    command = "delta", -- executable name or absolute path
    args = {}, -- for example { "--line-numbers", "--side-by-side" }
    timeout = 2000, -- milliseconds
  },
  picker = { layout = { preset = "default" } },
})
```

`picker` customizes Snacks appearance. Item collection, preview, confirmation
and close callbacks are owned by this plugin.

Set `backend = "delta"` to format diffs with the optional
[delta](https://dandavison.github.io/delta/) executable. Its ANSI colors are rendered
in the Snacks preview buffer. Delta runs asynchronously with the preview window's
width, dark/light mode, true color and paging disabled. Extra arguments are passed
directly as an argument list, never through a shell; delta can read your normal
Git configuration. Missing delta, startup errors, unsuccessful exits, empty output
and timeouts fall back to the native diff. Command-only actions and resource-only
summaries use the native text preview. Changing selection or closing the picker
cancels any pending delta process and ignores late output.

To hide the repeated top file section while keeping a project-relative path and
line number in each hunk header:

```lua
delta = {
  args = { "--file-style=omit", "--hunk-header-style=file line-number syntax" },
},
```

## Behavior and limits

- Previews use loaded buffer contents, including unsaved edits, before disk.
- File labels are relative to the source buffer's Git root, otherwise its LSP
  workspace/root directory, otherwise Neovim's cwd when the picker opens. Files
  outside that root keep absolute paths; non-file URIs remain unchanged. Only
  display labels change, not the URIs used for applying edits.
- UTF-8/UTF-16/UTF-32 edits use the server's position encoding via Neovim.
- `changes` and ordered `documentChanges` support multiple files. File resource
  operations appear as summaries; the preview never creates, renames or deletes
  real files. Operation options/annotations are applied by Neovim on confirmation,
  but preview summaries are not a simulation of filesystem permissions/options.
- Command-only actions remain executable but have no text diff. Commands attached
  to text edits may have extra effects that cannot be previewed.
- Resolve errors/timeouts keep the picker open when no executable edit/command
  was provided. Otherwise the original action remains executable, as in native
  code actions. Closing cancels pending requests;
  late responses cannot replace the currently selected item's preview.
- Confirmation refuses actions if the original buffer changed while the picker
  was open. Cross-file previews are snapshots, not a transactional edit guarantee.
- This adapter recognizes Neovim's internal `{ action, ctx }` selection items.
  If the shape changes, it delegates to the existing picker without a preview.
  Check compatibility after upgrading Neovim. LSP apply/command behavior uses
  public APIs; cached resolved actions deliberately avoid resolving twice.

## Tests

```sh
./tests/run.sh
SNACKS_DIR=~/.local/share/nvim/lazy/snacks.nvim ./tests/integration.sh
```

Unit tests cover preview isolation, Unicode edits, unsaved/multiple files,
resource-operation order, late responses, resolve caching, failure/timeout,
confirmation, cancellation, fallback selection, and setup lifecycle.
Integration tests start a real Neovim LSP client against a local fixture server
and open an actual Snacks picker. No network or language server installation is
required. The fixture is a protocol test, not a compatibility claim for every
language server.

Renderer tests cover native output, literal delta arguments, ANSI output,
cancellation and fallback. Integration tests additionally exercise a missing
executable and a timed-out process. If delta is installed, they test its real ANSI
output, switching between delta and command-only previews, and failure fallback.
