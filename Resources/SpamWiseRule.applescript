using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        -- Asks SpamWise to check each included account's newest Inbox mail first. No mail is placed in the URL.
        open location "spamwise://check-inbox"
    end perform mail action with messages
end using terms from
