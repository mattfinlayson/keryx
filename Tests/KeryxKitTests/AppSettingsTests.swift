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