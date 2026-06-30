import Foundation

/// Formats byte sizes into human-readable strings
enum SizeFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    
    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        
        let doubleBytes = Double(bytes)
        let exponent = min(Int(log(doubleBytes) / log(1024)), units.count - 1)
        let value = doubleBytes / pow(1024, Double(exponent))
        
        if exponent == 0 {
            return "\(bytes) B"
        }
        
        return String(format: "%.1f %@", value, units[exponent])
    }
    
    static func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
