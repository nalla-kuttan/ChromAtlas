import Foundation

enum WorldRegion: String, CaseIterable, Codable, Sendable {
    case europe = "Europe"
    case middleEast = "Middle East"
    case northAfrica = "North Africa"
    case subSaharanAfrica = "Africa"
    case centralAsia = "Central Asia"
    case southAsia = "South Asia"
    case eastAsia = "East Asia"
    case southeastAsia = "Southeast Asia"
    case oceania = "Oceania"
    case northAmerica = "North America"
    case centralAmerica = "Central America & Caribbean"
    case southAmerica = "South America"
    case arctic = "Arctic"
}

struct CountryInfo: Sendable {
    let code: String
    let name: String
    let region: WorldRegion

    var flag: String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }.joined()
    }
}

enum Countries {
    static let schengen: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IT", "LV", "LI",
        "LT", "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH",
    ]
    static let gcc: Set<String> = ["AE", "SA", "QA", "BH", "KW", "OM"]
    static let eastAsia: Set<String> = ["JP", "KR", "CN", "TW", "HK", "MO", "MN"]
    static let asean: Set<String> = ["TH", "VN", "KH", "LA", "MM", "MY", "SG", "ID", "PH", "BN", "TL"]
    static let nordic: Set<String> = ["DK", "SE", "NO", "FI", "IS", "FO", "GL"]
    static let balkans: Set<String> = ["HR", "BA", "ME", "RS", "AL", "MK", "SI", "BG", "GR", "RO"]
    static let silkRoad: Set<String> = ["UZ", "KZ", "KG", "TR", "IR", "GE", "AM", "AZ", "CN"]
    static let latinAmerica: Set<String> = ["MX", "GT", "BZ", "CR", "PA", "CU", "DO", "PR", "CO", "EC", "PE", "BO", "CL", "AR", "UY", "PY", "BR", "VE"]

    private static let table: [String: (String, WorldRegion)] = [
        "AE": ("United Arab Emirates", .middleEast), "QA": ("Qatar", .middleEast), "BH": ("Bahrain", .middleEast),
        "KW": ("Kuwait", .middleEast), "SA": ("Saudi Arabia", .middleEast), "OM": ("Oman", .middleEast),
        "JO": ("Jordan", .middleEast), "LB": ("Lebanon", .middleEast), "IL": ("Israel", .middleEast),
        "TR": ("Türkiye", .middleEast), "IR": ("Iran", .middleEast), "IQ": ("Iraq", .middleEast),
        "EG": ("Egypt", .northAfrica), "MA": ("Morocco", .northAfrica), "TN": ("Tunisia", .northAfrica), "DZ": ("Algeria", .northAfrica),
        "NG": ("Nigeria", .subSaharanAfrica), "GH": ("Ghana", .subSaharanAfrica), "SN": ("Senegal", .subSaharanAfrica),
        "ET": ("Ethiopia", .subSaharanAfrica), "KE": ("Kenya", .subSaharanAfrica), "TZ": ("Tanzania", .subSaharanAfrica),
        "RW": ("Rwanda", .subSaharanAfrica), "UG": ("Uganda", .subSaharanAfrica), "ZA": ("South Africa", .subSaharanAfrica),
        "NA": ("Namibia", .subSaharanAfrica), "ZW": ("Zimbabwe", .subSaharanAfrica), "MG": ("Madagascar", .subSaharanAfrica),
        "MU": ("Mauritius", .subSaharanAfrica), "SC": ("Seychelles", .subSaharanAfrica),
        "GB": ("United Kingdom", .europe), "IE": ("Ireland", .europe), "FR": ("France", .europe), "MC": ("Monaco", .europe),
        "BE": ("Belgium", .europe), "NL": ("Netherlands", .europe), "LU": ("Luxembourg", .europe), "DE": ("Germany", .europe),
        "CH": ("Switzerland", .europe), "AT": ("Austria", .europe), "CZ": ("Czechia", .europe), "HU": ("Hungary", .europe),
        "PL": ("Poland", .europe), "SK": ("Slovakia", .europe), "SI": ("Slovenia", .europe), "HR": ("Croatia", .europe),
        "BA": ("Bosnia & Herzegovina", .europe), "ME": ("Montenegro", .europe), "RS": ("Serbia", .europe), "AL": ("Albania", .europe),
        "MK": ("North Macedonia", .europe), "BG": ("Bulgaria", .europe), "RO": ("Romania", .europe), "MD": ("Moldova", .europe),
        "UA": ("Ukraine", .europe), "GR": ("Greece", .europe), "CY": ("Cyprus", .europe), "MT": ("Malta", .europe),
        "IT": ("Italy", .europe), "VA": ("Vatican City", .europe), "SM": ("San Marino", .europe), "ES": ("Spain", .europe),
        "PT": ("Portugal", .europe), "DK": ("Denmark", .europe), "SE": ("Sweden", .europe), "NO": ("Norway", .europe),
        "FI": ("Finland", .europe), "EE": ("Estonia", .europe), "LV": ("Latvia", .europe), "LT": ("Lithuania", .europe),
        "IS": ("Iceland", .europe), "RU": ("Russia", .europe), "FO": ("Faroe Islands", .europe), "LI": ("Liechtenstein", .europe),
        "GE": ("Georgia", .centralAsia), "AM": ("Armenia", .centralAsia), "AZ": ("Azerbaijan", .centralAsia),
        "KZ": ("Kazakhstan", .centralAsia), "UZ": ("Uzbekistan", .centralAsia), "KG": ("Kyrgyzstan", .centralAsia),
        "AF": ("Afghanistan", .centralAsia),
        "MN": ("Mongolia", .eastAsia), "JP": ("Japan", .eastAsia), "KR": ("South Korea", .eastAsia), "CN": ("China", .eastAsia),
        "HK": ("Hong Kong", .eastAsia), "MO": ("Macau", .eastAsia), "TW": ("Taiwan", .eastAsia),
        "TH": ("Thailand", .southeastAsia), "VN": ("Vietnam", .southeastAsia), "KH": ("Cambodia", .southeastAsia),
        "LA": ("Laos", .southeastAsia), "MM": ("Myanmar", .southeastAsia), "MY": ("Malaysia", .southeastAsia),
        "SG": ("Singapore", .southeastAsia), "ID": ("Indonesia", .southeastAsia), "PH": ("Philippines", .southeastAsia),
        "BN": ("Brunei", .southeastAsia), "TL": ("Timor-Leste", .southeastAsia),
        "IN": ("India", .southAsia), "NP": ("Nepal", .southAsia), "BT": ("Bhutan", .southAsia), "LK": ("Sri Lanka", .southAsia),
        "MV": ("Maldives", .southAsia), "BD": ("Bangladesh", .southAsia), "PK": ("Pakistan", .southAsia),
        "AU": ("Australia", .oceania), "NZ": ("New Zealand", .oceania), "FJ": ("Fiji", .oceania), "PF": ("French Polynesia", .oceania),
        "US": ("United States", .northAmerica), "CA": ("Canada", .northAmerica), "GL": ("Greenland", .arctic),
        "MX": ("Mexico", .centralAmerica), "GT": ("Guatemala", .centralAmerica), "BZ": ("Belize", .centralAmerica),
        "CR": ("Costa Rica", .centralAmerica), "PA": ("Panama", .centralAmerica), "CU": ("Cuba", .centralAmerica),
        "PR": ("Puerto Rico", .centralAmerica), "DO": ("Dominican Republic", .centralAmerica), "JM": ("Jamaica", .centralAmerica),
        "BS": ("Bahamas", .centralAmerica), "BB": ("Barbados", .centralAmerica),
        "CO": ("Colombia", .southAmerica), "EC": ("Ecuador", .southAmerica), "PE": ("Peru", .southAmerica), "BO": ("Bolivia", .southAmerica),
        "CL": ("Chile", .southAmerica), "AR": ("Argentina", .southAmerica), "UY": ("Uruguay", .southAmerica),
        "PY": ("Paraguay", .southAmerica), "BR": ("Brazil", .southAmerica), "VE": ("Venezuela", .southAmerica),
    ]

    static func info(_ code: String) -> CountryInfo {
        if let (name, region) = table[code.uppercased()] {
            return CountryInfo(code: code, name: name, region: region)
        }
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
        return CountryInfo(code: code, name: name, region: .europe)
    }
}
