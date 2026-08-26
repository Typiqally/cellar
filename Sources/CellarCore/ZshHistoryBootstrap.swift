import Foundation

public enum ZshHistoryBootstrap {
    public static func latestEvidence(
        in history: String,
        resolver: (String) -> PackageOwnership?
    ) -> [PackageOwnership: Date] {
        var result: [PackageOwnership: Date] = [:]
        for line in history.split(whereSeparator: \.isNewline) {
            guard let parsed = parseHistoryLine(String(line)) else { continue }
            for command in commandNames(in: parsed.command) {
                guard let ownership = resolver(command) else { continue }
                if result[ownership, default: .distantPast] < parsed.date {
                    result[ownership] = parsed.date
                }
            }
        }
        return result
    }

    public static func commandNames(in commandLine: String) -> [String] {
        let segments = lex(commandLine)
        var result: [String] = []
        var expectingCommand = true
        var skippingWrapperArguments = false
        let wrappers: Set<String> = ["builtin", "command", "env", "exec", "nice", "nohup", "sudo", "time"]
        let separators: Set<String> = ["|", "||", "&&", ";", "&"]

        for token in segments {
            if separators.contains(token) {
                expectingCommand = true
                skippingWrapperArguments = false
                continue
            }
            guard expectingCommand else { continue }
            if token.contains("=") && !token.hasPrefix("=") {
                continue
            }
            if wrappers.contains(token) {
                skippingWrapperArguments = true
                continue
            }
            if skippingWrapperArguments, token.hasPrefix("-") {
                continue
            }
            result.append(token)
            expectingCommand = false
            skippingWrapperArguments = false
        }
        return result
    }

    private static func parseHistoryLine(_ line: String) -> (date: Date, command: String)? {
        guard line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") else { return nil }
        let metadata = line[line.index(line.startIndex, offsetBy: 2)..<semicolon]
        guard let timestampText = metadata.split(separator: ":").first,
              let timestamp = TimeInterval(timestampText) else { return nil }
        let command = String(line[line.index(after: semicolon)...])
        return (Date(timeIntervalSince1970: timestamp), command)
    }

    private static func lex(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        let characters = Array(input)
        var index = 0

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        while index < characters.count {
            let character = characters[index]
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                flush()
            } else if "|&;".contains(character) {
                flush()
                var separator = String(character)
                if index + 1 < characters.count, characters[index + 1] == character, character != ";" {
                    separator.append(character)
                    index += 1
                }
                tokens.append(separator)
            } else {
                current.append(character)
            }
            index += 1
        }
        flush()
        return tokens
    }
}
