vim.opt.rtp:prepend(vim.env.CODE_ACTIONS_ROOT)
local preview = require("code_actions.preview")
local count = 0
local function check(condition, label)
  assert(condition, label)
  count = count + 1
end
local function contains(lines, text)
  return table.concat(lines, "\n"):find(text, 1, true) ~= nil
end
local function buffer(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf, vim.uri_from_bufnr(buf)
end
local function edit(first, last, text)
  return {
    range = { start = { line = 0, character = first }, ["end"] = { line = 0, character = last } },
    newText = text,
  }
end
local buf, uri = buffer(".lua", { "中文😀foo", "unsaved" })
local other, other_uri = buffer(".lua", { "second" })
local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local original_buffers = #vim.api.nvim_list_bufs()
local action = {
  edit = { changes = { [uri] = { edit(4, 7, "bar") }, [other_uri] = { edit(0, 6, "changed") } } },
}
local lines = preview.lines(action, "utf-16")
check(contains(lines, "+中文😀bar"), "UTF-16 handles Chinese and surrogate pairs")
check(contains(lines, "+changed"), "multiple files use loaded unsaved contents")
check(
  vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
  "preview leaves original contents intact"
)
check(#vim.api.nvim_list_bufs() == original_buffers, "preview scratch buffers are deleted")
check(action.edit.changes[uri][1]._index == nil, "preview does not mutate server edits")
check(
  contains(
    preview.lines({ edit = { changes = { [uri] = { edit(10, 13, "bar") } } } }, "utf-8"),
    "+中文😀bar"
  ),
  "UTF-8 offsets"
)
check(
  contains(
    preview.lines({ edit = { changes = { [uri] = { edit(3, 6, "bar") } } } }, "utf-32"),
    "+中文😀bar"
  ),
  "UTF-32 offsets"
)
local created = vim.uri_from_fname(vim.fn.tempname())
local renamed = vim.uri_from_fname(vim.fn.tempname())
lines = preview.lines({
  edit = {
    documentChanges = {
      { kind = "create", uri = created },
      { textDocument = { uri = created }, edits = { edit(0, 0, "new") } },
      { kind = "rename", oldUri = created, newUri = renamed },
      { textDocument = { uri = renamed }, edits = { edit(0, 3, "renamed") } },
      { kind = "delete", uri = renamed },
    },
  },
}, "utf-16")
check(
  contains(lines, "+renamed") and contains(lines, "Delete file:"),
  "resource operations preserve document order"
)
check(
  vim.uv.fs_stat(vim.uri_to_fname(created)) == nil
    and vim.uv.fs_stat(vim.uri_to_fname(renamed)) == nil,
  "resource preview has no filesystem effects"
)
check(
  contains(preview.lines({ command = "test" }, "utf-16"), "No text edit"),
  "command-only preview"
)
check(
  contains(preview.lines({ edit = {}, command = {} }, "utf-16"), "also runs a command"),
  "additional command warning"
)
local bad_uri = vim.uri_from_fname(vim.fn.tempname())
local ok =
  pcall(preview.lines, { edit = { changes = { [bad_uri] = { edit(0, 0, "x") } } } }, "utf-16")
check(not ok, "missing files produce an unavailable preview instead of fabricating contents")
local invalid = { edit = { changes = { [uri] = { { newText = "x" } } } } }
check(not pcall(preview.lines, invalid, "utf-16"), "invalid edits fail")
check(
  #vim.api.nvim_list_bufs() == original_buffers,
  "failed edit simulation also deletes scratch buffer"
)

local captured, picker, calls, cancelled, applied, notices = nil, nil, {}, {}, {}, {}
local clients = {}
local next_request = 0
local function client(id)
  local value = { id = id, offset_encoding = "utf-16" }
  function value:supports_method()
    return true
  end
  function value:request(_, a, cb)
    next_request = next_request + 1
    calls[#calls + 1] = { callback = cb, action = a, id = next_request, client = id }
    return true, next_request
  end
  function value:cancel_request(request)
    cancelled[#cancelled + 1] = { id = request, client = id }
  end
  function value:exec_cmd(command, ctx)
    applied[#applied + 1] = { command = command, ctx = ctx }
  end
  clients[id] = value
  return value
end
client(11)
client(12)
vim.lsp.get_client_by_id = function(id)
  return clients[id]
end
vim.notify = function(message)
  notices[#notices + 1] = message
end
package.loaded["snacks.picker"] = {
  pick = function(options)
    captured = options
    picker = { selected = options.items[1] }
    function picker:current()
      return self.selected
    end
    function picker:close()
      options.on_close()
    end
    return picker
  end,
}
local delegated = 0
vim.ui.select = function()
  delegated = delegated + 1
end
local plugin = require("code_actions")
plugin.setup({ resolve_timeout = 30 })
local wrapped = vim.ui.select
plugin.setup()
check(vim.ui.select == wrapped, "setup is idempotent")
vim.ui.select({ "ordinary" }, {}, function() end)
check(delegated == 1, "ordinary selects delegate")
vim.ui.select({ { incompatible = true } }, { kind = "codeaction" }, function() end)
check(delegated == 2, "unknown native item shape delegates")

local cancellations = 0
local function open(entries)
  vim.ui.select(entries, {
    kind = "codeaction",
    format_item = function(entry)
      return entry.action.title
    end,
  }, function(value)
    check(value == nil, "native callback receives cancellation only")
    cancellations = cancellations + 1
  end)
  return captured, picker
end
local function entry(title, id, a)
  return {
    action = vim.tbl_extend("force", { title = title }, a or {}),
    ctx = { client_id = id or 11, bufnr = buf, method = "textDocument/codeAction" },
  }
end
local function context(item)
  local p = { lines = {} }
  function p:reset()
    self.lines = {}
  end
  function p:set_lines(value)
    self.lines = value
  end
  function p:highlight() end
  function p:set_title() end
  return { item = item, picker = picker, preview = p }
end
local function flush()
  vim.wait(10, function()
    return false
  end, 1)
end
local options, current_picker = open({ entry("First"), entry("Second", 12) })
local first, second = options.items[1], options.items[2]
local ctx1 = context(first)
options.preview(ctx1)
local request1 = calls[#calls]
current_picker.selected = second
local ctx2 = context(second)
options.preview(ctx2)
local request2 = calls[#calls]
request1.callback(nil, { title = "First", edit = action.edit })
flush()
check(contains(ctx1.preview.lines, "Resolving"), "late previous-item response is ignored")
request2.callback(nil, { title = "Second", command = { command = "second" } })
flush()
check(contains(ctx2.preview.lines, "No text edit"), "current-item response appears")
local n = #calls
options.confirm(current_picker, second)
flush()
check(#calls == n, "confirm reuses cached resolve")
check(applied[#applied].command.command == "second", "resolved command executes")
check(cancellations == 0, "successful apply does not call native cancellation callback")

options, current_picker = open({ entry("Cancel") })
local ctx = context(options.items[1])
options.preview(ctx)
local pending_request = calls[#calls]
local cancel_before = #cancelled
current_picker:close()
pending_request.callback(nil, { title = "Cancel", command = { command = "should-not-run" } })
flush()
check(#cancelled == cancel_before + 1 and cancellations == 1, "close cancels request once")
check(contains(ctx.preview.lines, "Resolving"), "closed picker ignores late response")

options, current_picker = open({ entry("Error") })
ctx = context(options.items[1])
options.preview(ctx)
calls[#calls].callback({ message = "resolve failed" })
flush()
check(contains(ctx.preview.lines, "resolve failed"), "resolve failure is shown")
current_picker:close()

options, current_picker = open({ entry("Timeout") })
ctx = context(options.items[1])
options.preview(ctx)
vim.wait(100, function()
  return contains(ctx.preview.lines, "timed out")
end, 1)
check(contains(ctx.preview.lines, "timed out"), "asynchronous resolution timeout")
current_picker:close()

options, current_picker = open({ entry("Changed", 11, { command = "direct" }) })
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "changed while browsing" })
local applied_before = #applied
options.confirm(current_picker, options.items[1])
flush()
check(
  #applied == applied_before and notices[#notices]:find("buffer changed"),
  "changed original buffer refuses apply"
)
current_picker:close()

options, current_picker = open({ entry("Disabled", 11, { disabled = { reason = "unavailable" } }) })
options.confirm(current_picker, options.items[1])
flush()
check(
  #applied == applied_before and notices[#notices] == "unavailable",
  "disabled action refuses apply"
)
current_picker:close()

options, current_picker = open({ entry("Disconnect") })
clients[11] = nil
options.confirm(current_picker, options.items[1])
flush()
check(notices[#notices] == "Language server disconnected", "disconnected server is reported")
current_picker:close()
client(11)

options, current_picker =
  open({ entry("Text", 11, { edit = { changes = { [other_uri] = { edit(0, 6, "applied") } } } }) })
options.confirm(current_picker, options.items[1])
calls[#calls].callback(nil, { title = "Text", edit = options.items[1].entry.action.edit })
flush()
check(
  vim.api.nvim_buf_get_lines(other, 0, 1, false)[1] == "applied",
  "confirmation uses native workspace edit"
)

options, current_picker = open({
  entry("Already complete", 11, {
    edit = { changes = { [other_uri] = { edit(0, 7, "complete") } } },
    command = { command = "complete" },
  }),
})
n = #calls
options.confirm(current_picker, options.items[1])
flush()
check(
  #calls == n and applied[#applied].command.command == "complete",
  "complete edit and command do not resolve again"
)
check(vim.api.nvim_buf_get_lines(other, 0, 1, false)[1] == "complete", "edit precedes command")

options, current_picker = open({ entry("Fallback", 11, { command = { command = "fallback" } }) })
options.confirm(current_picker, options.items[1])
calls[#calls].callback({ message = "optional resolve failed" })
flush()
check(
  applied[#applied].command.command == "fallback",
  "resolve failure preserves executable original command"
)

options, current_picker = open({ entry("Confirm while resolving") })
ctx = context(options.items[1])
options.preview(ctx)
n = #calls
options.confirm(current_picker, options.items[1])
options.confirm(current_picker, options.items[1])
check(#calls == n, "confirmation shares the pending preview request")
applied_before = #applied
calls[#calls].callback(nil, { title = "Confirmed", command = { command = "once" } })
flush()
check(#applied == applied_before + 1, "repeated Enter executes once")

local alternate = 0
vim.ui.select = function()
  alternate = alternate + 1
end
plugin.setup()
vim.ui.select({ "ordinary" }, {}, function() end)
check(alternate == 1, "reinstall follows new select provider without recursion")
if vim.v.vim_did_enter == 0 then
  local after_ui = 0
  vim.ui.select = function()
    after_ui = after_ui + 1
  end
  vim.api.nvim_exec_autocmds("UIEnter", {})
  flush()
  vim.ui.select({ "ordinary" }, {}, function() end)
  check(after_ui == 1, "UIEnter reinstalls adapter after Snacks installs its select provider")
end
print(("code-actions: %d assertions passed"):format(count))
vim.cmd("qa!")
