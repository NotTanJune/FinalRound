import Foundation

struct CurrencyFormatter {
    static func getCurrencySymbol(for currencyCode: String) -> String {
        let currencySymbols: [String: String] = [
            // North America
            "USD": "$", "CAD": "CA$", "MXN": "MX$",
            
            // Europe
            "GBP": "£", "EUR": "€", "CHF": "CHF",
            "SEK": "kr", "NOK": "kr", "DKK": "kr",
            "PLN": "zł", "CZK": "Kč", "HUF": "Ft", "RON": "lei",
            
            // Asia Pacific
            "INR": "₹", "CNY": "¥", "JPY": "¥", "KRW": "₩",
            "SGD": "S$", "HKD": "HK$", "TWD": "NT$",
            "THB": "฿", "MYR": "RM", "IDR": "Rp", "PHP": "₱",
            "VND": "₫", "PKR": "₨", "BDT": "৳",
            "AUD": "A$", "NZD": "NZ$",
            
            // Middle East
            "AED": "AED", "SAR": "SR", "ILS": "₪", "TRY": "₺",
            "QAR": "QR", "KWD": "KD",
            
            // Africa
            "ZAR": "R", "NGN": "₦", "KES": "KSh", "EGP": "E£",
            
            // South America
            "BRL": "R$", "ARS": "AR$", "CLP": "CLP", "COP": "COL$", "PEN": "S/"
        ]
        
        return currencySymbols[currencyCode] ?? currencyCode
    }
    
    static func formatSalary(_ salary: String, currency: String) -> String {
        // If salary already has a currency symbol, return as is
        if salary.contains("$") || salary.contains("£") || salary.contains("€") || 
           salary.contains("₹") || salary.contains("¥") || salary.contains("₩") {
            return salary
        }
        
        // Otherwise, prepend the currency symbol
        let symbol = getCurrencySymbol(for: currency)
        return "\(symbol)\(salary)"
    }
    
    static func formatAmount(_ amount: Double, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        
        if let formatted = formatter.string(from: NSNumber(value: amount)) {
            return formatted
        }
        
        // Fallback
        let symbol = getCurrencySymbol(for: currency)
        return "\(symbol)\(Int(amount))"
    }
    
    static func extractSalaryRange(from salaryString: String) -> (min: Double?, max: Double?)? {
        // Extract numbers from salary string like "$90k-$120k" or "90-120k"
        let numbers = salaryString.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .compactMap { Double($0) }
        
        guard numbers.count >= 2 else { return nil }
        
        var min = numbers[0]
        var max = numbers[1]
        
        // Check if it's in thousands (k)
        if salaryString.lowercased().contains("k") {
            min *= 1000
            max *= 1000
        }
        
        return (min, max)
    }
}

