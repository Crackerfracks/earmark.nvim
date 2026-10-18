-- The table of user actions. Keymaps, <Plug> mappings and :Earmark subcommands are all
-- generated from it, so a key can never point at a function that doesn't exist.
--
-- An action: { name, desc, modes = { n = fn, x = fn }, cmd = fn(args, range)|false,
--              expr = true (mapping is an expression returning keys) }
-- The default key for an action is config.options.keys[name].
local M = {}

M.list = {} --- @type table[]
M.by_name = {} --- @type table<string, table>
M.default_command = 'info'

function M.register(spec)
  assert(spec.name and spec.desc, 'earmark: action needs name and desc')
  if not M.by_name[spec.name] then M.list[#M.list + 1] = spec end
  M.by_name[spec.name] = spec
  for i, s in ipairs(M.list) do
    if s.name == spec.name then M.list[i] = spec end
  end
  return spec
end

function M.plug(name)
  return '<Plug>(earmark-' .. name:gsub('_', '-') .. ')'
end

--- Define every <Plug> mapping, and the default keys from `keys` (false = none).
function M.apply_keymaps(keys)
  for _, a in ipairs(M.list) do
    for mode, fn in pairs(a.modes or {}) do
      vim.keymap.set(mode, M.plug(a.name), fn, {
        desc = 'earmark: ' .. a.desc,
        silent = true,
        expr = a.expr or nil,
        replace_keycodes = a.expr and true or nil,
      })
    end
  end
  if not keys then return end
  for _, a in ipairs(M.list) do
    local lhs = keys[a.name]
    if lhs and a.modes then
      for mode in pairs(a.modes) do
        vim.keymap.set(mode, lhs, M.plug(a.name), { desc = 'earmark: ' .. a.desc, remap = true, silent = true })
      end
    end
  end
end

--- Names of actions available as :Earmark subcommands.
function M.commands()
  local out = {}
  for _, a in ipairs(M.list) do
    if a.cmd ~= false then out[#out + 1] = a.name end
  end
  return out
end

--- Run `:Earmark <name> [args]`.
function M.run_command(cmd)
  local name = cmd.fargs[1] or M.default_command
  local a = M.by_name[name]
  if not a or a.cmd == false then
    vim.notify('earmark: unknown subcommand ' .. name, vim.log.levels.WARN)
    return
  end
  if a.cmd then return a.cmd(vim.list_slice(cmd.fargs, 2), cmd.range > 0 and { cmd.line1, cmd.line2 } or nil) end
  return a.modes.n()
end

return M
