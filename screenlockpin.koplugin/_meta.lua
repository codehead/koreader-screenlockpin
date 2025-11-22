local _ = require("gettext")

return {
    -- KOReader meta information
    name = "screenlockpin",
    fullname = _("ScreenLock PIN"),
    description = _([[Protect your device privacy with a PIN.]]),

    -- used to check for latest plugin updates
    update_url = "https://api.github.com/repos/oleasteo/koreader-screenlockpin/releases/latest",
    -- additional meta information; no effect in code
    version = "2025.11-1",
    website_url = "https://github.com/oleasteo/koreader-screenlockpin",
    repository_url = "https://github.com/oleasteo/koreader-screenlockpin.git",
}
