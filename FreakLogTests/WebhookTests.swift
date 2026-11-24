import CoreData
import XCTest
@testable import FreakLog

@MainActor
final class WebhookTests: XCTestCase {
  func testNoteMessagesUseTheNoteLayout() {
    let settings = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "Sam",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(forNote: "Peaking", settings: settings), "Sam: Peaking")
    let anonymous = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(forNote: "Peaking", settings: anonymous), "Peaking")
  }

  func testIngestionMessagesKeepTheirLayout() {
    let data = WebhookManager.WebhookDataSnapshot(
      user: "",
      substance: "Caffeine",
      substanceDisplayName: "Caffeine",
      dose: 100,
      units: "mg",
      isEstimate: true,
      route: "oral",
      site: "",
      note: "")
    let settings = WebhookManager.WebhookSettingsSnapshot(
      template: WebhookService.defaultTemplate,
      noteTemplate: WebhookService.defaultNoteTemplate,
      username: "Sam",
      isHyperlinked: false,
      substanceInfoUrl: "")
    XCTAssertEqual(WebhookService.content(for: data, settings: settings), "Sam: ~100 mg Caffeine via oral")
  }

  func testTimedNoteMessagesAreDeletedWithTheNote() throws {
    let context = PersistenceController(inMemory: true).viewContext
    let preset = WebhookPreset(context: context)
    preset.url = "https://example.com/webhook"
    let note = TimedNote(context: context)
    note.note = "Peaking"
    let message = WebhookMessage(context: context)
    message.messageId = "1"
    message.webhookPreset = preset
    message.timedNote = note
    try context.save()
    XCTAssertEqual(note.webhookMessagesSorted, [message])

    context.delete(note)
    try context.save()
    XCTAssertEqual(try context.count(for: WebhookMessage.fetchRequest()), 0)
    XCTAssertTrue(preset.messages?.count == 0)
  }
}
