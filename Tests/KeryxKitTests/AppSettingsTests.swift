import Testing
import Foundation
@testable import KeryxKit

@Suite("AppSettings")
struct AppSettingsTests {

    @Test("default settings use the home inbox and a 2s scan interval")
    func defaults() {
        let settings = AppSettings.default

        #expect(settings.scanInterval == 2.0)
        #expect(settings.inboxURL == nil)
    }

    @Test("scan interval below the minimum is clamped")
    func clampsInterval() {
        #expect(AppSettings(inboxURL: nil, scanInterval: 0.05).scanInterval == 0.5)
        #expect(AppSettings(inboxURL: nil, scanInterval: -1).scanInterval == 0.5)
        #expect(AppSettings(inboxURL: nil, scanInterval: 30).scanInterval == 30)
    }

    @Test("in-memory store round-trips settings")
    func inMemoryStoreRoundTrip() {
        let store = InMemorySettingsStore()
        let url = URL(fileURLWithPath: "/tmp/inbox")
        let settings = AppSettings(inboxURL: url, scanInterval: 5)

        store.save(settings)

        #expect(store.settings == settings)
        #expect(store.settings.inboxURL == url)
    }
}

@Suite("UserDefaultsSettingsStore")
struct UserDefaultsSettingsStoreTests {

    private func makeStore() -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: "keryx-test-\(UUID().uuidString)")!)
    }

    @Test("round-trips inbox path and scan interval")
    func roundTrip() {
        let store = makeStore()
        let settings = AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/my-inbox"), scanInterval: 7)

        store.save(settings)

        #expect(store.settings == settings)
        #expect(store.settings.inboxURL?.path == "/tmp/my-inbox")
        #expect(store.settings.scanInterval == 7)
    }

    @Test("returns defaults when nothing was saved")
    func returnsDefaultsWhenEmpty() {
        let store = makeStore()

        #expect(store.settings == AppSettings.default)
    }

    @Test("overwrites previously saved settings")
    func overwrites() {
        let store = makeStore()
        store.save(AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/a"), scanInterval: 2))
        store.save(AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/b"), scanInterval: 10))

        #expect(store.settings.inboxURL?.path == "/tmp/b")
        #expect(store.settings.scanInterval == 10 || store.settings.scanInterval == 10)
        #expect(store.settings == AppSettings(inboxURL: URL(fileURLWithPath: "/tmp/b"), scanInterval: 10))
    }
}