import Foundation
import Testing
@testable import PostmanCore

@Suite struct ApiRequestEqualityTests {
    @Test func comparesBodiesByBytes() {
        var a = ApiRequest(id: "r", body: "{\"name\": \"ř\"}")
        var b = a
        #expect(a == b)

        // "ř" precomposed and as r + combining caron: equal as Swift Strings,
        // different on the wire, so different requests.
        a.body = "\u{159}"
        b.body = "r\u{30C}"
        #expect(a.body == b.body)
        #expect(a != b)

        b.body = "\u{159}"
        #expect(a == b)
    }

    @Test func stillComparesTheOtherFields() {
        let a = ApiRequest(id: "r", name: "One", url: "http://x")
        var b = a
        b.name = "Two"
        #expect(a != b)
        b = a
        b.headers = [KeyValue(key: "A", value: "1")]
        #expect(a != b)
    }

    @Test func sameBytesHandlesEmptyAndLargeText() {
        #expect(sameBytes("", ""))
        #expect(!sameBytes("", "a"))
        let big = String(repeating: "příliš žluťoučký kůň ", count: 50_000)
        #expect(sameBytes(big, big + ""))
        #expect(!sameBytes(big, big + "x"))
    }
}

@Suite struct CancelledResponseTests {
    @Test func cancellationIsRecognisedAndOtherFailuresAreNot() {
        #expect(ApiResponse.failure(message(for: CancellationError())).isCancelled)
        #expect(ApiResponse.failure(message(for: URLError(.cancelled))).isCancelled)
        #expect(!ApiResponse.failure(message(for: URLError(.timedOut))).isCancelled)
        #expect(!ApiResponse.failure("Could not connect to the server.").isCancelled)
        // A server that happens to answer with that text is still an answer.
        #expect(!ApiResponse(status: 499, error: ApiResponse.cancelledMessage).isCancelled)
    }
}
