import Foundation

@MainActor @Observable
final class CourseCatalog {
    var courses: [CatalogCourse] = []
    var loading = false
    var message: String?
    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "pinpoint.selectedCourse") }
    }
    var selectedCourse: GolfCourse? { courses.first { $0.id == selectedID }?.definition ?? courses.first(where: { $0.definition != nil })?.definition }
    init() {
        selectedID = UserDefaults.standard.string(forKey: "pinpoint.selectedCourse").flatMap(UUID.init(uuidString:))
        if let data = UserDefaults.standard.data(forKey: "pinpoint.courseCatalog"),
           let saved = try? JSONDecoder().decode([CatalogCourse].self, from: data) { courses = saved }
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let base = PinpointSupabase.configURL, let key = PinpointSupabase.configKey else {
            message = "Course catalog is not configured."; return
        }
        do {
            var all: [CatalogCourse] = []
            var offset = 0
            while true {
                var components = URLComponents(url: base.appendingPathComponent("rest/v1/course_catalog"), resolvingAgainstBaseURL: false)!
                components.queryItems = [.init(name: "select", value: "*"), .init(name: "order", value: "name.asc,id.asc"), .init(name: "limit", value: "200"), .init(name: "offset", value: String(offset))]
                var request = URLRequest(url: components.url!, timeoutInterval: 20)
                request.setValue(key, forHTTPHeaderField: "apikey")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let page = try JSONDecoder().decode([CatalogCourse].self, from: data)
                all += page
                if page.count < 200 { break }
                offset += page.count
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            courses = all
            message = nil
            UserDefaults.standard.set(try JSONEncoder().encode(all), forKey: "pinpoint.courseCatalog")
        } catch is CancellationError { }
        catch { message = courses.isEmpty ? "Could not load courses. Check your connection and retry." : "Offline · showing saved courses." }
    }
}
