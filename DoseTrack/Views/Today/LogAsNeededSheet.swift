// DoseTrack/Views/Today/LogAsNeededSheet.swift
// Sheet for recording one or more ad-hoc ("as needed" / PRN) doses.
//
// Deliberately has no Skip or Snooze action, unlike DoseActionSheet: an as-needed dose was never
// due, so there is nothing to skip and nothing to postpone. The only question worth asking is how
// many were taken, plus an optional note ("bad headache", "before flight") that a doctor reading
// the history later will find far more useful than the count alone.
import SwiftUI
import UIKit

struct LogAsNeededSheet: View {
    let item: AsNeededItem
    let onLog: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var doseCount: Int = 1
    @State private var note: String = ""

    /// Cap chosen to keep the stepper sane rather than to enforce a clinical limit — the app is a
    /// reminder tool and must not imply it knows a safe maximum for any given medication.
    private static let maxDoses = 20

    private var unitLabel: String {
        let unit = item.medication.wrappedUnit
        return doseCount == 1 ? unit : unit + "s"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.medication.color)
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.medication.wrappedName)
                                .font(.headline)
                            // Only show a dose summary when there is one — strength is optional, so
                            // this is blank for e.g. an unmeasured scoop of powder.
                            if !item.medication.doseSummary.isEmpty {
                                Text(item.medication.doseSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Stepper(value: $doseCount, in: 1...Self.maxDoses) {
                        HStack {
                            Text("Doses taken")
                            Spacer()
                            Text("\(doseCount) \(unitLabel)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("How many?")
                } footer: {
                    if item.dosesTakenToday > 0 {
                        Text("You've already logged \(item.dosesTakenToday) as-needed \(item.dosesTakenToday == 1 ? "dose" : "doses") today.")
                    }
                }

                Section {
                    TextField("e.g. bad headache", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Note (optional)")
                } footer: {
                    Text("Saved with this dose in your history and reports.")
                }
            }
            .navigationTitle("Log As Needed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onLog(doseCount, trimmed.isEmpty ? nil : trimmed)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
