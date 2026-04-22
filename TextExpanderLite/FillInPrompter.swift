import AppKit

final class FillInPrompter {
    func resolve(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") else {
            return text
        }

        var result = text
        while true {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            guard let match = regex.firstMatch(in: result, range: range),
                  match.numberOfRanges > 1,
                  let tokenRange = Range(match.range(at: 0), in: result),
                  let promptRange = Range(match.range(at: 1), in: result) else {
                break
            }

            let prompt = String(result[promptRange])
            guard let value = promptForValue(prompt) else {
                return nil
            }

            result.replaceSubrange(tokenRange, with: value)
        }

        return result
    }

    private func promptForValue(_ prompt: String) -> String? {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.informativeText = "Enter a value"
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return field.stringValue
        }
        return nil
    }
}
