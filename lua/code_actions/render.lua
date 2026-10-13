local M = {}

local function plain(ctx, lines)
  ctx.preview:reset()
  ctx.preview:set_title("Preview")
  ctx.preview:set_lines(lines)
  ctx.preview:highlight({ ft = "diff" })
end

-- Return a cancellation callback. Preview generation checks belong to the picker;
-- both process completion and ANSI rendering must check them before touching UI.
function M.start(ctx, lines, config, valid)
  local delta = config.delta
  local text = table.concat(lines, "\n")
  if
    config.backend ~= "delta"
    or not text:find("\n@@ ", 1, true)
    or vim.fn.executable(delta.command) ~= 1
  then
    plain(ctx, lines)
    return function() end
  end
  local cmd = {
    delta.command,
    "--paging=never",
    "--true-color=always",
    "--width=" .. vim.api.nvim_win_get_width(ctx.win),
  }
  if not vim.tbl_contains(delta.args, "--dark") and not vim.tbl_contains(delta.args, "--light") then
    cmd[#cmd + 1] = "--" .. vim.o.background
  end
  vim.list_extend(cmd, delta.args)
  local cancelled, process = false, nil
  local ok, result = pcall(vim.system, cmd, {
    stdin = text .. "\n",
    text = true,
    timeout = delta.timeout,
    cwd = ctx.item and ctx.item.root or nil,
    env = { PAGER = "cat", DELTA_PAGER = "cat" },
  }, function(output)
    vim.schedule(function()
      if cancelled or not valid() then
        return
      end
      if output.code ~= 0 or not output.stdout or output.stdout == "" then
        plain(ctx, lines)
        return
      end
      -- Snacks creates and cleans up the scratch buffer. The terminal is only
      -- an ANSI renderer; delta already finished and has no interactive pager.
      local buf = ctx.preview:scratch()
      ctx.preview:set_title("Preview · delta")
      local channel = vim.api.nvim_open_term(buf, {})
      vim.api.nvim_chan_send(channel, output.stdout)
    end)
  end)
  if not ok then
    plain(ctx, lines)
  else
    process = result
  end
  return function()
    cancelled = true
    if process and not process:is_closing() then
      process:kill(15)
    end
  end
end

return M
