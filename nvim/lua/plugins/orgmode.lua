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
        end,
    },

}
