vim.opt.rtp:prepend(vim.env.CODE_ACTIONS_ROOT)
vim.opt.rtp:prepend(vim.env.SNACKS_DIR)
vim.o.columns, vim.o.lines = 120, 40
require("snacks").setup({ picker = { enabled = true } })
require("snacks.picker").setup()
require("code_actions").setup()
local function wait(test, message)
  assert(vim.wait(5000, test, 10), message)
end
local function current()
  return require("snacks.picker").get()[1]
end
local function preview_text(picker)
  local buf = picker.preview.win.buf
  return buf
      and vim.api.nvim_buf_is_valid(buf)
      and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    or ""
end
vim.cmd("enew")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".txt")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world", "second line" })
local id = vim.lsp.start({
  name = "code-actions-fixture",
  cmd = { "python3", vim.env.CODE_ACTIONS_ROOT .. "/tests/server.py" },
  root_dir = vim.fn.getcwd(),
})
local client = assert(vim.lsp.get_client_by_id(id))
wait(function()
  return client.initialized
end, "fixture server initializes")
vim.lsp.buf.code_action()
wait(function()
  return current() and current():current()
end, "actual Snacks picker opens")
local picker = current()
wait(function()
  return preview_text(picker):find("+你好😀 world", 1, true)
end, "real preview renders Unicode diff")
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "hello world", "preview is isolated")
assert(
  vim.bo[picker.preview.win.buf].syntax == "diff"
    or vim.treesitter.highlighter.active[picker.preview.win.buf],
  "diff highlighting is active"
)
assert(#picker:items() == 2, "native actions reach Snacks")
picker.opts.confirm(picker, picker:current())
wait(function()
  return not current()
end, "confirmation closes picker")
assert(
  vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "你好😀 world",
  "real native workspace edit applies"
)

vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world", "second line" })
vim.cmd("normal! ggVj")
vim.lsp.buf.code_action({ context = { only = { "quickfix" } } })
wait(function()
  return current() and current():current()
end, "Visual code action picker opens")
picker = current()
assert(#picker:items() == 1, "native kind filtering remains active")
local range = picker:current().entry.action.data.range
assert(range.start.line == 0 and range["end"].line == 1, "native Visual range reaches server")
picker:close()
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "hello world", "cancel preserves text")
vim.cmd("normal! \027")

vim.lsp.buf.code_action({ context = { only = { "quickfix" } }, apply = true })
wait(function()
  return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "你好😀 world"
end, "native apply=true remains supported")
assert(not current(), "native automatic apply bypasses picker")
client:stop(true)
print(
  "code-actions: real LSP/Snacks integration passed (preview, apply, Visual, filter, cancel, auto-apply)"
)
vim.cmd("qa!")
