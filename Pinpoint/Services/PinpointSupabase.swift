import Foundation
import Supabase

enum PinpointSupabase {
    static let bucket = "swings"
    static let table = "swings"

    static let client: SupabaseClient? = {
        guard let url = configURL, let key = configKey else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()

    static var isConfigured: Bool { client != nil }

    private static var configURL: URL? {
        guard let raw = string("SUPABASE_URL"),
              !raw.contains("YOUR_PROJECT"),
              let url = URL(string: raw) else { return nil }
        return url
    }

    private static var configKey: String? {
        guard let key = string("SUPABASE_ANON_KEY"),
              !key.isEmpty,
              key != "YOUR_ANON_KEY" else { return nil }
        return key
    }

    private static func string(_ key: String) -> String? {
        if let plist = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: plist) as? [String: String],
           let value = dict[key], !value.isEmpty {
            return value
        }
        return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
