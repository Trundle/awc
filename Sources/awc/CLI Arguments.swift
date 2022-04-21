import ArgumentParser

struct AwcArguments: ParsableArguments {
    @Option(
        name: [.customLong("config"), .short],
        help: ArgumentHelp("Path to configuration file.", valueName: "path"))
    var configPath: String?

    @Flag()
    var debug: Bool = false
}
