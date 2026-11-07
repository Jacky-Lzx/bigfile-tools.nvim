-- Buffer protection is independent of editor UI and plugin-manager lifecycle.
local M = {}
local api = vim.api
local defaults = {
  max_bytes = 1.5 * 1024 * 1024,
  max_line_length = 1000,
  filetype = "bigfile",
  buffer = {},
  window = { foldmethod = "manual", foldexpr = "0", conceallevel = 0, statuscolumn = "" },
}
local options = vim.deepcopy(defaults)
local protected, active, registered, bypass = {}, false, false, false
local group
local function buffer(buf)
  return buf and buf ~= 0 and buf or api.nvim_get_current_buf()
end
local function restore_window(win, values)
  if not api.nvim_win_is_valid(win) then
    return
  end
  for name, record in pairs(values) do
    if api.nvim_get_option_value(name, { win = win }) == record.installed then
      api.nvim_set_option_value(name, record.before, { win = win })
    end
  end
end
local function apply_window(buf, win)
  local state = protected[buf]
  if not state then
    return
  end
  local values = state.windows[win] or {}
  state.windows[win] = values
  for name, value in pairs(options.window) do
    if not values[name] then
      values[name] = { before = api.nvim_get_option_value(name, { win = win }), installed = value }
    end
    api.nvim_set_option_value(name, value, { win = win })
  end
