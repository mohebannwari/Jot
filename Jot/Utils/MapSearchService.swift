//
//  MapSearchService.swift
//  Jot
//

import Combine
import Foundation
import MapKit

@MainActor
final class MapSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Result: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    @Published var query: String = "" {
        didSet { updateQueryFragment() }
    }
    @Published private(set) var results: [Result] = []
    @Published private(set) var isResolvingSelection = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?
    private var pendingQueryTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func reset() {
        pendingQueryTask?.cancel()
        pendingQueryTask = nil
        activeSearch?.cancel()
        completer.cancel()
        query = ""
        results = []
        errorMessage = nil
        isResolvingSelection = false
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.map {
            Result(
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: $0.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                completion: $0
            )
        }
        errorMessage = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        errorMessage = error.localizedDescription
    }

    func resolve(_ result: Result) async -> MapBlockData? {
        isResolvingSelection = true
        errorMessage = nil

        let request = MKLocalSearch.Request(completion: result.completion)
        let search = MKLocalSearch(request: request)
        activeSearch?.cancel()
        activeSearch = search

        defer {
            activeSearch = nil
            isResolvingSelection = false
        }

        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first(where: {
                CLLocationCoordinate2DIsValid($0.placemark.coordinate)
            }) ?? response.mapItems.first else {
                errorMessage = "No place details available."
                return nil
            }

            let coordinate = mapItem.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                errorMessage = "The selected place has no valid coordinate."
                return nil
            }

            let title = MapBlockData.sanitizedTextComponent(
                mapItem.name ?? result.title
            )
            let placemarkSubtitle = mapItem.placemark.subtitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subtitle = MapBlockData.sanitizedTextComponent(
                placemarkSubtitle.isEmpty ? result.subtitle : placemarkSubtitle
            )

            return MapBlockData.initial(
                title: title.isEmpty ? result.title : title,
                subtitle: subtitle,
                coordinate: coordinate
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func updateQueryFragment() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingQueryTask?.cancel()
        pendingQueryTask = nil

        guard !trimmed.isEmpty else {
            completer.cancel()
            results = []
            errorMessage = nil
            return
        }

        errorMessage = nil
        pendingQueryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.completer.queryFragment = trimmed
            }
        }
    }
}
