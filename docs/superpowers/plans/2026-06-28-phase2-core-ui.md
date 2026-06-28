# DoseTrack Phase 2: Core UI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full navigational shell and core screens — TabView, Today, Medications list, Medication Detail, and Add/Edit form — with ViewModels, unit tests, and a working simulator build.

**Architecture:** MVVM throughout. Each screen has a dedicated ViewModel (`@MainActor ObservableObject`) that owns CoreData fetches and business logic. Views are thin — they bind to ViewModels and emit user intents. The `PersistenceController.shared.viewContext` is injected via `.environment(\.managedObjectContext)` at the root and consumed in ViewModels via `@Environment`. Free-tier enforcement (max 5 medications) lives in `MedicationsViewModel`.

**Tech Stack:** SwiftUI (iOS 17+), CoreData (`@FetchRequest`, `NSFetchedResultsController`), `@StateObject` / `@ObservedObject`, `@Environment(\.managedObjectContext)`, XCTest for ViewModel logic

---

## File Map

| File | Role |
|---|---|
| `DoseTrack/App/ContentView.swift` | Replace placeholder with real TabView shell |
| `DoseTrack/ViewModels/TodayViewModel.swift` | Today's doses, adherence score, snooze/take/skip actions |
| `DoseTrack/ViewModels/MedicationsViewModel.swift` | CRUD ops, free-tier gate, sort order |
| `DoseTrack/ViewModels/AddEditMedicationViewModel.swift` | Form state, validation, save/update |
| `DoseTrack/Views/Today/TodayView.swift` | Header + grouped dose list |
| `DoseTrack/Views/Today/DoseRowView.swift` | Single dose row with status chip |
| `DoseTrack/Views/Today/DoseActionSheet.swift` | Take/Skip/Snooze bottom sheet |
| `DoseTrack/Views/Medications/MedicationsView.swift` | List with FAB, swipe-to-delete, refill badge |
| `DoseTrack/Views/Medications/MedicationDetailView.swift` | Read-only detail, edit button, schedules list |
| `DoseTrack/Views/Medications/AddEditMedicationView.swift` | Full add/edit form |
| `DoseTrack/Views/Medications/ScheduleBuilderView.swift` | Time + days-of-week picker |
| `DoseTrack/Views/Paywall/PaywallView.swift` | Stub paywall sheet (full StoreKit UI in Phase 7) |
| `DoseTrackTests/TodayViewModelTests.swift` | Unit tests for adherence and dose actions |
| `DoseTrackTests/MedicationsViewModelTests.swift` | Unit tests for CRUD and free-tier gate |
| `DoseTrackTests/AddEditMedicationViewModelTests.swift` | Unit tests for form validation |

---

## Chunk 1: TabView Shell + ViewModels

### Task 1: TodayViewModel

**Files:**
- Create: `DoseTrack/ViewModels/TodayViewModel.swift`

- [ ] **Step 1: Write TodayViewModel.swift**

