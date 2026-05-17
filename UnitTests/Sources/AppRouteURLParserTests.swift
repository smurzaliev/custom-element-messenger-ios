//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct AppRouteURLParserTests {
    var appSettings: AppSettings
    var appRouteURLParser: AppRouteURLParser
    
    init() {
        AppSettings.resetAllSettings()
        appSettings = AppSettings()
        appRouteURLParser = AppRouteURLParser(appSettings: appSettings)
    }
    
    @Test
    func oAuthCallbackRoute() {
        // Given an OAuth callback for this app.
        let callbackURL = appSettings.oAuthRedirectURL.appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                                                              URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then it should be considered a valid OAuth callback.
        #expect(route == .oAuthCallback(url: callbackURL))
    }
    
    @Test
    func oAuthCallbackAppVariantRoute() {
        // Given an OAuth callback for a different app variant.
        let callbackURL = appSettings.oAuthRedirectURL
            .deletingLastPathComponent()
            .appending(component: "io.element.elementz")
            .appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                    URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route in this app.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then the route shouldn't be considered valid and should be ignored.
        #expect(route == nil)
    }
    
    @Test
    func matrixUserURL() throws {
        let userID = "@test:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(userID)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: userID))
    }
    
    @Test
    func matrixRoomIdentifierURL() throws {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(id)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .room(roomID: id, via: []))
    }
    
    @Test
    func webRoomIDURL() throws {
        // UCMeet has no Element web hosts configured (elementWebHosts = []), so app.element.io URLs should not be parsed.
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://app.element.io/#/room/\(id)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == nil)
    }

    @Test
    func webUserIDURL() throws {
        // UCMeet has no Element web hosts configured (elementWebHosts = []), so develop.element.io URLs should not be parsed.
        let id = "@alice:matrix.org"
        let url = try #require(URL(string: "https://develop.element.io/#/user/\(id)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == nil)
    }

    // MARK: - UCMeet ucmatrix.org permalink tests

    @Test
    func ucMatrixUserURL() throws {
        let userID = "@test:matrix.org"
        let url = try #require(URL(string: "https://ucmatrix.org/#/\(userID)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .userProfile(userID: userID))
    }

    @Test
    func ucMatrixRoomIdentifierURL() throws {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://ucmatrix.org/#/\(id)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .room(roomID: id, via: []))
    }

    // MARK: - Additional ucmatrix.org permalink shapes

    @Test
    func ucMatrixRoomAliasURL() throws {
        // Room aliases use URL-encoded `%23` for the `#` prefix.
        let alias = "#general:matrix.org"
        let url = try #require(URL(string: "https://ucmatrix.org/#/%23general:matrix.org"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .roomAlias(alias))
    }

    @Test
    func ucMatrixEventOnRoomURL() throws {
        let roomID = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let eventID = "$abcdefghijklmnopqrstuvwxyz1234567890"
        let url = try #require(URL(string: "https://ucmatrix.org/#/\(roomID)/\(eventID)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .event(eventID: eventID, roomID: roomID, via: []))
    }

    @Test
    func ucMatrixEventOnRoomAliasURL() throws {
        // Event-on-alias canonical form keeps `#` literal (matches SDK PermalinkTests:50-53).
        let alias = "#general:matrix.org"
        let eventID = "$abcdefghijklmnopqrstuvwxyz1234567890"
        let url = try #require(URL(string: "https://ucmatrix.org/#/#general:matrix.org/\(eventID)"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .eventOnRoomAlias(eventID: eventID, alias: alias))
    }

    @Test
    func ucMatrixRoomURLWithViaParameters() throws {
        let id = "!roomidentifier:matrix.org"
        let url = try #require(URL(string: "https://ucmatrix.org/#/\(id)?via=server1.org&via=server2.org"))

        let route = appRouteURLParser.route(from: url)

        #expect(route == .room(roomID: id, via: ["server1.org", "server2.org"]))
    }

    // MARK: - Round-trip symmetry: outgoing URL.replacingMatrixToHost() ↔ inbound parser

    // Locks in the contract that any matrix.to permalink we rewrite for sharing
    // (URL.swift:replacingMatrixToHost) parses back to the same AppRoute when an
    // incoming Universal Link delivers it. If these two paths ever drift,
    // share-link round-trips silently break.

    @Test
    func roundTripRoomURL() throws {
        let roomID = "!abcdef:matrix.org"
        let matrixToURL = try #require(URL(string: "https://matrix.to/#/\(roomID)"))

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        #expect(ucmatrixURL.host == "ucmatrix.org")
        #expect(appRouteURLParser.route(from: ucmatrixURL) == .room(roomID: roomID, via: []))
    }

    @Test
    func roundTripUserURL() throws {
        let userID = "@alice:matrix.org"
        let matrixToURL = try #require(URL(string: "https://matrix.to/#/\(userID)"))

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        #expect(ucmatrixURL.host == "ucmatrix.org")
        #expect(appRouteURLParser.route(from: ucmatrixURL) == .userProfile(userID: userID))
    }

    @Test
    func roundTripRoomAliasURL() throws {
        let alias = "#general:matrix.org"
        let matrixToURL = try #require(URL(string: "https://matrix.to/#/%23general:matrix.org"))

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        #expect(ucmatrixURL.host == "ucmatrix.org")
        #expect(appRouteURLParser.route(from: ucmatrixURL) == .roomAlias(alias))
    }

    @Test
    func roundTripEventOnRoomURL() throws {
        let roomID = "!abcdef:matrix.org"
        let eventID = "$xyz123"
        let matrixToURL = try #require(URL(string: "https://matrix.to/#/\(roomID)/\(eventID)?via=server.org"))

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        #expect(ucmatrixURL.host == "ucmatrix.org")
        #expect(appRouteURLParser.route(from: ucmatrixURL) == .event(eventID: eventID, roomID: roomID, via: ["server.org"]))
    }
}
