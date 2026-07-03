local M = {}

local state = require("awards53.state")

M.buf = nil
M.win = nil

function M.open()

    local record = state.current_record()
    local field = state.field_name()

    vim.cmd("tabnew")

    vim.notify(
        string.format("Редагування поля: %s", field),
        vim.log.levels.INFO
    )

    M.buf = vim.api.nvim_get_current_buf()
    M.win = vim.api.nvim_get_current_win()

    vim.bo[M.buf].buftype = ""
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].swapfile = false
    vim.bo[M.buf].filetype = "org"


    vim.api.nvim_buf_set_name(
        M.buf,
        string.format(
            "AWARDS53 %d/%d : %s",
            state.index(),
            state.count(),
            field
        )
    )

    vim.api.nvim_buf_set_lines(
        M.buf,
        0,
        -1,
        false,
        record[field] or {}
    )

    -- тут включаем spellcheck
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "uk,ru,en"   
  
    local group = vim.api.nvim_create_augroup(
        "Awards53Editor" .. M.win,
        { clear = true }
    )

    vim.api.nvim_create_autocmd("WinClosed", {

        group = group,

        callback = function(args)

            if tonumber(args.match) ~= M.win then
                return
            end

            state.set_mode("NORMAL")
            
            require("awards53.ui").redraw()

            vim.api.nvim_del_augroup_by_id(group)

        end,

    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {

        buffer = M.buf,

        callback = function()
            M.save()
        end,

    })

    vim.api.nvim_buf_create_user_command(
        M.buf,
        "W",
        function()
            M.save()
        end,
        {}
    )

end


function M.save()

    local lines = vim.api.nvim_buf_get_lines(
        M.buf,
        0,
        -1,
        false
    )

    local record = state.current_record()
    local field = state.field_name()

    record[field] = lines

    vim.bo[M.buf].modified = false

    state.set_mode("NORMAL")

    require("awards53.ui").redraw()

    vim.cmd("tabclose!")

end

return M
