return {
  {
    "nvim-orgmode/orgmode",

    ft = { "org" },

    config = function()
      require("orgmode").setup({
        win_split_mode = "tabnew",

        org_agenda_files = {
          "~/awards/org/*.org",
        },

        org_default_notes_file = "~/awards/org/diary.org",

        org_todo_keywords = {
          "TODO",
          "NEXT",
          "WAIT",
          "|",
          "DONE",
          "CANCELLED",
        },

        org_capture_templates = {
          t = {
            description = "Завдання",
            template = "* TODO %?\nSCHEDULED: %T",
          },
        },
      })

      ----------------------------------------------------------------
      -- WINBAR
      ----------------------------------------------------------------

      local function update_orgagenda_winbar(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        if vim.bo[bufnr].filetype ~= "orgagenda" then
          return
        end

        local winid = vim.fn.bufwinid(bufnr)

        if winid == -1 or not vim.api.nvim_win_is_valid(winid) then
          return
        end

        vim.wo[winid].winbar = "%#OrgHelpText#   "
          .. "%#OrgHelpKey# [?] "
          .. "%#OrgHelpText#- Довідка"
      end

      ----------------------------------------------------------------
      -- HELP
      ----------------------------------------------------------------

      local function show_orgagenda_help()
        local bufnr = vim.api.nvim_get_current_buf()

        if vim.bo[bufnr].filetype ~= "orgagenda" then
          return
        end

        ------------------------------------------------------------
        -- Получаем mappings текущего orgagenda
        ------------------------------------------------------------

        local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")

        local entries = {}
        local seen = {}

        for _, map in ipairs(maps) do
          local lhs = map.lhs
          local desc = map.desc

          if lhs and desc and desc ~= "" and not seen[lhs] then
            seen[lhs] = true

            table.insert(entries, {
              key = lhs,
              desc = desc,
            })
          end
        end

        ------------------------------------------------------------
        -- Сортировка
        ------------------------------------------------------------

        table.sort(entries, function(a, b)
          return a.key < b.key
        end)

        ------------------------------------------------------------
        -- Формируем текст
        ------------------------------------------------------------

        local lines = { "" }

        ------------------------------------------------------------
        -- Ширина колонки клавиш
        ------------------------------------------------------------

        local key_width = 0

        for _, item in ipairs(entries) do
          key_width = math.max(key_width, vim.fn.strdisplaywidth(item.key))
        end

        ------------------------------------------------------------
        -- Заполняем строки
        ------------------------------------------------------------

        for _, item in ipairs(entries) do
          local current_width = vim.fn.strdisplaywidth(item.key)
          local padding = string.rep(" ", key_width - current_width)

          table.insert(
            lines,
            "  " .. item.key .. padding .. "    " .. item.desc
          )
        end

        table.insert(lines, "")
        table.insert(lines, "  <Esc> / q — закрити")
        table.insert(lines, "")

        ------------------------------------------------------------
        -- Размер окна
        ------------------------------------------------------------

        local width = 0

        for _, line in ipairs(lines) do
          width = math.max(width, vim.fn.strdisplaywidth(line))
        end

        width = math.min(width + 2, vim.o.columns - 4)

        local height = math.min(#lines, vim.o.lines - 6)

        ------------------------------------------------------------
        -- Создаём buffer
        ------------------------------------------------------------

        local help_buf = vim.api.nvim_create_buf(false, true)

        vim.bo[help_buf].bufhidden = "wipe"

        vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)

        vim.bo[help_buf].modifiable = false

        ------------------------------------------------------------
        -- Позиция окна
        ------------------------------------------------------------

        local row = math.floor((vim.o.lines - height) / 2 - 1)
        local col = math.floor((vim.o.columns - width) / 2)

        ------------------------------------------------------------
        -- Floating window
        ------------------------------------------------------------

        local win = vim.api.nvim_open_win(help_buf, true, {
          relative = "editor",
          row = row,
          col = col,
          width = width,
          height = height,
          style = "minimal",
          border = "rounded",
          title = " Orgmode Help ",
          title_pos = "center",
        })

        vim.wo[win].wrap = false
        vim.wo[win].cursorline = true

        ------------------------------------------------------------
        -- Закрытие
        ------------------------------------------------------------

        local function close()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end

        vim.keymap.set("n", "q", close, {
          buffer = help_buf,
          silent = true,
        })

        vim.keymap.set("n", "<Esc>", close, {
          buffer = help_buf,
          silent = true,
        })
      end

      ----------------------------------------------------------------
      -- ORGAGENDA AUTOCMD & АКТИВАЦИЯ
      ----------------------------------------------------------------

      local function orgagenda_activate_item(bufnr)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end

          local win = vim.fn.bufwinid(bufnr)
          if win == -1 or not vim.api.nvim_win_is_valid(win) then
            return
          end

          local total = vim.api.nvim_buf_line_count(bufnr)

          -- Ищем первую строку с реальным заданием (пропускаем служебный заголовок)
          for i = 1, total do
            local text = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""
            if text ~= "" and not text:match("^Global list of TODO items") then
              vim.api.nvim_win_set_cursor(win, { i, 0 })
              break
            end
          end
        end)
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "orgagenda",
        callback = function(event)
          local bufnr = event.buf

          -- ? = help
          vim.keymap.set("n", "?", show_orgagenda_help, {
            buffer = bufnr,
            silent = true,
            desc = "Показати клавіші orgmode",
          })

          -- Переопределяем 'r' с небольшой задержкой для асинхронного обновления orgmode
          vim.keymap.set("n", "r", function()
            vim.cmd("normal! r")
            -- Ждем 100 мс, пока orgmode завершит перерисовку аженды, затем смещаем курсор
            vim.defer_fn(function()
              orgagenda_activate_item(bufnr)
            end, 100)
          end, {
            buffer = bufnr,
            silent = true,
            noremap = true,
            desc = "Оновити agenda",
          })

          vim.defer_fn(function()
            update_orgagenda_winbar(bufnr)
            orgagenda_activate_item(bufnr)
          end, 150)
        end,
      })

      -- Автоматический сдвиг курсора при изменении содержимого буфера (на случай любых обновлений)
      vim.api.nvim_create_autocmd({ "BufReadPost", "TextChanged" }, {
        pattern = "*",
        callback = function(event)
          if vim.bo[event.buf].filetype == "orgagenda" then
            vim.defer_fn(function()
              orgagenda_activate_item(event.buf)
            end, 50)
          end
        end,
      })

      vim.api.nvim_create_autocmd("FocusGained", {
        callback = function()
          local buf = vim.api.nvim_get_current_buf()
          if vim.bo[buf].filetype == "orgagenda" then
            orgagenda_activate_item(buf)
          end
        end,
      })

      ----------------------------------------------------------------
      -- Команда запуска TODOs
      ----------------------------------------------------------------

      vim.api.nvim_create_user_command("OrgTodos", function()
        vim.schedule(function()
          require("orgmode").agenda:todos()
        end)
      end, {})
    end,
  },
}

