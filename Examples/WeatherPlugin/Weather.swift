import FluidKit
import Foundation

/// The temperature where you are, from Open-Meteo (no API key), with today's
/// hourly curve in the panel.
@main
final class Weather: FluidPlugin {
    static let manifest = Manifest(
        id: "dev.fluid.example.weather",
        name: "Weather",
        summary: "Current temperature and today's curve, from Open-Meteo.",
        surfaces: [.menuBar, .panel, .widget],
        triggers: [.launch, .minutes(15), .wake],
        capabilities: [.network("api.open-meteo.com", "geocoding-api.open-meteo.com")]
    )

    struct Place: Codable, Equatable { var name: String; var latitude: Double; var longitude: Double }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Hourly: Decodable { let temperature_2m: [Double] }
        let current: Current
        let hourly: Hourly
    }

    private struct Geocoding: Decodable {
        struct Result: Decodable { let name: String; let country: String?; let latitude: Double; let longitude: Double }
        let results: [Result]?
    }

    @Stored("place") var place = Place(name: "Berlin", latitude: 52.52, longitude: 13.41)
    @Stored("unit") var unit = "celsius"
    var temperature: Double?
    var code = 0
    var hourly: [Double] = []
    var problem: String?

    func refresh() async throws {
        let url = "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,weather_code&hourly=temperature_2m&forecast_days=1&temperature_unit=\(unit)"
        do {
            let forecast: Forecast = try await Fluid.getJSON(url)
            temperature = forecast.current.temperature_2m
            code = forecast.current.weather_code
            hourly = forecast.hourly.temperature_2m
            problem = nil
        } catch {
            problem = "\(error)"
        }
    }

    var menuBar: ViewContent {
        Label(temperature.map { "\(Int($0.rounded()))°" } ?? "–", symbol: symbol)
    }

    var panel: ViewContent {
        Text(place.name).style(.headline)
        if let temperature {
            Text("\(Int(temperature.rounded()))° \(description)").style(.title)
        }
        if hourly.count > 1 { Chart("Today", values: hourly) }
        if let problem { Text(problem).role(.warning).style(.caption) }
        TextField("Change city", key: "city") { city in try await self.search(city) }
        Picker("Unit", options: ["celsius", "fahrenheit"], selection: unit) { newUnit in
            self.unit = newUnit
            try await self.refresh()
        }
    }

    var widget: ViewContent {
        Text(place.name).style(.caption).role(.secondary)
        Label(temperature.map { "\(Int($0.rounded()))°" } ?? "–", symbol: symbol)
        if hourly.count > 1 { Chart(values: hourly) }
    }

    var tools: [AgentTool] {
        AgentTool("current", description: "Current temperature and conditions") { _ in
            guard let temperature = self.temperature else { return "No reading yet." }
            return "\(self.place.name): \(temperature)° \(self.unit), \(self.description)"
        }
    }

    private func search(_ city: String) async throws {
        let query = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let result: Geocoding = try await Fluid.getJSON("https://geocoding-api.open-meteo.com/v1/search?count=1&name=\(query)")
        guard let first = result.results?.first else {
            problem = "No place called \(city)"
            return
        }
        place = Place(name: [first.name, first.country].compactMap { $0 }.joined(separator: ", "), latitude: first.latitude, longitude: first.longitude)
        try await refresh()
    }

    /// WMO weather codes, grouped.
    private var description: String {
        switch code {
        case 0: return "clear"
        case 1...3: return "partly cloudy"
        case 45, 48: return "fog"
        case 51...67, 80...82: return "rain"
        case 71...77, 85, 86: return "snow"
        case 95...99: return "thunderstorm"
        default: return "cloudy"
        }
    }

    private var symbol: String {
        switch code {
        case 0: return "sun.max"
        case 1...3: return "cloud.sun"
        case 45, 48: return "cloud.fog"
        case 51...67, 80...82: return "cloud.rain"
        case 71...77, 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt"
        default: return "cloud"
        }
    }
}
