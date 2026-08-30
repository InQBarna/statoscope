@_spi(Internal) @testable import Statoscope

private func setupVerboseLevel() {
    StatoscopeLogger.logLevel = LogLevel.all
}
