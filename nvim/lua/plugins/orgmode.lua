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
                            local help_text ="%#OrgHelpBar#  [oct] Нове | [t] TODO/DONE | [o$] В архів | [oid] Дедлайн | [ois] Розклад"
                            vim.wo[0].winbar = help_text
                        end
                    end)
                end,
            })

        end,
    },

}
