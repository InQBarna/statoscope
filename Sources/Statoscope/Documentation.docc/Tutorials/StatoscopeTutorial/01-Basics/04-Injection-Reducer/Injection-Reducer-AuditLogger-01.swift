struct AuditLogger: Injectable {
    var log: (String) -> Void
    static var defaultValue = AuditLogger(log: { _ in })
}
