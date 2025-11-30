import Foundation

struct CurrencyFormatter {
    /// Returns the SF Symbol name for a given currency code
    static func getSFSymbolName(for currencyCode: String) -> String {
        let sfSymbols: [String: String] = [
            // Dollar-based currencies
            "USD": "dollarsign.circle.fill",
            "CAD": "dollarsign.circle.fill",
            "AUD": "dollarsign.circle.fill",
            "NZD": "dollarsign.circle.fill",
            "SGD": "dollarsign.circle.fill",
            "HKD": "dollarsign.circle.fill",
            "TWD": "dollarsign.circle.fill",
            "MXN": "pesosign.circle.fill",
            
            // European currencies
            "GBP": "sterlingsign.circle.fill",
            "EUR": "eurosign.circle.fill",
            "CHF": "francsign.circle.fill",
            "SEK": "coloncurrencysign.circle.fill",
            "NOK": "coloncurrencysign.circle.fill",
            "DKK": "coloncurrencysign.circle.fill",
            "PLN": "coloncurrencysign.circle.fill",
            "CZK": "coloncurrencysign.circle.fill",
            "HUF": "coloncurrencysign.circle.fill",
            "RON": "coloncurrencysign.circle.fill",
            
            // Asian currencies
            "INR": "indianrupeesign.circle.fill",
            "CNY": "yensign.circle.fill",
            "JPY": "yensign.circle.fill",
            "KRW": "wonsign.circle.fill",
            "THB": "bahtsign.circle.fill",
            "VND": "dongsign.circle.fill",
            "PHP": "pesosign.circle.fill",
            "MYR": "coloncurrencysign.circle.fill",
            "IDR": "coloncurrencysign.circle.fill",
            "PKR": "indianrupeesign.circle.fill",
            "BDT": "coloncurrencysign.circle.fill",
            
            // Middle East currencies
            "AED": "coloncurrencysign.circle.fill",
            "SAR": "coloncurrencysign.circle.fill",
            "ILS": "shekelsign.circle.fill",
            "TRY": "turkishlirasign.circle.fill",
            "QAR": "coloncurrencysign.circle.fill",
            "KWD": "coloncurrencysign.circle.fill",
            
            // African currencies
            "ZAR": "coloncurrencysign.circle.fill",
            "NGN": "nairasign.circle.fill",
            "KES": "coloncurrencysign.circle.fill",
            "EGP": "sterlingsign.circle.fill",
            
            // South American currencies
            "BRL": "brazilianrealsign.circle.fill",
            "ARS": "pesosign.circle.fill",
            "CLP": "pesosign.circle.fill",
            "COP": "pesosign.circle.fill",
            "PEN": "coloncurrencysign.circle.fill"
        ]
        
        return sfSymbols[currencyCode] ?? "coloncurrencysign.circle.fill"
    }
    
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

