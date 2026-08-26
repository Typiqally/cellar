import CellarCore
import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try CellarCommandParser.parse(arguments)

    switch command {
    case .help:
        FileHandle.standardOutput.write(Data(CellarApplication.help.utf8))
        exit(0)
    case .version:
        FileHandle.standardOutput.write(Data("cellar \(CellarApplication.version)\n".utf8))
        exit(0)
    case .initZsh:
        FileHandle.standardOutput.write(Data((ShellIntegration.zshInit() + "\n").utf8))
        exit(0)
    case .completionsZsh:
        FileHandle.standardOutput.write(Data(CellarApplication.zshCompletions.utf8))
        exit(0)
    default:
        break
    }

    let paths = CellarPaths()
    let store = try CellarStore(directory: paths.stateDirectory)
    let homebrew = try HomebrewClient.discover()
    let application = CellarApplication(
        store: store,
        paths: paths,
        homebrew: homebrew,
        signalProvider: FilesystemPackageSignalProvider(prefix: homebrew.inferredPrefix)
    )
    exit(try application.run(command))
} catch {
    let message = "cellar: error: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    if error is CommandParserError {
        FileHandle.standardError.write(Data("Try 'cellar help' for usage.\n".utf8))
        exit(64)
    }
    exit(1)
}
