//
//  OutboundTests.swift
//  OutboundTests
//
//  Created by Zhi Feng Xia on 4/26/26.
//

import Testing
import Foundation
@testable import Outbound

struct OutboundTests {

    @Test func appBundleRegistersFirebasePhoneAuthCallbackScheme() throws {
        let infoDictionary = try #require(Bundle.main.infoDictionary)
        let urlTypes = try #require(infoDictionary["CFBundleURLTypes"] as? [[String: Any]])
        let urlSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        #expect(urlSchemes.contains("app-1-186140050970-ios-e8305464ba7fbb30a033a3"))
    }

    @Test func firebaseConfigMatchesOutboundAppWhenPresent() throws {
        guard let configURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return
        }

        let configData = try Data(contentsOf: configURL)
        let config = try #require(
            PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any]
        )

        #expect(config["GOOGLE_APP_ID"] as? String == "1:186140050970:ios:e8305464ba7fbb30a033a3")
        #expect(config["PROJECT_ID"] as? String == "outbound-494602")
        #expect(config["BUNDLE_ID"] as? String == "xhstudio.Outbound")
    }

}
