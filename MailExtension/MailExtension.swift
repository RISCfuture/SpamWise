import AppIntents
//
//  MailExtension.swift
//  MailExtension
//
//  Created by Tim Morgan on 10/15/26.
//

import MailKit

class MailExtension: NSObject, MEExtension {

  func handlerForMessageActions() -> any MEMessageActionHandler {
    return MessageActionHandler()
  }

}
