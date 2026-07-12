// DoseTrack/Views/Settings/MealTimesView.swift
import SwiftUI

/// Settings → Preferences → Daily Routine Times. The app-wide list of named routine times a
/// medication's schedule can be linked to (see `GuidedScheduleView`). Global, not per-medication.
///
/// A fresh user starts with just two anchors — Wake Up and Bedtime — whose times feed the
/// notification-copy morning/bedtime gating and so can be edited but never deleted. Everything
/// else is user-defined: add named routines with "+", rename or retime any of them, swipe to
/// delete the non-anchors.
struct MealTimesView: View {
    @State private var store: RoutineStore = RoutineStore.load()
    @State private var isSaving = false
    @State private var toast: ToastMessage? = nil
    @State private var editingRoutine: Routine? = nil
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                ForEach(store.sorted) { routine in
                    Button {
                        editingRoutine = routine
                    } label: {
                        HStack {
                            Text(routine.name)
                                .foregroundStyle(.primary)
                            if routine.isAnchor {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(formattedTime(hour: routine.hour, minute: routine.minute))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Anchors (Wake Up / Bedtime) can't be deleted — notification gating
                        // depends on them always existing.
                        if !routine.isAnchor {
                            Button(role: .destructive) {
                                delete(routine)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                Text("Link a medication's schedule to a routine and Today shows the routine's name (e.g. \"Bedtime\") instead of a clock time — so if you move the routine, every linked dose moves with it. Wake Up and Bedtime are always here; add your own with +.")
            }
        }
        .navigationTitle("Daily Routine Times")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus").accessibilityLabel("Add routine")
                }
            }
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorView(routine: routine, isNew: false) { updated in
                update(updated)
            }
        }
        .sheet(isPresented: $showingAdd) {
            RoutineEditorView(
                routine: Routine(name: "", hour: 12, minute: 0),
                isNew: true
            ) { added in
                store.routines.append(added)
                persist()
            }
        }
        .toast($toast)
        .onDisappear {
            // Mirror the previous screen's belt-and-braces save-on-exit: each edit already
            // persists + pushes, but a push still in flight when the screen closes gets a final
            // guaranteed write here.
            Task { await pushRemote(showToast: false) }
        }
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var c = DateComponents()
        c.hour = hour; c.minute = minute
        let date = Calendar.current.date(from: c) ?? Date()
        return TimeFormatPreference.string(for: date, preference: UserDefaults.standard.string(forKey: "timeFormat") ?? "system")
    }

    private func update(_ routine: Routine) {
        guard let idx = store.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        store.routines[idx] = routine
        persist()
    }

    private func delete(_ routine: Routine) {
        store.routines.removeAll { $0.id == routine.id && !$0.isAnchor }
        persist()
    }

    private func persist() {
        store.save()
        Task { await pushRemote(showToast: true) }
    }

    private func pushRemote(showToast: Bool) async {
        isSaving = true
        defer { isSaving = false }
        await SupabaseSyncManager.shared.pushSettings()
        if showToast {
            toast = ToastMessage(text: "Saved", systemImage: "checkmark.circle.fill")
        }
    }
}

/// Add or edit a single routine: name + time. The name field is locked for anchors (Wake Up /
/// Bedtime) since renaming them would break the notification gating that keys off those names.
private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var routine: Routine
    let isNew: Bool
    let onSave: (Routine) -> Void

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = routine.hour; c.minute = routine.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                routine.hour = c.hour ?? 0
                routine.minute = c.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if routine.isAnchor {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(routine.name).foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Name (e.g. After Lunch)", text: $routine.name)
                    }
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                } footer: {
                    if routine.isAnchor {
                        Text("Wake Up and Bedtime can't be renamed or removed — reminder wording adapts to their times.")
                    }
                }
            }
            .navigationTitle(isNew ? "New Routine" : routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routine.name = routine.name.trimmingCharacters(in: .whitespaces)
                        onSave(routine)
                        dismiss()
                    }
                    .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { MealTimesView() }
}
