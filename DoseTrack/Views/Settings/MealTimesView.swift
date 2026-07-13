// DoseTrack/Views/Settings/MealTimesView.swift
import SwiftUI
import CoreData

/// Settings → Preferences → Routine Preferences. The app-wide list of named routine times a
/// medication's schedule can be linked to. Each routine opens its own editor where you can change
/// its time AND batch-link/unlink medications to it. Global, not per-medication.
///
/// A fresh user starts with two anchors — Wake Up and Bedtime — whose times feed the
/// notification-copy morning/bedtime gating and so can be edited but never deleted. Everything
/// else is user-defined: add named routines with "+", rename/retime any, swipe to delete non-anchors.
struct MealTimesView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var store: RoutineStore = RoutineStore.load()
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
                            Text("\(linkedCount(routine)) med\(linkedCount(routine) == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(formattedTime(hour: routine.hour, minute: routine.minute))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                Text("Link a medication to a routine and Today shows the routine's name (e.g. \"Bedtime\") instead of a clock time — move the routine and every linked dose moves with it. Wake Up and Bedtime are always here; add your own with +.")
            }
        }
        .navigationTitle("Routine Preferences")
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
        .sheet(item: $editingRoutine, onDismiss: { store = RoutineStore.load() }) { routine in
            RoutineEditorView(routine: routine, isNew: false, onSave: { updated in update(updated) })
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showingAdd) {
            RoutineEditorView(
                routine: Routine(name: "", hour: 12, minute: 0),
                isNew: true,
                onSave: { added in store.routines.append(added); persist() }
            )
            .environment(\.managedObjectContext, context)
        }
        .toast($toast)
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        let date = Calendar.current.date(from: c) ?? Date()
        return TimeFormatPreference.string(for: date, preference: UserDefaults.standard.string(forKey: "timeFormat") ?? "system")
    }

    /// How many medications are currently linked to this routine (any schedule carrying its name).
    private func linkedCount(_ routine: Routine) -> Int {
        let req = Schedule.fetchRequest()
        req.predicate = NSPredicate(format: "routineLabel == %@", routine.name)
        let scheds = (try? context.fetch(req)) ?? []
        return Set(scheds.compactMap { $0.medication?.objectID }).count
    }

    private func update(_ routine: Routine) {
        guard let idx = store.routines.firstIndex(where: { $0.id == routine.id }) else { return }
        let old = store.routines[idx]
        store.routines[idx] = routine
        // If the routine moved (or was renamed), carry every linked schedule with it — this is the
        // whole promise of a routine: "move the routine and the linked doses follow".
        if old.hour != routine.hour || old.minute != routine.minute || old.name != routine.name {
            RoutineLinker.propagateChange(fromName: old.name, to: routine, context: context)
        }
        persist()
    }

    private func delete(_ routine: Routine) {
        // Unlink any schedules first (don't leave doses pointing at a routine that no longer exists).
        RoutineLinker.unlinkAll(routineName: routine.name, context: context)
        store.routines.removeAll { $0.id == routine.id && !$0.isAnchor }
        persist()
    }

    private func persist() {
        store.save()
        Task {
            await SupabaseSyncManager.shared.pushSettings()
            toast = ToastMessage(text: "Saved", systemImage: "checkmark.circle.fill")
        }
    }
}

// MARK: - Routine editor (time + linked medications)