end
function M.detect(buf, path)
  buf = buffer(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return false
  end
  path = path or api.nvim_buf_get_name(buf)
  if options.exclude and options.exclude(buf, path) then
    return false
  end
  local lines = api.nvim_buf_line_count(buf)
  local size = api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_offset(buf, lines) or vim.fn.getfsize(path)
  return (options.max_bytes and size > options.max_bytes)
    or (options.max_line_length and size > 0 and (size - lines) / math.max(1, lines) > options.max_line_length)
    or false
end
function M.protect(buf)
  if not active then
    M.setup()
  end
  buf = buffer(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return false
  end
  if protected[buf] then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      apply_window(buf, win)
    end
    return true
  end
  local state = {
    variables = {},
    windows = {},
    filetype = vim.bo[buf].filetype,
    highlighted = vim.treesitter.highlighter.active[buf] ~= nil,
  }
  protected[buf] = state
  local variables = vim.tbl_extend("force", options.buffer, { bigfile = true })
  for name, value in pairs(variables) do
    state.variables[name] = { before = vim.b[buf][name], installed = value }
    vim.b[buf][name] = value
  end
  pcall(vim.treesitter.stop, buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_window(buf, win)
  end
  -- A FileType classifier sets the filetype itself after this callback returns.
  if options.filetype and not bypass then
    vim.bo[buf].filetype = options.filetype
  end
  return true
end
function M.release(buf)
  buf = buffer(buf)
  local state = protected[buf]
  if not state then
    return false
  end
  protected[buf] = nil
  if not api.nvim_buf_is_valid(buf) then
    return true
  end
  for win, values in pairs(state.windows) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
      restore_window(win, values)
    end
  end
  for name, record in pairs(state.variables) do
    if vim.b[buf][name] == record.installed then
      vim.b[buf][name] = record.before
    end
  end
  if options.filetype and vim.bo[buf].filetype == options.filetype then
    local ft = state.filetype
    if ft == "" or ft == options.filetype then
      bypass = true
      local ok, detected = pcall(vim.filetype.match, { buf = buf })
      bypass = false
      ft = ok and detected or ""
    end
    vim.bo[buf].filetype = ft or ""
  end
  if state.highlighted and not vim.treesitter.highlighter.active[buf] then
    pcall(vim.treesitter.start, buf)
  end
  return true
end
function M.info()
  local buffers = {}
  for buf in pairs(protected) do
    if api.nvim_buf_is_valid(buf) then
      buffers[#buffers + 1] = { buf = buf, name = api.nvim_buf_get_name(buf) }
    end
  end
  table.sort(buffers, function(a, b)
    return a.buf < b.buf
  end)
  return { enabled = active, buffers = buffers, options = vim.deepcopy(options) }
end
function M.dispose()
  active = false
  if group then
    api.nvim_del_augroup_by_id(group)
    group = nil
  end
  local buffers = vim.tbl_keys(protected)
  for _, buf in ipairs(buffers) do
    M.release(buf)
  end
  options = vim.deepcopy(defaults)
end
function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "bigfile-tools: setup expects a table")
  local next_options = vim.tbl_extend("force", vim.deepcopy(defaults), vim.deepcopy(opts or {}))
  for name in pairs(next_options) do
    assert(defaults[name] ~= nil or name == "exclude", "Unknown option: " .. name)
  end
  for _, name in ipairs({ "max_bytes", "max_line_length" }) do
    local value = next_options[name]
    assert(value == false or type(value) == "number" and value > 0 and value < math.huge, "Invalid " .. name)
  end
  assert(
    next_options.filetype == false or type(next_options.filetype) == "string" and next_options.filetype ~= "",
    "Invalid filetype"
  )
  assert(
    type(next_options.buffer) == "table" and type(next_options.window) == "table",
    "buffer/window must be option tables"
  )
  assert(next_options.exclude == nil or type(next_options.exclude) == "function", "exclude must be a function")
  for name, value in pairs(next_options.window) do
    local metadata = api.nvim_get_option_info2(name, {})
    assert(metadata.scope == "win", "Expected a window option: " .. name)
    assert(
      type(value) == ({ boolean = "boolean", number = "number", string = "string" })[metadata.type],
      "Invalid window option value: " .. name
    )
  end
  for name, value in pairs(next_options.buffer) do
    assert(type(name) == "string" and name:match("^[%w_]+$"), "Invalid buffer variable")
    assert(
      type(value) == "boolean" or type(value) == "number" or type(value) == "string",
      "Buffer variables must be scalar"
    )
  end
  if next_options.window.foldmethod then
    assert(
      vim.list_contains({ "manual", "indent", "expr", "marker", "syntax", "diff" }, next_options.window.foldmethod),
      "Invalid foldmethod"
    )
  end
  if next_options.window.conceallevel then
    local value = next_options.window.conceallevel
    assert(value % 1 == 0 and value >= 0 and value <= 3, "Invalid conceallevel")
  end
  if active and vim.deep_equal(options, next_options) then
    return M
  end
  M.dispose()
  options, active = next_options, true
  group = api.nvim_create_augroup("BigfileTools", { clear = true })
  if not registered then
    vim.filetype.add({
      pattern = {
        [".*"] = {
          function(path, buf)
            if not active or bypass or not buf or not api.nvim_buf_is_valid(buf) then
              return
            end
            local name = api.nvim_buf_get_name(buf)
            if
              (vim.uv.fs_realpath(path) or vim.fs.normalize(path))
              ~= (vim.uv.fs_realpath(name) or vim.fs.normalize(name))
            then
              return
            end
            if M.detect(buf, path) then
              bypass = true
              M.protect(buf)
              bypass = false
              return options.filetype or nil
            end
          end,
          { priority = math.huge },
        },
      },
    })
    registered = true
  end
  api.nvim_create_autocmd({ "BufReadPost", "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      if active and M.detect(ev.buf) then
        M.protect(ev.buf)
      end
    end,
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if protected[ev.buf] then
        apply_window(ev.buf, api.nvim_get_current_win())
      end
    end,
  })
  api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    callback = function(ev)
      local state, win = protected[ev.buf], api.nvim_get_current_win()
      if state and state.windows[win] then
        restore_window(win, state.windows[win])
        state.windows[win] = nil
      end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      protected[ev.buf] = nil
    end,
  })
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and M.detect(buf) then
      M.protect(buf)
    end
  end
  return M
end
return M
