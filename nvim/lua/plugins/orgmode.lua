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
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "orgagenda",
                callback = function(event)
                    vim.schedule(function()
                        if vim.api.nvim_win_is_valid(0) then
                            local help_text = table.concat({
                                    "%#OrgHelpText#  ",

                                    "%#OrgHelpKey# [oct] ",
                                    "%#OrgHelpText#Нове ",

                                    "%#OrgHelpSep#",

                                    "%#OrgHelpKey# [t] ",
                                    "%#OrgHelpText#TODO/DONE ",

                                    "%#OrgHelpSep#",

                                    "%#OrgHelpKey# [o$] ",
                                    "%#OrgHelpText#Архів ",

                                    "%#OrgHelpSep#",

                                    "%#OrgHelpKey# [oid] ",
                                    "%#OrgHelpText#Дедлайн ",

                                    "%#OrgHelpSep#",

                                    "%#OrgHelpKey# [ois] ",
                                    "%#OrgHelpText#Розклад ",

                                    "%#OrgHelpSep#",

                                    "%#OrgHelpKey# [oaa] ",
                                    "%#OrgHelpText#Agenda",
                                })
                            vim.wo[0].winbar = help_text
                        end
                    end)
                end,
            })
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "orgagenda",
                callback = function()
                    vim.schedule(function()
                        -- Робимо кілька кроків вниз від початку буфера, щоб стати на реальну задачу
                        pcall(vim.cmd, "normal! gg 1j")
                    end)
                end,
            })
        end,
    },

}
