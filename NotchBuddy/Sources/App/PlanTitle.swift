import Foundation

/// The name the approval card gives a plan: its first non-empty line, without the Markdown
/// heading marks. A plan is hundreds of words and the card is one line, so the card shows
/// this instead. Lifted out of HookServer so it can be tested on its own, like
/// `stopFailureDetail`: it decides what the user reads before approving something.
///
/// Falls back to "Plan" rather than to an empty card, because a plan with no usable first
/// line still has to be approvable.
func planTitle(_ plan: String?) -> String {
    let firstLine = plan?.split(separator: "\n")
        .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let title = firstLine.map { String($0.drop { $0 == "#" || $0 == " " }) } ?? ""
    return title.isEmpty ? "Plan" : title
}
