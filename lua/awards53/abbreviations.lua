
local M = {}

local dictionary = {
  ["3АКого"]   = "3 армійського корпусу",
  ["іменіВМ"]  = "імені князя Володимира Мономаха",
  ["53ди"]     = "53 окремої механізованої бригади",
  ["53да"]     = "53 окрема механізована бригада",
  ["53ді"]     = "53 окремій механізованій бригаді",
}

local keys = {}
for k in pairs(dictionary) do table.insert(keys, k) end
table.sort(keys, function(a,b) return #a > #b end)

function M.register_buffer_abbreviations(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local before = line:sub(1, col0)

      for _, key in ipairs(keys) do
        if before:sub(-#key) == key then
          local value = dictionary[key]
          local start_col = col0 - #key
          local end_col = col0

          vim.api.nvim_buf_set_text(bufnr, row-1, start_col, row-1, end_col, { value })
          vim.api.nvim_win_set_cursor(0, { row, start_col + #value })

          return
        end
      end
    end,
  })
end

return M