/// Edit a single routine: its name, its time, and which medications are taken at it. Linking a
/// medication moves its schedule onto this routine (name + time); unlinking returns it to a plain
/// clock time. Anchors (Wake Up / Bedtime) can't be renamed.
private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State var routine: Routine
    let isNew: Bool
    let onSave: (Routine) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Medication.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES")
    ) private var medications: FetchedResults<Medication>

    @State private var didLinkChange = false
    /// The linked medications, held as explicit view state so the checkmarks re-render reliably on
    /// tap — reading it live from each med's schedules (a to-many relationship) did NOT reliably
    /// refresh the row when a schedule changed, which is why boxes wouldn't toggle/uncheck.
    @State private var linkedIDs: Set<NSManagedObjectID> = []

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
                        HStack { Text("Name"); Spacer(); Text(routine.name).foregroundStyle(.secondary) }
                    } else {
                        TextField("Name (e.g. After Lunch)", text: $routine.name)
                    }
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                } footer: {
                    if routine.isAnchor {
                        Text("Wake Up and Bedtime can't be renamed or removed — reminder wording adapts to their times.")
                    }
                }

                // Batch-link medications to this routine. Hidden for a brand-new routine until it's
                // been saved (it needs a stable name to link against).
                if !isNew {
                    Section {
                        if medications.isEmpty {
                            Text("No medications yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(medications) { med in
                                let isOn = linkedIDs.contains(med.objectID)
                                Button {
                                    toggleLink(med, currentlyLinked: isOn)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(med.wrappedName).foregroundStyle(.primary)
                                            Text("\(med.wrappedDosage) · \(med.wrappedUnit)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Medications taken at \(routine.name)")
                    } footer: {
                        Text("Tap a medication to move its schedule to this routine. It'll show \"\(routine.name)\" on Today and follow this routine's time.")
                    }
                }
            }
            .navigationTitle(isNew ? "New Routine" : routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                linkedIDs = Set(medications
                    .filter { m in m.schedulesArray.contains { ($0.routineLabel ?? "") == routine.name } }
                    .map(\.objectID))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish(save: false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finish(save: true) }
                        .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func toggleLink(_ med: Medication, currentlyLinked: Bool) {
        if currentlyLinked {
            RoutineLinker.unlink(med: med, routineName: routine.name, context: context)
            linkedIDs.remove(med.objectID)
        } else {
            RoutineLinker.link(med: med, to: routine, context: context)
            linkedIDs.insert(med.objectID)
        }
        didLinkChange = true
    }

    private func finish(save: Bool) {
        routine.name = routine.name.trimmingCharacters(in: .whitespaces)
        if save { onSave(routine) }
        // A link/unlink already wrote to the store; rebuild notifications once on the way out so
        // the reminders reflect the new routine membership (cheaper than per-toggle).
        if didLinkChange { NotificationScheduler.shared.refreshAll(context: context) }
        dismiss()
    }
}

// MARK: - Linking helper

/// Links/unlinks medications to routines and keeps their schedules + Supabase in sync. Kept
/// separate so the write logic is in one place (used by both the routine list and its editor).
enum RoutineLinker {

    /// Move a medication onto a routine. Links the SINGLE schedule closest to the routine's time
    /// (so a twice-daily med isn't collapsed onto one time — only its nearest dose joins the
    /// routine), or creates one daily schedule if the medication had none.
    static func link(med: Medication, to routine: Routine, context: NSManagedObjectContext) {
        let target: Schedule
        if med.schedulesArray.isEmpty {
            target = Schedule.create(in: context, medication: med,
                                     hour: Int16(routine.hour), minute: Int16(routine.minute),
                                     frequency: "daily")
        } else {
            let rMin = routine.hour * 60 + routine.minute
            target = med.schedulesArray.min {
                abs((Int($0.hour) * 60 + Int($0.minute)) - rMin) < abs((Int($1.hour) * 60 + Int($1.minute)) - rMin)
            }!
        }
        target.routineLabel = routine.name
        target.hour = Int16(routine.hour)
        target.minute = Int16(routine.minute)
        target.updatedAt = Date()
        med.updatedAt = Date()
        try? context.save()
        Task { await SupabaseSyncManager.shared.pushMedication(med) }
    }

    /// Detach a medication from a routine — its schedules keep their time but drop the routine name.
    static func unlink(med: Medication, routineName: String, context: NSManagedObjectContext) {
        for s in med.schedulesArray where (s.routineLabel ?? "") == routineName {
            s.routineLabel = nil
            s.updatedAt = Date()
        }
        med.updatedAt = Date()
        try? context.save()
        Task { await SupabaseSyncManager.shared.pushMedication(med) }
    }

    /// A routine changed time or name — move every linked schedule to match, and re-push the meds.
    static func propagateChange(fromName oldName: String, to routine: Routine, context: NSManagedObjectContext) {
        let req = Schedule.fetchRequest()
        req.predicate = NSPredicate(format: "routineLabel == %@", oldName)
        guard let scheds = try? context.fetch(req), !scheds.isEmpty else { return }
        for s in scheds {
            s.routineLabel = routine.name
            s.hour = Int16(routine.hour)
            s.minute = Int16(routine.minute)
            s.updatedAt = Date()
        }
        let meds = Set(scheds.compactMap { $0.medication })
        for m in meds { m.updatedAt = Date() }
        try? context.save()
        Task { for m in meds { await SupabaseSyncManager.shared.pushMedication(m) } }
        NotificationScheduler.shared.refreshAll(context: context)
    }

    /// Detach every medication from a routine that's being deleted.
    static func unlinkAll(routineName: String, context: NSManagedObjectContext) {
        let req = Schedule.fetchRequest()
        req.predicate = NSPredicate(format: "routineLabel == %@", routineName)
        guard let scheds = try? context.fetch(req), !scheds.isEmpty else { return }
        for s in scheds { s.routineLabel = nil; s.updatedAt = Date() }
        let meds = Set(scheds.compactMap { $0.medication })
        for m in meds { m.updatedAt = Date() }
        try? context.save()
        Task { for m in meds { await SupabaseSyncManager.shared.pushMedication(m) } }
        NotificationScheduler.shared.refreshAll(context: context)
    }
}

#Preview {
    NavigationStack { MealTimesView() }
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
