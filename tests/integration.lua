vim.opt.rtp:prepend(vim.env.CODE_ACTIONS_ROOT)
vim.opt.rtp:prepend(vim.env.SNACKS_DIR)
vim.o.columns, vim.o.lines = 120, 40
require("snacks").setup({ picker = { enabled = true } })
require("snacks.picker").setup()
local backend = vim.env.CODE_ACTIONS_BACKEND or "vim"
local delta_command = vim.env.CODE_ACTIONS_DELTA_COMMAND or "delta"
local expect_delta = backend == "delta" and vim.env.CODE_ACTIONS_EXPECT_DELTA ~= "0"
require("code_actions").setup({
  backend = backend,
  delta = {
    command = delta_command,
    timeout = tonumber(vim.env.CODE_ACTIONS_DELTA_TIMEOUT) or 2000,
    args = vim.env.CODE_ACTIONS_DELTA_FAIL == "1" and { "--invalid-code-actions-test-flag" }
      or { "--file-style=omit", "--hunk-header-style=file line-number syntax" },
  },
})
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
local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/.git", "p")
vim.fn.mkdir(project .. "/markdown", "p")
project = assert(vim.uv.fs_realpath(project))
vim.api.nvim_buf_set_name(buf, project .. "/markdown/test.md")
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
  return preview_text(picker):find("你好😀 world", 1, true)
end, "real preview renders Unicode diff")
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "hello world", "preview is isolated")
assert(
  expect_delta and vim.bo[picker.preview.win.buf].buftype == "terminal"
    or not expect_delta
      and (vim.bo[picker.preview.win.buf].syntax == "diff" or vim.treesitter.highlighter.active[picker.preview.win.buf]),
  "diff highlighting is active"
)
assert(#picker:items() == 2, "native actions reach Snacks")
assert(picker:current().root == project, "preview captures the source project's Git root")
if expect_delta then
  local text = preview_text(picker)
  assert(
    not text:find("file://", 1, true) and not text:find(project, 1, true),
    "delta output omits URI prefixes and absolute project path"
  )
  assert(
    text:find("markdown/test.md:1", 1, true),
    "delta hunk title uses the project-relative path"
  )
  local _, occurrences = text:gsub("markdown/test%.md", "")
  assert(occurrences == 1, "only the hunk title shows the filename; top file section is hidden")
end
if expect_delta then
  picker.list:move(2, true)
  picker:show_preview()
  wait(function()
    return preview_text(picker):find("No text edit", 1, true)
  end, "switching from delta to command-only preview")
  assert(vim.bo[picker.preview.win.buf].buftype ~= "terminal", "old terminal buffer is cleared")
  picker.list:move(1, true)
  picker:show_preview()
  wait(function()
    return preview_text(picker):find("你好😀 world", 1, true)
  end, "switching back to delta preview")
  assert(vim.bo[picker.preview.win.buf].buftype == "terminal", "ANSI preview is recreated")
end
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
vim.fn.delete(project, "rf")
print(
  "code-actions: real LSP/Snacks integration passed ("
    .. backend
    .. (expect_delta and "/ANSI" or "/native")
    .. ", preview, apply, Visual, filter, cancel, auto-apply)"
)
vim.cmd("qa!")
