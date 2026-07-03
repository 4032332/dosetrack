// DoseTrack/Services/HealthKitManager.swift
// Writes dose confirmations to Apple Health as mindfulness sessions,
// tagged with the medication name in sample metadata.
// HealthKit doesn't have a native "medication dose" category type (as of iOS 17),
// so mindfulness sessions are the cleanest available proxy: they are time-stamped,
// support arbitrary metadata, and don't misrepresent health state.

import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()
    private init() {}

    private let store = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()

    // MARK: - Write types we request

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: [])
            isAuthorized = checkAuthorization()
        } catch {
            print("HealthKit auth error: \(error)")
        }
    }

    func checkAuthorization() -> Bool {
        guard isAvailable,
              let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return false }
        return store.authorizationStatus(for: mindful) == .sharingAuthorized
    }

    func refreshAuthorizationStatus() {
        isAuthorized = checkAuthorization()
    }

    // MARK: - Log dose

    /// Writes a dose event as a mindfulness session sample.
    /// The sample has zero duration (a point-in-time event) and carries
    /// the medication name in metadata so it's identifiable in Health.
    func logDose(medicationName: String, dosage: String, scheduledAt: Date) async {
        guard isAvailable, isAuthorized else { return }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }

        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: "dosetrack-\(medicationName)-\(scheduledAt.timeIntervalSince1970)",
            "DTMedicationName": medicationName,
            "DTDosage": dosage,
            HKMetadataKeyWasUserEntered: true
        ]

        // Zero-duration sample at the scheduled time — represents a point-in-time dose event
        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: scheduledAt,
            end: scheduledAt.addingTimeInterval(1),
            metadata: metadata
        )

        do {
            try await store.save(sample)
        } catch {
            print("HealthKit logDose error: \(error)")
        }
    }

    // MARK: - Delete dose (if user un-takes a dose)

    func deleteDose(medicationName: String, scheduledAt: Date) async {
        guard isAvailable, isAuthorized else { return }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }

        let externalUUID = "dosetrack-\(medicationName)-\(scheduledAt.timeIntervalSince1970)"
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalUUID
        )

        do {
            let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: mindfulType,
                    predicate: predicate,
                    limit: 10,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: results ?? []) }
                }
                store.execute(query)
            }
            if !samples.isEmpty {
                try await store.delete(samples)
            }
        } catch {
            print("HealthKit deleteDose error: \(error)")
        }
    }
}
