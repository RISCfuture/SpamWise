using terms from application "Mail"
    on perform mail action with messages theMessages for rule theRule
        -- Asks SpamWise to check each included account's newest Inbox mail first. No mail is placed in the URL.
        -- open -g delivers the URL without bringing SpamWise forward, so Mail stays in front.
        do shell script "/usr/bin/open -g 'spamwise://check-inbox'"
    end perform mail action with messages
end using terms from
