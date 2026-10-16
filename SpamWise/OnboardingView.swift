import SwiftUI
import SpamWiseCore

struct OnboardingView: View {
  @Bindable var model: AppModel
  @State private var step = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Image(systemName: "envelope.badge.shield.half.filled").font(.largeTitle).foregroundStyle(
          .tint
        )
        Text("Welcome to SpamWise").font(.title.bold())
        Spacer(); Text("Step \(step + 1) of 4").foregroundStyle(.secondary)
      }
      ProgressView(value: Double(step + 1), total: 4).accessibilityLabel("Setup progress")
      Group {
        switch step {
          case 0:
            VStack(alignment: .leading, spacing: 16) {
              Text("Your Inbox, with fewer distractions").accessibilityIdentifier("setup.intro")
                .font(.title2.bold())
              Text(
                """
                SpamWise explains every decision. It never deletes mail or moves it to Trash. \
                Uncertain mail stays in Inbox with an orange flag.
                """
              )
              Label(
                """
                Anthropic receives your policy, correction examples, evidence, and a shortened \
                message only when local rules do not decide it.
                """,
                systemImage: "network"
              )
              Label(
                "RDAP services receive the sender’s domain when its age is not cached.",
                systemImage: "globe"
              )
              Label(
                "Your API key stays in Keychain. Start in dry run to see decisions before any mail changes.",
                systemImage: "key"
              )
              HelpButton(page: "what-data-is-sent")
            }
          case 1: KeyEntryView(model: model)
          case 2: MailConnectionView(model: model)
          default:
            VStack(alignment: .leading, spacing: 16) {
              Text("Try a dry run").font(.title2.bold())
              Text(
                """
                Optionally classify up to 20 recent Inbox messages. This sends eligible messages \
                to Anthropic using your key, and never requests a Mail action.
                """
              )
              Button("Dry run 20 recent messages") { model.scan(limit: 20) }.disabled(model.busy)
              Text("You can finish setup offline and return to Settings later.").foregroundStyle(
                .secondary
              )
              Text(model.status).font(.callout).textSelection(.enabled)
            }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      HStack {
        if step > 0 { Button("Back") { step -= 1 }.disabled(model.busy) }
        Spacer()
        if model.busy { ProgressView().controlSize(.small) }
        if step == 3 {
          Button("Finish setup") { model.finishSetup() }.accessibilityIdentifier("setup.finish")
            .buttonStyle(.borderedProminent).disabled(!model.storageReady || model.busy)
        } else {
          Button(step == 1 ? "Continue offline" : "Continue") { step += 1 }.accessibilityIdentifier(
            "setup.continue"
          ).buttonStyle(.borderedProminent).disabled(model.busy)
        }
      }
    }.padding(30).frame(width: 690, height: 580)
  }
}
struct KeyEntryView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Connect your Anthropic account").font(.title2.bold())
      Text(
        """
        Use your own API key. Verify sends a small synthetic message to Haiku 5.5 and saves the \
        key in Keychain only if verification succeeds.
        """
      )
      Link(
        "Open Claude Console",
        destination: URL(string: "https://console.anthropic.com/settings/keys")!
      )
      SecureField("Anthropic API key", text: $key).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Anthropic API key").accessibilityIdentifier("setup.key")
      Button("Verify and save key") {
        model.verifyKey(key); key = ""
      }.disabled(key.isEmpty || model.busy)
      Text(model.keyStatus).textSelection(.enabled).accessibilityLabel(
        "API key status: \(model.keyStatus)"
      )
      Text("Model: Claude Haiku 5.5 · no automatic model substitution").font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
struct MailConnectionView: View {
  @Bindable var model: AppModel
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Connect Apple Mail").font(.title2.bold())
        Text(
          "Allow Automation when asked. In Mail → Settings → Extensions, enable SpamWise to inspect incoming dry runs."
        )
        HStack {
          Button("Check Mail connection") { model.checkMail() }.accessibilityIdentifier(
            "mail.check"
          )
          Button("Connect Contacts (optional)") { model.requestContacts() }
        }.disabled(model.busy)
        Text(model.mailStatus).accessibilityIdentifier("mail.status").font(.callout).textSelection(
          .enabled
        )
        Text(model.contactsStatus).font(.caption).foregroundStyle(.secondary)
        Button("Import Inbox and Sent history") { model.importHistory() }.disabled(model.busy)
        DisclosureGroup("Enable actions with a disposable message") {
          VStack(alignment: .leading, spacing: 10) {
            Text(
              """
              Select one disposable Inbox message in Mail with a subject beginning [SpamWise \
              Probe]. The test moves it to that account’s Junk, back to Inbox, and adds an orange \
              flag. Repeat for each account. If the return fails, restore the test message from \
              Junk manually.
              """
            )
            Button("Test selected disposable message") { model.testDisposableMessage() }.disabled(
              model.busy
            )
            Text(
              "\(model.state.settings.validatedAccounts.count) accounts passed the action test. Dry run remains on until you turn it off in General."
            )
            Text(
              """
              For incoming actions, copy the bundled rule script into ~/Library/Application \
              Scripts/com.apple.mail/ and select it in a Mail rule. SpamWise also checks recent \
              Inbox mail once a minute while running.
              """
            )
            Button("Show Mail rule script in Finder") { model.revealRule() }
          }.padding(.top, 8)
        }
        HelpButton(page: "troubleshooting-mail-integration")
      }
    }
  }
}
