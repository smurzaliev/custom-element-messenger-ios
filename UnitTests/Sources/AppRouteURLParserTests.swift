//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import XCTest

class AppRouteURLParserTests: XCTestCase {
    var appSettings: AppSettings!
    var appRouteURLParser: AppRouteURLParser!
    
    override func setUp() {
        AppSettings.resetAllSettings()
        appSettings = AppSettings()
        appRouteURLParser = AppRouteURLParser(appSettings: appSettings)
    }
    
    func testElementCallRoutes() {
        // UCMeet uses embedded Element Call bundle (no hosted instance), so universal link call routes
        // are not expected to match. Only custom scheme routes work.
        guard let url = URL(string: "https://call.element.io/test") else {
            XCTFail("URL invalid")
            return
        }

        // No knownHosts configured for UCMeet, so universal links to call.element.io should not match
        XCTAssertNil(appRouteURLParser.route(from: url))
    }
    
    func testCustomDomainUniversalLinkCallRoutes() {
        guard let url = URL(string: "https://somecustomdomain.element.io/test") else {
            XCTFail("URL invalid")
            return
        }
        
        XCTAssertEqual(appRouteURLParser.route(from: url), nil)
    }
    
    func testCustomSchemeLinkCallRoutes() {
        let urlString = "https://somecustomdomain.example.com/test?param=123"
        guard let url = URL(string: urlString) else {
            XCTFail("URL invalid")
            return
        }

        guard let encodedURLString = urlString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            XCTFail("Could not encode URL string")
            return
        }

        guard let customSchemeURL = URL(string: "org.ucmeet.call:/?url=\(encodedURLString)") else {
            XCTFail("URL invalid")
            return
        }

        XCTAssertEqual(appRouteURLParser.route(from: customSchemeURL), AppRoute.genericCallLink(url: url))
    }
    
    func testHttpCustomSchemeLinkCallRoutes() {
        guard let customSchemeURL = URL(string: "org.ucmeet.call:/?url=http%3A%2F%2Fcall.example.com%2Ftest") else {
            XCTFail("URL invalid")
            return
        }

        XCTAssertEqual(appRouteURLParser.route(from: customSchemeURL), nil)
    }
    
    func testMatrixUserURL() {
        let userID = "@test:matrix.org"
        guard let url = URL(string: "https://matrix.to/#/\(userID)") else {
            XCTFail("Invalid url")
            return
        }
        
        let route = appRouteURLParser.route(from: url)
        
        XCTAssertEqual(route, .userProfile(userID: userID))
    }
    
    func testMatrixRoomIdentifierURL() {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        guard let url = URL(string: "https://matrix.to/#/\(id)") else {
            XCTFail("Invalid url")
            return
        }
        
        let route = appRouteURLParser.route(from: url)
        
        XCTAssertEqual(route, .room(roomID: id, via: []))
    }
    
    func testUCMatrixUserURL() {
        let userID = "@test:matrix.org"
        guard let url = URL(string: "https://ucmatrix.org/#/\(userID)") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .userProfile(userID: userID))
    }

    func testUCMatrixRoomIdentifierURL() {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        guard let url = URL(string: "https://ucmatrix.org/#/\(id)") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .room(roomID: id, via: []))
    }

    // MARK: - Additional ucmatrix.org permalink shapes

    func testUCMatrixRoomAliasURL() {
        // Room aliases use URL-encoded `%23` for the `#` prefix.
        let alias = "#general:matrix.org"
        guard let url = URL(string: "https://ucmatrix.org/#/%23general:matrix.org") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .roomAlias(alias))
    }

    func testUCMatrixEventOnRoomURL() {
        let roomID = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let eventID = "$abcdefghijklmnopqrstuvwxyz1234567890"
        guard let url = URL(string: "https://ucmatrix.org/#/\(roomID)/\(eventID)") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .event(eventID: eventID, roomID: roomID, via: []))
    }

    func testUCMatrixEventOnRoomAliasURL() {
        // Event-on-alias canonical form keeps `#` literal (matches SDK PermalinkTests:50-53).
        let alias = "#general:matrix.org"
        let eventID = "$abcdefghijklmnopqrstuvwxyz1234567890"
        guard let url = URL(string: "https://ucmatrix.org/#/#general:matrix.org/\(eventID)") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .eventOnRoomAlias(eventID: eventID, alias: alias))
    }

    func testUCMatrixRoomURLWithViaParameters() {
        let id = "!roomidentifier:matrix.org"
        guard let url = URL(string: "https://ucmatrix.org/#/\(id)?via=server1.org&via=server2.org") else {
            XCTFail("Invalid url")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertEqual(route, .room(roomID: id, via: ["server1.org", "server2.org"]))
    }

    // MARK: - Round-trip symmetry: outgoing URL.replacingMatrixToHost() ↔ inbound parser
    // Locks in the contract that any matrix.to permalink we rewrite for sharing
    // (URL.swift:replacingMatrixToHost) parses back to the same AppRoute when an
    // incoming Universal Link delivers it. If these two paths ever drift,
    // share-link round-trips silently break.

    func testRoundTripRoomURL() {
        let roomID = "!abcdef:matrix.org"
        guard let matrixToURL = URL(string: "https://matrix.to/#/\(roomID)") else {
            XCTFail("Invalid url")
            return
        }

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        XCTAssertEqual(ucmatrixURL.host, "ucmatrix.org")
        XCTAssertEqual(appRouteURLParser.route(from: ucmatrixURL), .room(roomID: roomID, via: []))
    }

    func testRoundTripUserURL() {
        let userID = "@alice:matrix.org"
        guard let matrixToURL = URL(string: "https://matrix.to/#/\(userID)") else {
            XCTFail("Invalid url")
            return
        }

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        XCTAssertEqual(ucmatrixURL.host, "ucmatrix.org")
        XCTAssertEqual(appRouteURLParser.route(from: ucmatrixURL), .userProfile(userID: userID))
    }

    func testRoundTripRoomAliasURL() {
        let alias = "#general:matrix.org"
        guard let matrixToURL = URL(string: "https://matrix.to/#/%23general:matrix.org") else {
            XCTFail("Invalid url")
            return
        }

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        XCTAssertEqual(ucmatrixURL.host, "ucmatrix.org")
        XCTAssertEqual(appRouteURLParser.route(from: ucmatrixURL), .roomAlias(alias))
    }

    func testRoundTripEventOnRoomURL() {
        let roomID = "!abcdef:matrix.org"
        let eventID = "$xyz123"
        guard let matrixToURL = URL(string: "https://matrix.to/#/\(roomID)/\(eventID)?via=server.org") else {
            XCTFail("Invalid url")
            return
        }

        let ucmatrixURL = matrixToURL.replacingMatrixToHost()

        XCTAssertEqual(ucmatrixURL.host, "ucmatrix.org")
        XCTAssertEqual(appRouteURLParser.route(from: ucmatrixURL),
                       .event(eventID: eventID, roomID: roomID, via: ["server.org"]))
    }

    func testWebRoomIDURL() {
        // UCMeet has no web client hosts configured, so Element web URLs should not be parsed
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        guard let url = URL(string: "https://app.element.io/#/room/\(id)") else {
            XCTFail("URL invalid")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertNil(route)
    }

    func testWebUserIDURL() {
        // UCMeet has no web client hosts configured, so Element web URLs should not be parsed
        let id = "@alice:matrix.org"
        guard let url = URL(string: "https://develop.element.io/#/user/\(id)") else {
            XCTFail("URL invalid")
            return
        }

        let route = appRouteURLParser.route(from: url)

        XCTAssertNil(route)
    }
}
