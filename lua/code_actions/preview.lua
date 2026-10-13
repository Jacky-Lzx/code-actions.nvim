local M = {}

local function read(uri)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.uri_from_bufnr(buf) == uri then
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end
  assert(uri:match("^file:"), "Cannot read this URI: " .. uri)
  local path = vim.uri_to_fname(uri)
  assert(vim.uv.fs_stat(path), "File does not exist: " .. path)
  local lines = vim.fn.readfile(path)
  return #lines == 0 and { "" } or lines
end

local function edited(lines, edits, encoding)
  local buf = vim.api.nvim_create_buf(false, true)
  local ok, result = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.lsp.util.apply_text_edits(vim.deepcopy(edits), buf, encoding)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end)
  vim.api.nvim_buf_delete(buf, { force = true })
  assert(ok, result)
  return result
end

-- Replay text edits in documentChanges order. Resource operations are shown as
-- summaries and modeled in memory, never performed while browsing the picker.
function M.lines(action, encoding)
  if not action.edit then
    return { "No text edit to preview. This action runs a command when confirmed." }
  end
  local out, files = {}, {}
  local function content(uri)
    if not files[uri] then
      files[uri] = read(uri)
    end
    return files[uri]
  end
  local function text(uri, edits)
    local before = content(uri)
    local after = edited(before, edits, encoding)
    files[uri] = after
    local diff = (vim.text and vim.text.diff or vim.diff)(
      table.concat(before, "\n") .. "\n",
      table.concat(after, "\n") .. "\n",
      { result_type = "unified", ctxlen = 3 }
    )
    if diff ~= "" then
      vim.list_extend(out, { "--- " .. uri, "+++ " .. uri })
      vim.list_extend(out, vim.split(diff, "\n", { trimempty = true }))
    end
  end
  local edit = action.edit
  if edit.documentChanges then
    for _, change in ipairs(edit.documentChanges) do
      if change.textDocument then
        text(change.textDocument.uri, change.edits)
      elseif change.kind == "create" then
        out[#out + 1] = "Create file: " .. change.uri
        files[change.uri] = { "" }
      elseif change.kind == "rename" then
        out[#out + 1] = "Rename file: " .. change.oldUri .. " -> " .. change.newUri
        files[change.newUri] = content(change.oldUri)
        files[change.oldUri] = nil
      elseif change.kind == "delete" then
        out[#out + 1] = "Delete file: " .. change.uri
        files[change.uri] = nil
      end
    end
  else
    local uris = vim.tbl_keys(edit.changes or {})
    table.sort(uris)
    for _, uri in ipairs(uris) do
      text(uri, edit.changes[uri])
    end
  end
  if #out == 0 then
    out = { "No text changes to preview." }
  end
  if action.command then
    out[#out + 1] = ""
    out[#out + 1] = "This action also runs a command; its effects are not included above."
  end
  return out
end

return M
