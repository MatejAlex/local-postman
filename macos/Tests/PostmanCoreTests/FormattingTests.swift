import Testing
@testable import PostmanCore

@Suite struct PrettyJSONTests {
    @Test func indentsLikeJSONStringifyAndKeepsKeyOrder() {
        let input = #"{"z":1,"a":[1,{"b":null}],"e":{},"f":[],"s":"x, {y}: \"q\""}"#
        let expected = """
        {
          "z": 1,
          "a": [
            1,
            {
              "b": null
            }
          ],
          "e": {},
          "f": [],
          "s": "x, {y}: \\"q\\""
        }
        """
        #expect(prettyJSON(input) == expected)
    }

    @Test func leavesInvalidJSONAlone() {
        #expect(prettyJSON("{nope") == "{nope")
        #expect(prettyJSON("plain text") == "plain text")
    }

    @Test func decodesUnicodeEscapesLikeJSONParse() {
        let input = #"{"cz":"P\u0159\u00edli\u0161","emoji":"\ud83d\ude00","keep":"\u0022 \u005c \u0001"}"#
        let expected = #"""
        {
          "cz": "Příliš",
          "emoji": "😀",
          "keep": "\u0022 \u005c \u0001"
        }
        """#
        #expect(prettyJSON(input) == expected)
    }

    @Test func reindentsAlreadyPrettyJSON() {
        #expect(prettyJSON("{\n    \"a\" :   [ ]\n}") == "{\n  \"a\": []\n}")
    }
}

@Suite struct PrettyMarkupTests {
    @Test func indentsNestedHTML() {
        let html = "<html><body><div><p>One<p>Two</div><br><pre>  keep\n    this</pre></body></html>"
        let expected = """
        <html>
          <body>
            <div>
              <p>
                One
              <p>
                Two
            </div>
            <br>
            <pre>
              keep
                this
            </pre>
          </body>
        </html>
        """
        #expect(prettyMarkup(html) == expected)
    }

    @Test func keepsCommentsAndUnclosedTags() {
        #expect(prettyMarkup("<a><!-- c --><b") == "<a>\n  <!-- c -->\n  <b")
    }
}

@Suite struct SniffingTests {
    @Test func prettyBodyPicksTheFormatter() {
        #expect(prettyBody(#"{"a":1}"#, contentType: "text/plain") == "{\n  \"a\": 1\n}")
        #expect(prettyBody("<?xml version=\"1.0\"?><a><b/></a>", contentType: "") == "<?xml version=\"1.0\"?>\n<a>\n  <b/>\n</a>")
        #expect(prettyBody("hello", contentType: "text/plain") == "hello")
        #expect(looksHTML(contentType: "", body: "  <!DOCTYPE html><html>"))
    }

    @Test func formatsTimeAndSize() {
        #expect(formatTime(123.4) == "123 ms")
        #expect(formatTime(1530) == "1.53 s")
        #expect(formatSize(512) == "512 B")
        #expect(formatSize(2048) == "2.0 KB")
    }
}
