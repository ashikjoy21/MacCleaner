import AppKit
import CleanerKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let engine = CleanupEngine()
    var results: [String: CategoryResult] = [:]
    var selectedItemIDs: Set<String> = []
    var isScanning = false
    var isCleaning = false
    var cleanProgress: CleanProgress?
    var cleanReport: CleanReport?
    var showingConfirmation = false
    var showingCleanSheet = false
    var selection: String?

    var categories: [CategoryResult] { results.values.filter(\.isVisible).sorted { $0.totalSize > $1.totalSize } }
    var selectedBytes: Int64 { categories.flatMap(\.items).filter { selectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { categories.filter { categorySelectedBytes($0) > 0 }.count }
    var selectedItems: [CleanupItem] { categories.flatMap(\.items).filter { selectedItemIDs.contains($0.id) } }
    var appsToQuit: [AppIdentity] {
        categories.compactMap { category in
            category.items.contains(where: { selectedItemIDs.contains($0.id) }) ? category.appToQuit : nil
        }
    }

    func selectedBytes(in category: CategoryResult) -> Int64 { category.items.filter { selectedItemIDs.contains($0.id) }.reduce(0) { $0 + $1.size } }
    private func categorySelectedBytes(_ category: CategoryResult) -> Int64 { selectedBytes(in: category) }

    func setCategory(_ category: CategoryResult, selected: Bool) {
        for item in category.items { if selected { selectedItemIDs.insert(item.id) } else { selectedItemIDs.remove(item.id) } }
    }

    func toggle(_ item: CleanupItem) {
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) } else { selectedItemIDs.insert(item.id) }
    }

    func scan() async {
        isScanning = true
        // Keep the user's choices for items that are still there; apply defaults only to new items.
        let previousIDs = Set(results.values.flatMap(\.items).map(\.id))
        let previousSelection = selectedItemIDs
        var fresh: [String: CategoryResult] = [:]
        selectedItemIDs = []
        for await result in engine.scan() {
            fresh[result.id] = result
            results[result.id] = result
            for item in result.items {
                let wasSeen = previousIDs.contains(item.id)
                if wasSeen ? previousSelection.contains(item.id) : item.isSelectedByDefault { selectedItemIDs.insert(item.id) }
            }
        }
        results = fresh
        isScanning = false
    }

    func clean() async {
        showingConfirmation = false
        showingCleanSheet = true
        isCleaning = true
        let items = selectedItems
        let apps = appsToQuit
        cleanReport = nil
        cleanProgress = nil
        cleanReport = await engine.clean(items, appsToQuit: apps) { [weak self] progress in
            Task { @MainActor in self?.cleanProgress = progress }
        }
        isCleaning = false
    }

    func finishClean() {
        showingCleanSheet = false
        cleanReport = nil
        selectedItemIDs.removeAll()
        Task { await scan() }
    }
}
