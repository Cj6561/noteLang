-- noteLang plugin entry point
-- Registers user commands and autocmds.

local ok, preview = pcall(require, "notelang.preview")
if not ok then
  vim.notify("[noteLang] Failed to load notelang.preview: " .. tostring(preview), vim.log.levels.ERROR)
  return
end

-- ── Commands ──────────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command("NLPreview", function()
  preview.start(vim.api.nvim_get_current_buf())
end, { desc = "Open noteLang live preview in browser" })

vim.api.nvim_create_user_command("NLUpdate", function()
  local path = preview.get_preview_path()
  if vim.fn.filereadable(path) == 0 then
    vim.notify("[noteLang] No active preview. Run :NLPreview first.", vim.log.levels.WARN)
    return
  end
  preview.update(vim.api.nvim_get_current_buf())
  vim.notify("[noteLang] Preview updated.", vim.log.levels.INFO)
end, { desc = "Push current buffer to noteLang preview" })

vim.api.nvim_create_user_command("NLStop", function()
  preview.stop()
end, { desc = "Stop noteLang preview and clean up temp file" })

-- ── Autocmds ─────────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("noteLang", { clear = true })

-- Auto-update preview on save if a preview file is active
vim.api.nvim_create_autocmd("BufWritePost", {
  group   = group,
  pattern = "*.note",
  callback = function(ev)
    local path = preview.get_preview_path()
    if vim.fn.filereadable(path) == 1 then
      preview.update(ev.buf)
    end
  end,
  desc = "Auto-update noteLang preview on save",
})

-- Debounced live update while typing (no save required)
local _debounce_timer = nil
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group   = group,
  pattern = "*.note",
  callback = function(ev)
    local path = preview.get_preview_path()
    if vim.fn.filereadable(path) == 0 then return end
    if _debounce_timer then
      _debounce_timer:stop()
      _debounce_timer:close()
      _debounce_timer = nil
    end
    _debounce_timer = vim.loop.new_timer()
    _debounce_timer:start(500, 0, vim.schedule_wrap(function()
      if _debounce_timer then _debounce_timer:close(); _debounce_timer = nil end
      preview.update(ev.buf)
    end))
  end,
  desc = "Live-update noteLang preview while typing (debounced)",
})

-- Auto-open preview on BufEnter if config.auto_preview = true
vim.api.nvim_create_autocmd("BufEnter", {
  group   = group,
  pattern = "*.note",
  callback = function(ev)
    local cfg_ok, cfg = pcall(require, "notelang")
    if cfg_ok and cfg.config.auto_preview then
      local path = preview.get_preview_path()
      -- Only open if not already open for this file
      if vim.fn.filereadable(path) == 0 then
        preview.start(ev.buf)
      end
    end
  end,
  desc = "Auto-open noteLang preview on BufEnter",
})