```swift
// DoseTrack/ViewModels/TodayViewModel.swift
import CoreData
import Combine

/// Represents a single dose slot on the Today screen.
struct DoseEntry: Identifiable {
    let id: UUID
    let medication: Medication
    let schedule: Schedule
    let scheduledAt: Date
    var status: DoseStatus
    var existingLog: DoseLog?
}

@MainActor
final class TodayViewModel: ObservableObject {

    @Published var doseEntries: [DoseEntry] = []
    @Published var takenCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var selectedEntry: DoseEntry?

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
    }

    // MARK: - Public

    func refresh() {
        let entries = buildTodayEntries()
        doseEntries = entries.sorted { $0.scheduledAt < $1.scheduledAt }
        totalCount = entries.count
        takenCount = entries.filter { $0.status == .taken }.count
    }

    func markTaken(_ entry: DoseEntry) {
        log(entry: entry, status: .taken)
    }

    func markSkipped(_ entry: DoseEntry) {
        log(entry: entry, status: .skipped)
    }

    func snooze(_ entry: DoseEntry, minutes: Int = 30) {
        // Snooze is handled by NotificationScheduler (Phase 3).
        // On the Today screen we optimistically mark as pending (no log written).
        // Nothing to persist here — the user will see the snoozed notification later.
    }

    // MARK: - Computed

    var adherencePercent: Int {
        guard totalCount > 0 else { return 100 }
        return Int(Double(takenCount) / Double(totalCount) * 100)
    }

    var allDonToday: Bool {
        totalCount > 0 && takenCount == totalCount
    }

    // MARK: - Private

    private func log(entry: DoseEntry, status: DoseStatus) {
        if let existing = entry.existingLog {
            existing.status = status.rawValue
            existing.loggedAt = Date()
        } else {
            DoseLog.create(
                in: context,
                medication: entry.medication,
                scheduledAt: entry.scheduledAt,
                status: status
            )
        }
        try? context.save()
        refresh()
    }

    private func buildTodayEntries() -> [DoseEntry] {
        let medRequest = Medication.fetchRequest()
        medRequest.predicate = NSPredicate(format: "isActive == YES")
        guard let medications = try? context.fetch(medRequest) else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let weekday = calendar.component(.weekday, from: Date())

        let logRequest = DoseLog.fetchRequest()
        logRequest.predicate = NSPredicate(
            format: "scheduledAt >= %@ AND scheduledAt < %@",
            today as NSDate, tomorrow as NSDate
        )
        let todayLogs = (try? context.fetch(logRequest)) ?? []

        var entries: [DoseEntry] = []

        for med in medications {
            for schedule in med.schedulesArray where schedule.isEnabled {
                guard isDueToday(schedule: schedule, weekday: weekday) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = Int(schedule.hour)
                components.minute = Int(schedule.minute)
                guard let scheduledAt = calendar.date(from: components) else { continue }

                let existing = todayLogs.first {
                    $0.medication == med &&
                    calendar.isDate($0.scheduledAt ?? .distantPast, equalTo: scheduledAt, toGranularity: .minute)
                }

                let status: DoseStatus = existing?.doseStatus ?? (scheduledAt < Date() ? .missed : .taken)
                // Mark as "pending" visual state using .taken as placeholder for future doses
                let displayStatus: DoseStatus = existing?.doseStatus ?? (scheduledAt <= Date() ? .missed : .taken)

                entries.append(DoseEntry(
                    id: schedule.id ?? UUID(),
                    medication: med,
                    schedule: schedule,
                    scheduledAt: scheduledAt,
                    status: existing != nil ? existing!.doseStatus : (scheduledAt <= Date() ? .missed : .taken),
                    existingLog: existing
                ))
            }
        }

        return entries
    }

    private func isDueToday(schedule: Schedule, weekday: Int) -> Bool {
        switch schedule.wrappedFrequency {
        case "daily":
            return true
        case "weekly":
            let days = schedule.daysOfWeekArray
            return days.isEmpty || days.contains(weekday)
        case "custom":
            let days = schedule.daysOfWeekArray
            return days.isEmpty || days.contains(weekday)
        case "as_needed":
            return false
        default:
            return true
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/ViewModels/TodayViewModel.swift
git commit -m "feat: add TodayViewModel with dose entry building and adherence score"
```

---

### Task 2: MedicationsViewModel

**Files:**
- Create: `DoseTrack/ViewModels/MedicationsViewModel.swift`

- [ ] **Step 1: Write MedicationsViewModel.swift**

```swift
// DoseTrack/ViewModels/MedicationsViewModel.swift
import CoreData
import Combine

@MainActor
final class MedicationsViewModel: ObservableObject {

    @Published var medications: [Medication] = []
    @Published var showingPaywall: Bool = false
    @Published var showingAddForm: Bool = false
    @Published var medicationToEdit: Medication?
    @Published var medicationToDelete: Medication?
    @Published var showingDeleteConfirm: Bool = false

    private let context: NSManagedObjectContext
    private let isProSubscriber: () -> Bool

    init(context: NSManagedObjectContext, isProSubscriber: @escaping () -> Bool = {
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
    }) {
        self.context = context
        self.isProSubscriber = isProSubscriber
        fetchMedications()
    }

    // MARK: - Public

    func fetchMedications() {
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Medication.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)
        ]
        medications = (try? context.fetch(request)) ?? []
    }

    /// Returns false and sets showingPaywall if at free tier limit.
    func canAddMedication() -> Bool {
        if !isProSubscriber() && medications.count >= Constants.FreeTier.maxMedications {
            showingPaywall = true
            return false
        }
        return true
    }

    func requestAddMedication() {
        guard canAddMedication() else { return }
        showingAddForm = true
    }

    func requestEdit(_ medication: Medication) {
        medicationToEdit = medication
    }

    func requestDelete(_ medication: Medication) {
        medicationToDelete = medication
        showingDeleteConfirm = true
    }

    /// Soft-delete: sets isActive = false. Does not permanently destroy.
    func confirmSoftDelete() {
        guard let med = medicationToDelete else { return }
        med.isActive = false
        try? context.save()
        fetchMedications()
        medicationToDelete = nil
    }

    func cancelDelete() {
        medicationToDelete = nil
        showingDeleteConfirm = false
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = medications
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, med) in reordered.enumerated() {
            med.sortOrder = Int32(index)
        }
        try? context.save()
        medications = reordered
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/ViewModels/MedicationsViewModel.swift
git commit -m "feat: add MedicationsViewModel with free-tier gate and soft-delete"
```

---

### Task 3: AddEditMedicationViewModel

**Files:**
- Create: `DoseTrack/ViewModels/AddEditMedicationViewModel.swift`

- [ ] **Step 1: Write AddEditMedicationViewModel.swift**

