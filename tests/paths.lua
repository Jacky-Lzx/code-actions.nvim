vim.opt.rtp:prepend(vim.env.CODE_ACTIONS_ROOT)
local preview = require("code_actions.preview")
local count = 0
local function check(value, message)
  assert(value, message)
  count = count + 1
end
local function buffer(path)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "old" })
  return buf, vim.uri_from_bufnr(buf)
end
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/project/.git", "p")
vim.fn.mkdir(tmp .. "/project/markdown", "p")
vim.fn.mkdir(tmp .. "/workspace/sub", "p")
tmp = assert(vim.uv.fs_realpath(tmp))
local project = tmp .. "/project"
local buf, uri = buffer(project .. "/markdown/中文 test.md")
local cwd = vim.fn.getcwd()
vim.cmd.cd(project .. "/markdown")
check(
  preview.root(buf, { config = { root_dir = project .. "/markdown" } }) == project,
  "Git root takes priority over nested cwd and LSP root"
)
local edits = {
  {
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } },
    newText = "new",
  },
}
local action = { edit = { changes = { [uri] = edits } } }
local lines = preview.lines(action, "utf-16", project)
check(
  lines[1] == "--- markdown/中文 test.md" and lines[2] == "+++ markdown/中文 test.md",
  "diff headers use decoded project-relative paths"
)
check(action.edit.changes[uri] == edits, "display conversion preserves edit URI and object")
local other, other_uri = buffer(tmp .. "/project-extra/test.md")
lines = preview.lines({ edit = { changes = { [other_uri] = edits } } }, "utf-16", project)
check(
  lines[1] == "--- " .. tmp .. "/project-extra/test.md",
  "outside files retain absolute paths with prefix boundary"
)
local workspace_buf = buffer(tmp .. "/workspace/sub/test.md")
local client = {
  workspace_folders = {
    { uri = vim.uri_from_fname(tmp .. "/unrelated-workspace-with-a-long-name") },
    { uri = vim.uri_from_fname(tmp .. "/workspace") },
    { uri = vim.uri_from_fname(tmp .. "/workspace/sub") },
  },
}
check(
  preview.root(workspace_buf, client) == tmp .. "/workspace/sub",
  "most specific matching LSP workspace is used"
)
check(
  preview.root(workspace_buf, { config = { root_dir = tmp .. "/workspace" } })
    == tmp .. "/workspace",
  "LSP configured root works without workspace folders"
)
check(
  preview.root(workspace_buf, { root_dir = tmp .. "/workspace" }) == tmp .. "/workspace",
  "LSP root property works"
)
check(
  preview.root(workspace_buf, { root_dir = tmp .. "/unrelated" }) == project .. "/markdown",
  "unrelated LSP root falls back to cwd"
)
check(
  preview.root(workspace_buf, nil) == project .. "/markdown",
  "missing client falls back to cwd"
)
lines = preview.lines(
  { edit = { documentChanges = { { kind = "create", uri = "untitled:document" } } } },
  "utf-16",
  project
)
check(lines[1] == "Create file: untitled:document", "non-file URIs remain unchanged")
lines = preview.lines({
  edit = {
    documentChanges = { { kind = "create", uri = vim.uri_from_fname(project .. "/new.md") } },
  },
}, "utf-16", project)
check(lines[1] == "Create file: new.md", "resource-operation labels also use the project root")
vim.cmd.cd(cwd)
vim.fn.delete(tmp, "rf")
print(("code-actions paths: %d assertions passed"):format(count))
vim.cmd("qa!")
