import AppIntents
//
//  MailExtension.swift
//  MailExtension
//
//  Created by Tim Morgan on 10/15/26.
//

import MailKit

nonisolated final class MailExtension: NSObject, MEExtension {

  nonisolated func handlerForMessageActions() -> any MEMessageActionHandler {
    return MessageActionHandler()
  }

}
