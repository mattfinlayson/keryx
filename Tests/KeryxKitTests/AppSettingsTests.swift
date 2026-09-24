import Testing
import Foundation
@testable import KeryxKit

@Suite("AppSettings")
struct AppSettingsTests {

    @Test("default settings use the home inbox, unlimited age, no opener rules")
    func defaults() {
        let settings = AppSettings.default

        #expect(settings.inboxURL == nil)
        #expect(settings.maxFileAge == nil)
        #expect(settings.openers.isEmpty)
    }

    @Test("in-memory store round-trips settings")
    func inMemoryStoreRoundTrip() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(
            inboxURL: URL(fileURLWithPath: "/tmp/inbox"),
            maxFileAge: 86400,
            openers: ["md": "Marked 2"]
        )

        store.save(settings)

        #expect(store.settings == settings)
    }

    @Test("opener extension keys are normalized: *.md, .MD, and md are equivalent")
    func normalizesOpenerKeys() {
        let settings = AppSettings(
            inboxURL: nil,
            openers: ["*.md": "Marked 2", ".LOG": "Console", " txt ": "TextEdit"]
        )

        #expect(settings.openers.keys.sorted() == ["log", "md", "txt"])
        #expect(settings.openers["md"] == "Marked 2")
        #expect(settings.openers["log"] == "Console")
        #expect(settings.openers["txt"] == "TextEdit")
    }

    @Test("a bare * rule is kept and acts as the all-files fallback")
    func starRuleIsPreserved() {
        let settings = AppSettings(inboxURL: nil, openers: ["*": "Marked 2"])

        #expect(settings.openers == ["*": "Marked 2"])
    }

    @Test("opener(forExtension:) prefers the exact match, then the * rule, then nil")
    func openerLookup() {
        let settings = AppSettings(
            inboxURL: nil,
            openers: ["*.md": "Marked 2", "*": "TextEdit"]
        )

        #expect(settings.opener(forExtension: "md") == "Marked 2")
        #expect(settings.opener(forExtension: "MD") == "Marked 2")
        #expect(settings.opener(forExtension: ".md") == "Marked 2")
        #expect(settings.opener(forExtension: "log") == "TextEdit")
        #expect(settings.opener(forExtension: "") == nil)
    }
}

@Suite("UserDefaultsSettingsStore")
struct UserDefaultsSettingsStoreTests {

    private func makeStore() -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: "keryx-test-\(UUID().uuidString)")!)
    }

    @Test("round-trips inbox path, max file age, and opener rules")
    func roundTrip() {
        let store = makeStore()
        let settings = AppSettings(
            inboxURL: URL(fileURLWithPath: "/tmp/my-inbox"),
            maxFileAge: 7 * 86400,
            openers: ["md": "Marked 2", "log": "Console"]
        )

        store.save(settings)

        #expect(store.settings == settings)
        #expect(store.settings.inboxURL?.path == "/tmp/my-inbox")
        #expect(store.settings.maxFileAge == 7.0 * 86400)
        #expect(store.settings.openers == ["md": "Marked 2", "log": "Console"])
    }

    @Test("returns defaults when nothing was saved")
    func returnsDefaultsWhenEmpty() {
        let store = makeStore()

        #expect(store.settings == AppSettings.default)
    }

    @Test("overwrites previously saved settings")
    func overwrites() {
        let store = makeStore()
        store.save(AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/a"), maxFileAge: 60))
        store.save(AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/b"), maxFileAge: nil))

        #expect(store.settings.inboxURL?.path == "/tmp/b")
        #expect(store.settings.maxFileAge == nil)
    }
}