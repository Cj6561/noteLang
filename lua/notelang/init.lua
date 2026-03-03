local M = {}

M.config = {
  auto_preview = false,
  refresh_interval = 1500,
}

function M.setup(opts)
  if opts then
    for k, v in pairs(opts) do
      M.config[k] = v
    end
  end
end

return M
