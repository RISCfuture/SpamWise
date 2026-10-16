import AppIntents
//
//  MailExtension.swift
//  MailExtension
//
//  Created by Tim Morgan on 10/15/26.
//

import MailKit

class MailExtension: NSObject, MEExtension {
    
    func handlerForMessageActions() -> MEMessageActionHandler {
        // Use a shared instance for all messages, since there's
        // no state associated with performing actions.
        return MessageActionHandler()
    }

    
    
}