```swift
// DoseTrack/ViewModels/AddEditMedicationViewModel.swift
import CoreData
import SwiftUI

struct ScheduleDraft: Identifiable {
    var id = UUID()
    var hour: Int = 8
    var minute: Int = 0
    var frequency: String = "daily"
    var daysOfWeek: [Int] = []
    var isEnabled: Bool = true
}

@MainActor
final class AddEditMedicationViewModel: ObservableObject {

    // MARK: - Form state

    @Published var name: String = ""
    @Published var dosage: String = ""
    @Published var unit: String = "pill"
    @Published var colorHex: String = "#5B8AF0"
    @Published var notes: String = ""
    @Published var currentCount: Int = 0
    @Published var refillThreshold: Int = 7
    @Published var schedules: [ScheduleDraft] = [ScheduleDraft()]
    @Published var photoData: Data? = nil

    // MARK: - Validation

    @Published var nameError: String? = nil
    @Published var dosageError: String? = nil

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !dosage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - State

    let isEditing: Bool
    private let medication: Medication?
    private let context: NSManagedObjectContext

    static let unitOptions = ["pill", "ml", "mg", "injection", "supplement", "drop", "spray"]
    static let colorOptions = [
        "#5B8AF0", "#FF6B6B", "#4ECDC4", "#45B7D1",
        "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8"
    ]

    // MARK: - Init

    init(context: NSManagedObjectContext, medication: Medication? = nil) {
        self.context = context
        self.medication = medication
        self.isEditing = medication != nil

        if let med = medication {
            name = med.wrappedName
            dosage = med.wrappedDosage
            unit = med.wrappedUnit
            colorHex = med.wrappedColorHex
            notes = med.wrappedNotes
            currentCount = Int(med.currentCount)
            refillThreshold = Int(med.refillThreshold)
            photoData = med.photoData
            schedules = med.schedulesArray.map { s in
                ScheduleDraft(
                    id: s.id ?? UUID(),
                    hour: Int(s.hour),
                    minute: Int(s.minute),
                    frequency: s.wrappedFrequency,
                    daysOfWeek: s.daysOfWeekArray,
                    isEnabled: s.isEnabled
                )
            }
            if schedules.isEmpty { schedules = [ScheduleDraft()] }
        }
    }

    // MARK: - Actions

    func addSchedule() {
        schedules.append(ScheduleDraft())
    }

    func removeSchedule(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        if schedules.isEmpty { schedules = [ScheduleDraft()] }
    }

    func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
        dosageError = dosage.trimmingCharacters(in: .whitespaces).isEmpty ? "Dosage is required" : nil
        return isValid
    }

    @discardableResult
    func save() -> Medication? {
        guard validate() else { return nil }

        let med: Medication
        if let existing = medication {
            med = existing
        } else {
            med = Medication(context: context)
            med.id = UUID()
            med.createdAt = Date()
            med.isActive = true
        }

        med.name = name.trimmingCharacters(in: .whitespaces)
        med.dosage = dosage.trimmingCharacters(in: .whitespaces)
        med.unit = unit
        med.colorHex = colorHex
        med.notes = notes.trimmingCharacters(in: .whitespaces)
        med.currentCount = Int32(currentCount)
        med.refillThreshold = Int32(refillThreshold)
        med.photoData = photoData
        med.totalDosesPerDay = Int32(schedules.filter { $0.isEnabled }.count)

        // Rebuild schedules: delete old, create new
        if let existing = medication {
            for old in existing.schedulesArray {
                context.delete(old)
            }
        }
        for draft in schedules {
            let s = Schedule(context: context)
            s.id = UUID()
            s.hour = Int16(draft.hour)
            s.minute = Int16(draft.minute)
            s.frequency = draft.frequency
            s.daysOfWeekArray = draft.daysOfWeek
            s.isEnabled = draft.isEnabled
            s.intervalDays = 1
            s.medication = med
        }

        try? context.save()
        return med
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/ViewModels/AddEditMedicationViewModel.swift
git commit -m "feat: add AddEditMedicationViewModel with form state and validation"
```

---

## Chunk 2: Views — Shell + Today

### Task 4: Replace ContentView with real TabView shell

**Files:**
- Modify: `DoseTrack/App/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView.swift**

```swift
// DoseTrack/App/ContentView.swift
import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today, medications, history, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)

            MedicationsView()
                .tabItem { Label("Medications", systemImage: "pill.fill") }
                .tag(Tab.medications)

            HistoryPlaceholderView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(Tab.history)

            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

// Temporary placeholder views until Phase 4
private struct HistoryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("History — coming in Phase 4")
                .navigationTitle("History")
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Settings — coming in Phase 4")
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
```

- [ ] **Step 2: Build and verify no errors**

```bash
xcodebuild build \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/App/ContentView.swift
git commit -m "feat: replace placeholder ContentView with TabView shell"
```

---

### Task 5: DoseRowView and DoseActionSheet

**Files:**
- Create: `DoseTrack/Views/Today/DoseRowView.swift`
- Create: `DoseTrack/Views/Today/DoseActionSheet.swift`

- [ ] **Step 1: Write DoseRowView.swift**

```swift
// DoseTrack/Views/Today/DoseRowView.swift
import SwiftUI

