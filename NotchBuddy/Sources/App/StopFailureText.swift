import Foundation

// The text Coucou shows when a Claude Code turn ends in failure, and the text the log
// carries. Lifted out of HookServer so it can be tested on its own: it is a pure function
// of the hook payload, and it is the only thing standing between an agent that died and a
// user who can tell why.

/// What stopped a Claude Code turn, from its StopFailure hook: Claude Code's own message when
/// it sends one, else a sentence for the kind of error. nil when nothing says.
func stopFailureDetail(_ payload: [String: Any]) -> String? {
    for key in ["error_message", "error_details", "message"] {
        if let text = payload[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DiffEngine.toOneLine(text)
        }
    }
    if let error = payload["error"] as? [String: Any], let text = error["message"] as? String, !text.isEmpty {
        return DiffEngine.toOneLine(text)
    }
    let kind = (payload["error_type"] as? String) ?? (payload["error"] as? String) ?? ""
    switch kind {
    case "rate_limit":            return String(localized: "Claude's rate limit is reached. Try again in a moment.")
    case "overloaded":            return String(localized: "Claude is overloaded. Try again in a moment.")
    case "authentication_failed", "oauth_org_not_allowed":
                                  return String(localized: "Claude Code is not signed in, or its key is no longer valid.")
    case "billing_error":         return String(localized: "Billing problem on the Claude account.")
    case "server_error":          return String(localized: "Claude's servers had a problem. Try again.")
    case "max_output_tokens":     return String(localized: "The answer was too long and was cut.")
    case "model_not_found":       return String(localized: "This model is not available.")
    default:
        // Claude Code often sends only `error: "unknown"`: its last message then usually
        // carries the API's own words ("API Error: 529 Overloaded…").
        if let last = payload["last_assistant_message"] as? String,
           last.range(of: "error", options: .caseInsensitive) != nil {
            return DiffEngine.toOneLine(last)
        }
        // A readable error is shown as it is; "unknown" or a bare status code says nothing.
        return kind.count > 3 && Int(kind) == nil && kind != "unknown" ? kind : nil
    }
}
