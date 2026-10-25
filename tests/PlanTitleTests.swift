import Foundation

@main
enum PlanTitleTests {
    static func main() {
        // The ordinary case: a Markdown heading becomes the card's one line.
        precondition(planTitle("# Rewrite the hook router\n\nDetails follow.")
            == "Rewrite the hook router")

        // Deeper headings, and a heading with no space after the hashes.
        precondition(planTitle("### Add the agents panel") == "Add the agents panel")
        precondition(planTitle("##Add the agents panel") == "Add the agents panel")

        // No heading marks at all: the line is the title.
        precondition(planTitle("Move the binaries to OneDrive") == "Move the binaries to OneDrive")

        // Leading blank lines are skipped, which is how a plan usually arrives.
        precondition(planTitle("\n\n   \n# Real title\nbody") == "Real title")

        // A plan that is only blank lines, only hashes, empty, or missing has to stay
        // approvable, so the card falls back to a word rather than showing nothing.
        precondition(planTitle("\n\n   \n") == "Plan")
        precondition(planTitle("###") == "Plan")
        precondition(planTitle("#   ") == "Plan")
        precondition(planTitle("") == "Plan")
        precondition(planTitle(nil) == "Plan")

        // Only the first line is taken, never the body.
        let long = planTitle("# Short title\n" + String(repeating: "body text ", count: 200))
        precondition(long == "Short title", "got: \(long)")

        // Trailing content on the first line is kept as it is: trimming the end is not
        // this function's job, and cutting it would hide which plan is being approved.
        precondition(planTitle("# Fix CI, then merge") == "Fix CI, then merge")

        // Hashes inside the title survive; only the leading run is stripped.
        precondition(planTitle("# Close issue #262") == "Close issue #262")

        print("PlanTitleTests: all passed")
    }
}