struct DoseRowView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.medication.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.medication.wrappedName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(entry.medication.wrappedDosage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.scheduledAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusChip(status: entry.status)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.medication.wrappedName), \(entry.medication.wrappedDosage), due at \(entry.scheduledAt.formatted(date: .omitted, time: .shortened)), \(entry.status.displayName)")
    }
}

struct StatusChip: View {
    let status: DoseStatus

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .taken:   return "Taken"
        case .skipped: return "Skipped"
        case .missed:  return "Missed"
        }
    }

    private var color: Color {
        switch status {
        case .taken:   return .green
        case .skipped: return .orange
        case .missed:  return .red
        }
    }
}
```

- [ ] **Step 2: Write DoseActionSheet.swift**

```swift
// DoseTrack/Views/Today/DoseActionSheet.swift
import SwiftUI

struct DoseActionSheet: View {
    let entry: DoseEntry
    let onTaken: () -> Void
    let onSkipped: () -> Void
    let onSnooze: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Medication info
            HStack(spacing: 12) {
                Circle()
                    .fill(entry.medication.color)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading) {
                    Text(entry.medication.wrappedName)
                        .font(.headline)
                    Text("\(entry.medication.wrappedDosage) · \(entry.scheduledAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 20)

            Divider()

            // Actions
            Group {
                actionButton(
                    title: "Mark as Taken",
                    icon: "checkmark.circle.fill",
                    color: .green
                ) {
                    onTaken()
                    dismiss()
                }

                Divider().padding(.leading)

                actionButton(
                    title: "Skip This Dose",
                    icon: "arrow.right.circle.fill",
                    color: .orange
                ) {
                    onSkipped()
                    dismiss()
                }

                Divider().padding(.leading)

                actionButton(
                    title: "Snooze 30 Minutes",
                    icon: "clock.fill",
                    color: .blue
                ) {
                    onSnooze()
                    dismiss()
                }
            }

            Divider()
                .padding(.top, 8)

            Button("Cancel") { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(.background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/Views/Today/
git commit -m "feat: add DoseRowView with status chips and DoseActionSheet"
```

---

### Task 6: TodayView

**Files:**
- Create: `DoseTrack/Views/Today/TodayView.swift`

- [ ] **Step 1: Write TodayView.swift**

```swift
// DoseTrack/Views/Today/TodayView.swift
import SwiftUI

struct TodayView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var viewModel: TodayViewModel
    @State private var selectedEntry: DoseEntry?

    init() {
        // ViewModel initialised with a temporary context; overridden in body via onAppear.
        // Using a workaround: store context at init time is not possible with @Environment,
        // so we use a private wrapper trick below.
        _viewModel = StateObject(wrappedValue: TodayViewModel(
            context: PersistenceController.shared.viewContext
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                // Adherence header
                Section {
                    AdherenceHeaderView(
                        takenCount: viewModel.takenCount,
                        totalCount: viewModel.totalCount,
                        allDone: viewModel.allDonToday
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Dose rows
                if viewModel.doseEntries.isEmpty {
                    Section {
                        Text("No medications scheduled for today")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    // Upcoming (future)
                    let upcoming = viewModel.doseEntries.filter { $0.scheduledAt > Date() && $0.existingLog == nil }
                    let past = viewModel.doseEntries.filter { $0.scheduledAt <= Date() || $0.existingLog != nil }

                    if !past.isEmpty {
                        Section("Due / Past") {
                            ForEach(past) { entry in
                                DoseRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming) { entry in
                                DoseRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.large)
            .refreshable { viewModel.refresh() }
            .sheet(item: $selectedEntry) { entry in
                DoseActionSheet(
                    entry: entry,
                    onTaken:  { viewModel.markTaken(entry) },
                    onSkipped: { viewModel.markSkipped(entry) },
                    onSnooze:  { viewModel.snooze(entry) }
                )
            }
        }
        .onAppear { viewModel.refresh() }
    }
}

private struct AdherenceHeaderView: View {
    let takenCount: Int
    let totalCount: Int
    let allDone: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if allDone {
                    Label("All doses taken today", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("\(takenCount) of \(totalCount) doses taken")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if totalCount > 0 {
                AdherenceRingView(percent: totalCount > 0 ? Double(takenCount) / Double(totalCount) : 0)
                    .frame(width: 44, height: 44)
            }
        }
        .padding()
    }
}

private struct AdherenceRingView: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(percent >= 1.0 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent * 100))%")
                .font(.system(size: 10, weight: .bold))
        }
    }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DoseTrack/Views/Today/TodayView.swift
git commit -m "feat: add TodayView with adherence ring, grouped dose list, and action sheet"
```

---

## Chunk 3: Medications Screens

### Task 7: ScheduleBuilderView

**Files:**
- Create: `DoseTrack/Views/Medications/ScheduleBuilderView.swift`

- [ ] **Step 1: Write ScheduleBuilderView.swift**

```swift
// DoseTrack/Views/Medications/ScheduleBuilderView.swift
import SwiftUI

struct ScheduleBuilderView: View {
    @Binding var draft: ScheduleDraft

    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    // weekday values: 1=Sun, 2=Mon, ... 7=Sat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time picker
            HStack {
                Label("Time", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                DatePicker(
                    "",
                    selection: timeBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }

            // Frequency
            Picker("Frequency", selection: $draft.frequency) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
                Text("Custom Days").tag("custom")
            }
            .pickerStyle(.segmented)

            // Days of week (shown for weekly/custom)
            if draft.frequency != "daily" {
                HStack(spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let weekday = index + 1
                        let selected = draft.daysOfWeek.contains(weekday)
                        Button(day) {
                            if selected {
                                draft.daysOfWeek.removeAll { $0 == weekday }
                            } else {
                                draft.daysOfWeek.append(weekday)
                                draft.daysOfWeek.sort()
                            }
                        }
                        .buttonStyle(DayToggleButtonStyle(selected: selected))
                    }
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = draft.hour
                c.minute = draft.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = c.hour ?? 8
                draft.minute = c.minute ?? 0
            }
        )
    }
}

private struct DayToggleButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/Views/Medications/ScheduleBuilderView.swift
git commit -m "feat: add ScheduleBuilderView with time picker and day-of-week toggle"
```

---

### Task 8: AddEditMedicationView

**Files:**
- Create: `DoseTrack/Views/Medications/AddEditMedicationView.swift`

- [ ] **Step 1: Write AddEditMedicationView.swift**

```swift
// DoseTrack/Views/Medications/AddEditMedicationView.swift
import SwiftUI
import PhotosUI

struct AddEditMedicationView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AddEditMedicationViewModel
    let onSave: (Medication) -> Void

    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section("Medication") {
                    TextField("Name (e.g. Metformin)", text: $viewModel.name)
                        .autocorrectionDisabled()
                    if let err = viewModel.nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    HStack {
                        TextField("Dose (e.g. 500)", text: $viewModel.dosage)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $viewModel.unit) {
                            ForEach(AddEditMedicationViewModel.unitOptions, id: \.self) { u in
                                Text(u).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if let err = viewModel.dosageError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                // Color
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(AddEditMedicationViewModel.colorOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if viewModel.colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { viewModel.colorHex = hex }
                                .accessibilityLabel("Color \(hex)")
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Schedules
                Section("Schedule") {
                    ForEach($viewModel.schedules) { $draft in
                        ScheduleBuilderView(draft: $draft)
                            .padding(.vertical, 4)
                    }
                    .onDelete { viewModel.removeSchedule(at: $0) }

                    Button {
                        viewModel.addSchedule()
                    } label: {
                        Label("Add Another Time", systemImage: "plus.circle")
                    }
                }

                // Refill tracking
                Section("Refill Tracking") {
                    Stepper("Current supply: \(viewModel.currentCount)", value: $viewModel.currentCount, in: 0...9999)
                    Stepper("Alert when below: \(viewModel.refillThreshold)", value: $viewModel.refillThreshold, in: 1...999)
                }

                // Photo
                Section("Photo (optional)") {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack {
                            if let data = viewModel.photoData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, height: 60)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(viewModel.photoData == nil ? "Add bottle photo" : "Change photo")
                                .foregroundStyle(.accentColor)
                        }
                    }
                    .onChange(of: photoPickerItem) { _, item in
                        Task {
                            viewModel.photoData = try? await item?.loadTransferable(type: Data.self)
                        }
                    }

                    if viewModel.photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            viewModel.photoData = nil
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Optional notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Disclaimer
                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Medication" : "New Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let saved = viewModel.save() {
                            onSave(saved)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}

#Preview {
    AddEditMedicationView(
        viewModel: AddEditMedicationViewModel(
            context: PersistenceController.preview.viewContext
        ),
        onSave: { _ in }
    )
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/Views/Medications/AddEditMedicationView.swift
git commit -m "feat: add AddEditMedicationView form with schedule builder and photo picker"
```

---

### Task 9: MedicationDetailView

**Files:**
- Create: `DoseTrack/Views/Medications/MedicationDetailView.swift`

- [ ] **Step 1: Write MedicationDetailView.swift**

```swift
// DoseTrack/Views/Medications/MedicationDetailView.swift
import SwiftUI

struct MedicationDetailView: View {
    @Environment(\.managedObjectContext) private var context
    let medication: Medication
    @State private var showingEditSheet = false

    var body: some View {
        List {
            // Header
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(medication.color)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text(medication.wrappedName)
                            .font(.title2.weight(.semibold))
                        Text("\(medication.wrappedDosage) · \(medication.wrappedUnit)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Schedules
            Section("Schedules") {
                if medication.schedulesArray.isEmpty {
                    Text("No schedules set").foregroundStyle(.secondary)
                } else {
                    ForEach(medication.schedulesArray, id: \.id) { schedule in
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.accentColor)
                            Text(schedule.timeDescription)
                            Spacer()
                            Text(scheduleLabel(schedule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !schedule.isEnabled {
                                Text("Off")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            // Refill
            if medication.currentCount > 0 {
                Section("Supply") {
                    HStack {
                        Label("\(medication.currentCount) remaining", systemImage: "pills.fill")
                        Spacer()
                        if medication.isRefillWarning {
                            Label("Refill soon", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Notes
            if !medication.wrappedNotes.isEmpty {
                Section("Notes") {
                    Text(medication.wrappedNotes)
                        .foregroundStyle(.secondary)
                }
            }

            // Photo
            if let data = medication.photoData, let img = UIImage(data: data) {
                Section("Photo") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Disclaimer
            Section {
                Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(medication.wrappedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddEditMedicationView(
                viewModel: AddEditMedicationViewModel(context: context, medication: medication),
                onSave: { _ in }
            )
        }
    }

    private func scheduleLabel(_ schedule: Schedule) -> String {
        switch schedule.wrappedFrequency {
        case "daily": return "Every day"
        case "weekly", "custom":
            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let selected = schedule.daysOfWeekArray.compactMap { d -> String? in
                guard d >= 1, d <= 7 else { return nil }
                return days[d - 1]
            }
            return selected.isEmpty ? "Every day" : selected.joined(separator: ", ")
        default: return schedule.wrappedFrequency
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/Views/Medications/MedicationDetailView.swift
git commit -m "feat: add MedicationDetailView with schedules, refill warning, and photo"
```

---

### Task 10: MedicationsView + PaywallView stub

**Files:**
- Create: `DoseTrack/Views/Medications/MedicationsView.swift`
- Create: `DoseTrack/Views/Paywall/PaywallView.swift`

- [ ] **Step 1: Write PaywallView.swift** (stub — full implementation in Phase 7)

```swift
// DoseTrack/Views/Paywall/PaywallView.swift
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                Text("DoseTrack Pro")
                    .font(.largeTitle.weight(.bold))

                Text("Unlimited medications, iCloud sync, PDF reports, and family sharing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                        Button {
                            Task { try? await subscriptionManager.purchase(product) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(product.displayName)
                                        .fontWeight(.semibold)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("DoseTrack is a reminder tool, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Write MedicationsView.swift**

```swift
// DoseTrack/Views/Medications/MedicationsView.swift
import SwiftUI

struct MedicationsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var viewModel: MedicationsViewModel
    @State private var navigationPath = NavigationPath()

    init() {
        _viewModel = StateObject(wrappedValue: MedicationsViewModel(
            context: PersistenceController.shared.viewContext
        ))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.medications.isEmpty {
                    emptyState
                } else {
                    medicationsList
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.requestAddMedication()
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add medication")
                    }
                }
            }
            .navigationDestination(for: Medication.self) { med in
                MedicationDetailView(medication: med)
            }
            .sheet(isPresented: $viewModel.showingAddForm, onDismiss: { viewModel.fetchMedications() }) {
                AddEditMedicationView(
                    viewModel: AddEditMedicationViewModel(context: context),
                    onSave: { _ in viewModel.fetchMedications() }
                )
            }
            .sheet(item: $viewModel.medicationToEdit, onDismiss: { viewModel.fetchMedications() }) { med in
                AddEditMedicationView(
                    viewModel: AddEditMedicationViewModel(context: context, medication: med),
                    onSave: { _ in viewModel.fetchMedications() }
                )
            }
            .sheet(isPresented: $viewModel.showingPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                "Delete \(viewModel.medicationToDelete?.wrappedName ?? "medication")?",
                isPresented: $viewModel.showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { viewModel.confirmSoftDelete() }
                Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            } message: {
                Text("This will remove the medication and all its history. This cannot be undone.")
            }
        }
        .onAppear { viewModel.fetchMedications() }
    }

    private var medicationsList: some View {
        List {
            ForEach(viewModel.medications) { med in
                NavigationLink(value: med) {
                    MedicationRowView(medication: med)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.requestDelete(med)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        viewModel.requestEdit(med)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onMove { viewModel.moveItems(from: $0, to: $1) }

            // Free tier indicator
            if !subscriptionManager.isProSubscriber {
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.medications.count) of \(Constants.FreeTier.maxMedications) medications (free tier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.medications.count >= Constants.FreeTier.maxMedications {
                            Button("Upgrade") { viewModel.showingPaywall = true }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pill.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Medications Yet")
                .font(.title2.weight(.semibold))
            Text("Add your first medication to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.requestAddMedication()
            } label: {
                Label("Add Medication", systemImage: "plus")
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct MedicationRowView: View {
    let medication: Medication

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(medication.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.wrappedName)
                    .font(.body.weight(.medium))
                Text("\(medication.wrappedDosage) \(medication.wrappedUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if medication.isRefillWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Refill warning")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MedicationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/Views/Medications/ DoseTrack/Views/Paywall/
git commit -m "feat: add MedicationsView, MedicationDetailView, PaywallView stub"
```

---

## Chunk 4: ViewModel Unit Tests

### Task 11: TodayViewModel unit tests

**Files:**
- Create: `DoseTrackTests/TodayViewModelTests.swift`

- [ ] **Step 1: Write TodayViewModelTests.swift**

```swift
// DoseTrackTests/TodayViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class TodayViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: TodayViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = TodayViewModel(context: context)
    }

    override func tearDownWithError() throws {
        sut = nil
        context = nil
    }

    func testAdherencePercent_zeroWhenNoMedications() {
        sut.refresh()
        XCTAssertEqual(sut.adherencePercent, 100) // no meds = 100% by convention
        XCTAssertEqual(sut.totalCount, 0)
    }

    func testAdherencePercent_calculatesCorrectly() {
        sut.takenCount = 3
        sut.totalCount = 4
        XCTAssertEqual(sut.adherencePercent, 75)
    }

    func testAllDoneToday_trueWhenAllTaken() {
        sut.takenCount = 3
        sut.totalCount = 3
        XCTAssertTrue(sut.allDonToday)
    }

    func testAllDoneToday_falseWhenPartial() {
        sut.takenCount = 2
        sut.totalCount = 3
        XCTAssertFalse(sut.allDonToday)
    }

    func testAllDoneToday_falseWhenZeroTotal() {
        sut.takenCount = 0
        sut.totalCount = 0
        XCTAssertFalse(sut.allDonToday)
    }

    func testMarkTaken_writesLog() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        try context.save()

        let entry = DoseEntry(
            id: UUID(),
            medication: med,
            schedule: schedule,
            scheduledAt: Date(),
            status: .missed,
            existingLog: nil
        )

        sut.markTaken(entry)

        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.doseStatus, .taken)
    }

    func testMarkSkipped_writesLog() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 9, minute: 0)
        try context.save()

        let entry = DoseEntry(
            id: UUID(),
            medication: med,
            schedule: schedule,
            scheduledAt: Date(),
            status: .missed,
            existingLog: nil
        )

        sut.markSkipped(entry)

        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.doseStatus, .skipped)
    }

    func testMarkTaken_updatesExistingLog() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg")
        let schedule = Schedule.create(in: context, medication: med)
        let existing = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .skipped)
        try context.save()

        let entry = DoseEntry(
            id: UUID(),
            medication: med,
            schedule: schedule,
            scheduledAt: Date(),
            status: .skipped,
            existingLog: existing
        )

        sut.markTaken(entry)

        XCTAssertEqual(existing.doseStatus, .taken)
        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1, "Should update, not create a second log")
    }
}
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild test \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  -only-testing:DoseTrackTests \
  2>&1 | grep -E "passed|failed|Executed"
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add DoseTrackTests/TodayViewModelTests.swift
git commit -m "test: add TodayViewModel unit tests for adherence and dose logging"
```

---

### Task 12: MedicationsViewModel unit tests

**Files:**
- Create: `DoseTrackTests/MedicationsViewModelTests.swift`

- [ ] **Step 1: Write MedicationsViewModelTests.swift**

```swift
// DoseTrackTests/MedicationsViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class MedicationsViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: MedicationsViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = MedicationsViewModel(context: context, isProSubscriber: { false })
    }

    override func tearDownWithError() throws {
        sut = nil
        context = nil
    }

    func testFetchMedications_returnsOnlyActive() throws {
        Medication.create(in: context, name: "Active", dosage: "10mg")
        let inactive = Medication.create(in: context, name: "Inactive", dosage: "20mg")
        inactive.isActive = false
        try context.save()

        sut.fetchMedications()

        XCTAssertEqual(sut.medications.count, 1)
        XCTAssertEqual(sut.medications.first?.name, "Active")
    }

    func testCanAddMedication_trueWhenBelowLimit() {
        XCTAssertTrue(sut.canAddMedication())
        XCTAssertFalse(sut.showingPaywall)
    }

    func testCanAddMedication_falseAtFreeTierLimit() throws {
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        sut.fetchMedications()

        let result = sut.canAddMedication()

        XCTAssertFalse(result)
        XCTAssertTrue(sut.showingPaywall)
    }

    func testCanAddMedication_trueForProAtLimit() throws {
        let proSut = MedicationsViewModel(context: context, isProSubscriber: { true })
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        proSut.fetchMedications()

        XCTAssertTrue(proSut.canAddMedication())
        XCTAssertFalse(proSut.showingPaywall)
    }

    func testConfirmSoftDelete_setsIsActiveToFalse() throws {
        let med = Medication.create(in: context, name: "To Delete", dosage: "5mg")
        try context.save()
        sut.fetchMedications()

        sut.requestDelete(med)
        sut.confirmSoftDelete()

        XCTAssertFalse(med.isActive)
        XCTAssertEqual(sut.medications.count, 0)
        XCTAssertNil(sut.medicationToDelete)
    }

    func testCancelDelete_clearsState() throws {
        let med = Medication.create(in: context, name: "Keep Me", dosage: "10mg")
        try context.save()

        sut.requestDelete(med)
        XCTAssertNotNil(sut.medicationToDelete)

        sut.cancelDelete()

        XCTAssertNil(sut.medicationToDelete)
        XCTAssertFalse(sut.showingDeleteConfirm)
    }

    func testMoveItems_updatesSortOrder() throws {
        for i in 0..<3 {
            let m = Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
            m.sortOrder = Int32(i)
        }
        try context.save()
        sut.fetchMedications()

        sut.moveItems(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(sut.medications[2].wrappedName, "Med 0")
    }
}
```

- [ ] **Step 2: Run all tests**

```bash
xcodebuild test \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  -only-testing:DoseTrackTests \
  2>&1 | grep -E "passed|failed|Executed"
```

Expected: All tests pass, zero failures.

- [ ] **Step 3: Commit**

```bash
git add DoseTrackTests/MedicationsViewModelTests.swift
git commit -m "test: add MedicationsViewModel unit tests — CRUD, free-tier gate, soft-delete"
```

---

### Task 13: AddEditMedicationViewModel unit tests

**Files:**
- Create: `DoseTrackTests/AddEditMedicationViewModelTests.swift`

- [ ] **Step 1: Write AddEditMedicationViewModelTests.swift**

```swift
// DoseTrackTests/AddEditMedicationViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class AddEditMedicationViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        context = nil
    }

    func testSave_createsNewMedication() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Lisinopril"
        vm.dosage = "10mg"

        let result = vm.save()

        XCTAssertNotNil(result)
        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.name, "Lisinopril")
    }

    func testSave_createsSchedules() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Metformin"
        vm.dosage = "500mg"
        vm.schedules = [
            ScheduleDraft(hour: 8, minute: 0),
            ScheduleDraft(hour: 20, minute: 0)
        ]

        vm.save()

        let schedules = try context.fetch(Schedule.fetchRequest())
        XCTAssertEqual(schedules.count, 2)
    }

    func testSave_failsWithEmptyName() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = ""
        vm.dosage = "10mg"

        let result = vm.save()

        XCTAssertNil(result)
        XCTAssertNotNil(vm.nameError)
    }

    func testSave_failsWithEmptyDosage() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Aspirin"
        vm.dosage = ""

        let result = vm.save()

        XCTAssertNil(result)
        XCTAssertNotNil(vm.dosageError)
    }

    func testSave_updatesExistingMedication() throws {
        let med = Medication.create(in: context, name: "Old Name", dosage: "5mg")
        try context.save()

        let vm = AddEditMedicationViewModel(context: context, medication: med)
        vm.name = "New Name"
        vm.dosage = "10mg"
        vm.save()

        XCTAssertEqual(med.name, "New Name")
        XCTAssertEqual(med.dosage, "10mg")
        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.count, 1, "Should update, not create a second medication")
    }

    func testSave_replacesSchedulesOnEdit() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000 IU")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        Schedule.create(in: context, medication: med, hour: 20, minute: 0)
        try context.save()

        let vm = AddEditMedicationViewModel(context: context, medication: med)
        vm.schedules = [ScheduleDraft(hour: 12, minute: 30)]
        vm.save()

        let schedules = try context.fetch(Schedule.fetchRequest())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.hour, 12)
        XCTAssertEqual(schedules.first?.minute, 30)
    }

    func testIsEditing_trueForExistingMedication() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "5mg")
        let vm = AddEditMedicationViewModel(context: context, medication: med)
        XCTAssertTrue(vm.isEditing)
    }

    func testIsEditing_falseForNewMedication() {
        let vm = AddEditMedicationViewModel(context: context)
        XCTAssertFalse(vm.isEditing)
    }

    func testAddSchedule_appendsNewDraft() {
        let vm = AddEditMedicationViewModel(context: context)
        XCTAssertEqual(vm.schedules.count, 1)
        vm.addSchedule()
        XCTAssertEqual(vm.schedules.count, 2)
    }

    func testRemoveSchedule_keepsMinimumOne() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.removeSchedule(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.schedules.count, 1, "Should never have zero schedules")
    }
}
```

- [ ] **Step 2: Run all tests**

```bash
xcodebuild test \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,id=86B40524-D181-4453-8FE7-1A64E0EFADAF' \
  -only-testing:DoseTrackTests \
  2>&1 | grep -E "passed|failed|Executed"
```

Expected: All tests pass, zero failures.

- [ ] **Step 3: Final commit**

```bash
git add DoseTrackTests/AddEditMedicationViewModelTests.swift
git commit -m "test: add AddEditMedicationViewModel unit tests — validation, CRUD, schedule management"
git tag phase2-complete
```

---

## Phase Boundary

**Phase 2 is complete when:**
- `xcodebuild build` succeeds with zero errors
- `xcodebuild test` passes all tests (target ≥ 30 total)
- TabView has all four tabs visible
- MedicationsView lists medications, supports add/edit/delete
- Today screen shows today's medication schedule
- Free-tier gate shows PaywallView stub at medication #6

**Next plan:** `2026-06-28-phase3-notifications.md` — `NotificationManager`, `NotificationScheduler`, background refresh, action handling.
