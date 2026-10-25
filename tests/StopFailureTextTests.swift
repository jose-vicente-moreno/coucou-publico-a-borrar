import Foundation

@main
enum StopFailureTextTests {
    static func main() {
        // Claude Code's own message wins over everything else, on any of the three keys.
        precondition(stopFailureDetail(["error_message": "Context window exceeded"])
            == "Context window exceeded")
        precondition(stopFailureDetail(["error_details": "Tool use failed"])
            == "Tool use failed")
        precondition(stopFailureDetail(["message": "Connection reset"])
            == "Connection reset")

        // A message that is only whitespace is not a message: fall through.
        precondition(stopFailureDetail(["error_message": "   \n  ", "error_type": "rate_limit"])
            != nil)
        precondition(stopFailureDetail(["error_message": "  "]) == nil)

        // Multi-line text is flattened, because it goes on one line of a card.
        let multi = stopFailureDetail(["message": "first line\nsecond line"]) ?? ""
        precondition(!multi.contains("\n"), "detail must be one line, got: \(multi)")
        precondition(multi.contains("first line"))

        // A nested error object.
        precondition(stopFailureDetail(["error": ["message": "quota exceeded"]])
            == "quota exceeded")

        // The known kinds each get their own sentence, and never come back nil.
        for kind in ["rate_limit", "overloaded", "authentication_failed",
                     "oauth_org_not_allowed", "billing_error", "server_error",
                     "max_output_tokens", "model_not_found"] {
            let text = stopFailureDetail(["error_type": kind])
            precondition(text != nil, "\(kind) produced no text")
            precondition(!(text ?? "").isEmpty, "\(kind) produced empty text")
            precondition(text != kind, "\(kind) was echoed raw instead of explained")
        }

        // The fix taken from upstream c7c36c5. Claude Code often sends nothing but
        // error: "unknown", and the real reason is sitting in the last message. Before
        // this, the card said "unknown", which tells the user nothing at all.
        precondition(stopFailureDetail([
            "error": "unknown",
            "last_assistant_message": "API Error: 529 Overloaded",
        ]) == "API Error: 529 Overloaded")

        // "unknown" with no last message is still better left blank than echoed.
        precondition(stopFailureDetail(["error": "unknown"]) == nil)

        // A last message that is not about an error must not be dressed up as one.
        precondition(stopFailureDetail([
            "error": "unknown",
            "last_assistant_message": "Done, the tests pass.",
        ]) == nil)

        // A bare status code says nothing, so it is dropped.
        precondition(stopFailureDetail(["error_type": "500"]) == nil)
        precondition(stopFailureDetail(["error_type": "429"]) == nil)

        // A readable unknown kind is shown as it is.
        precondition(stopFailureDetail(["error_type": "transport_closed"])
            == "transport_closed")

        // Nothing at all in the payload: nothing to say.
        precondition(stopFailureDetail([:]) == nil)

        print("StopFailureTextTests: all passed")
    }
}
