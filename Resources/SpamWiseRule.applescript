using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        -- The app re-queries Mail with account-scoped identity. No raw mail is placed in the URL.
        open location "spamwise://check-inbox"
    end perform mail action with messages
end using terms from
