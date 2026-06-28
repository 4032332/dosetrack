# DoseTrack Phase 1: Project Setup & Data Layer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a buildable DoseTrack Xcode project with CoreData schema, PersistenceController (free/Pro container switching), and StoreKit 2 SubscriptionManager — all with unit tests.

**Architecture:** xcodegen-defined .xcodeproj; CoreData with `NSPersistentContainer` (free) and `NSPersistentCloudKitContainer` (Pro) behind a single `PersistenceController`; StoreKit 2 `SubscriptionManager` using async/await with `@MainActor`; App Group shared store for widget/watch access.

**Tech Stack:** Swift 5.9+, SwiftUI, Xcode 26, CoreData, CloudKit, StoreKit 2, XCTest, xcodegen (build-time scaffolding only)

---

## Chunk 1: Tooling & Project Scaffolding

### Task 1: Install xcodegen

**Files:**
- No project files — system tool installation

- [ ] **Step 1: Install xcodegen via Homebrew**

```bash
brew install xcodegen
xcodegen --version
```

Expected output: `XcodeGen Version: 2.x.x`

---

### Task 2: Write project.yml for xcodegen

**Files:**
- Create: `project.yml` (repo root — never committed to app bundle, scaffolding only)

- [ ] **Step 1: Create project.yml**

```yaml
name: DoseTrack
options:
  bundleIdPrefix: com.robbrown
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16"
  groupSortPosition: top
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: 5.9
    DEVELOPMENT_TEAM: ""   # Fill in after Xcode opens
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"

targets:
  DoseTrack:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - DoseTrack
    settings:
      base:
        INFOPLIST_FILE: DoseTrack/Resources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.robbrown.dosetrack
        CODE_SIGN_ENTITLEMENTS: DoseTrack/Resources/DoseTrack.entitlements
    entitlements:
      path: DoseTrack/Resources/DoseTrack.entitlements
    capabilities:
      push-notifications: {}
    dependencies:
      - target: DoseTrackWidgets
      - target: DoseTrackTests
        embed: false

  DoseTrackWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - DoseTrackWidgets
    settings:
      base:
        INFOPLIST_FILE: DoseTrackWidgets/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.robbrown.dosetrack.widgets
        CODE_SIGN_ENTITLEMENTS: DoseTrackWidgets/DoseTrackWidgets.entitlements

  DoseTrackTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - DoseTrackTests
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/DoseTrack.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/DoseTrack"
    dependencies:
      - target: DoseTrack
```

- [ ] **Step 2: Generate Xcode project**

```bash
cd /Users/robbrown/Desktop/CodingProjects/Apps/dosetrack-ios
xcodegen generate
```

Expected: `✅ Generated project at: DoseTrack.xcodeproj`

---

### Task 3: Create directory structure and stub files

**Files:**
- Create all directories per CLAUDE.md §15 File Structure

- [ ] **Step 1: Scaffold directories and empty placeholder files**

```bash
cd /Users/robbrown/Desktop/CodingProjects/Apps/dosetrack-ios
mkdir -p DoseTrack/App
mkdir -p DoseTrack/Models
mkdir -p DoseTrack/Services
mkdir -p DoseTrack/ViewModels
mkdir -p DoseTrack/Views/{Today,Medications,History,Settings,Onboarding,Paywall}
mkdir -p DoseTrack/Utilities
mkdir -p DoseTrack/Resources
mkdir -p DoseTrackWidgets
mkdir -p DoseTrackTests
```

- [ ] **Step 2: Create Info.plist**

```xml
<!-- DoseTrack/Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DoseTrack</string>
    <key>CFBundleDisplayName</key>
    <string>DoseTrack</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>NSCameraUsageDescription</key>
    <string>DoseTrack uses your camera to photograph medication bottles for easy identification.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>DoseTrack accesses your photo library so you can attach a bottle photo to a medication.</string>
    <key>UIBackgroundModes</key>
    <array>
        <string>fetch</string>
        <string>remote-notification</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create entitlements file**

```xml
<!-- DoseTrack/Resources/DoseTrack.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.developer.usernotifications.critical-alerts</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.robbrown.dosetrack</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.robbrown.dosetrack</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Create Constants.swift**

```swift
// DoseTrack/Utilities/Constants.swift
import Foundation

enum Constants {
    enum AppGroup {
        static let identifier = "group.com.robbrown.dosetrack"
    }

    enum StoreKit {
        static let proMonthly = "com.robbrown.dosetrack.pro.monthly"
        static let proAnnual = "com.robbrown.dosetrack.pro.annual"
    }

    enum UserDefaultsKeys {
        static let isProSubscriber = "isProSubscriber"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastNotificationRefresh = "lastNotificationRefresh"
    }

    enum FreeTier {
        static let maxMedications = 5
    }

    enum Notification {
        static let categoryMedicationDue = "MEDICATION_DUE"
        static let actionTakeDose = "TAKE_DOSE"
        static let actionSkipDose = "SKIP_DOSE"
        static let actionSnooze30 = "SNOOZE_30"
    }
}
```

- [ ] **Step 5: Commit scaffolding**

```bash
git init
git add project.yml DoseTrack/ DoseTrackWidgets/ DoseTrackTests/ DoseTrack.xcodeproj/
git commit -m "feat: scaffold DoseTrack project with xcodegen and directory structure"
```

---

## Chunk 2: CoreData Schema

### Task 4: Create CoreData model XML

**Files:**
- Create: `DoseTrack/Models/DoseTrack.xcdatamodeld/DoseTrack.xcdatamodel/contents`

CoreData .xcdatamodeld is an XML file. We create it manually so it is version-controlled and reproducible without Xcode GUI.

- [ ] **Step 1: Create the xcdatamodeld bundle directories**

```bash
mkdir -p "DoseTrack/Models/DoseTrack.xcdatamodeld/DoseTrack.xcdatamodel"
```

- [ ] **Step 2: Write the CoreData model XML**

```xml
<!-- DoseTrack/Models/DoseTrack.xcdatamodeld/DoseTrack.xcdatamodel/contents -->
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0"
       lastSavedToolsVersion="23788" systemVersion="24A348" minimumToolsVersion="Automatic"
       sourceLanguage="Swift" userDefinedModelVersionIdentifier="">

    <!-- ===== Medication ===== -->
    <entity name="Medication" representedClassName="Medication" syncable="YES">
        <attribute name="colorHex"         optional="YES" attributeType="String"/>
        <attribute name="createdAt"        optional="NO"  attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="currentCount"     optional="NO"  attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="dosage"           optional="NO"  attributeType="String"/>
        <attribute name="id"               optional="NO"  attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="isActive"         optional="NO"  attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="name"             optional="NO"  attributeType="String"/>
        <attribute name="notes"            optional="YES" attributeType="String"/>
        <attribute name="photoData"        optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
        <attribute name="refillThreshold"  optional="NO"  attributeType="Integer 32" defaultValueString="7" usesScalarValueType="YES"/>
        <attribute name="sortOrder"        optional="NO"  attributeType="Integer 32" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="totalDosesPerDay" optional="NO"  attributeType="Integer 32" defaultValueString="1" usesScalarValueType="YES"/>
        <attribute name="unit"             optional="NO"  attributeType="String" defaultValueString="pill"/>
        <relationship name="doseLogs"  optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="DoseLog"  inverseName="medication" inverseEntity="DoseLog"/>
        <relationship name="schedules" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Schedule" inverseName="medication" inverseEntity="Schedule"/>
    </entity>

    <!-- ===== Schedule ===== -->
    <entity name="Schedule" representedClassName="Schedule" syncable="YES">
        <attribute name="daysOfWeek"       optional="YES" attributeType="Transformable" valueTransformerName="NSSecureUnarchiveFromDataTransformer" customClassName="[NSNumber]"/>
        <attribute name="frequency"        optional="NO"  attributeType="String" defaultValueString="daily"/>
        <attribute name="hour"             optional="NO"  attributeType="Integer 16" defaultValueString="8" usesScalarValueType="YES"/>
        <attribute name="id"               optional="NO"  attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="intervalDays"     optional="NO"  attributeType="Integer 16" defaultValueString="1" usesScalarValueType="YES"/>
        <attribute name="isEnabled"        optional="NO"  attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="minute"           optional="NO"  attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="notificationIds"  optional="YES" attributeType="Transformable" valueTransformerName="NSSecureUnarchiveFromDataTransformer" customClassName="[NSString]"/>
        <relationship name="medication" optional="NO" maxCount="1" deletionRule="Nullify" destinationEntity="Medication" inverseName="schedules" inverseEntity="Medication"/>
    </entity>

    <!-- ===== DoseLog ===== -->
    <entity name="DoseLog" representedClassName="DoseLog" syncable="YES">
        <attribute name="id"          optional="NO"  attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="loggedAt"    optional="NO"  attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="notes"       optional="YES" attributeType="String"/>
        <attribute name="scheduledAt" optional="NO"  attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="status"      optional="NO"  attributeType="String" defaultValueString="taken"/>
        <relationship name="medication" optional="NO" maxCount="1" deletionRule="Nullify" destinationEntity="Medication" inverseName="doseLogs" inverseEntity="Medication"/>
    </entity>

    <elements>
        <element name="DoseLog"    positionX="-63"  positionY="-18"  width="128" height="133"/>
        <element name="Medication" positionX="-369" positionY="-18"  width="128" height="253"/>
        <element name="Schedule"   positionX="-216" positionY="-18"  width="128" height="178"/>
    </elements>
</model>
```

- [ ] **Step 3: Verify the model file is valid XML**

```bash
xmllint --noout "DoseTrack/Models/DoseTrack.xcdatamodeld/DoseTrack.xcdatamodel/contents" && echo "XML valid"
```

Expected: `XML valid`

- [ ] **Step 4: Commit CoreData model**

```bash
git add DoseTrack/Models/DoseTrack.xcdatamodeld/
git commit -m "feat: add CoreData schema — Medication, Schedule, DoseLog entities"
```

---

### Task 5: CoreData NSManagedObject extensions

**Files:**
- Create: `DoseTrack/Models/Medication+Extensions.swift`
- Create: `DoseTrack/Models/Schedule+Extensions.swift`
- Create: `DoseTrack/Models/DoseLog+Extensions.swift`

- [ ] **Step 1: Write Medication+Extensions.swift**

```swift
// DoseTrack/Models/Medication+Extensions.swift
import CoreData
import SwiftUI

extension Medication {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        dosage: String,
        unit: String = "pill",
        colorHex: String = "#5B8AF0"
    ) -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.name = name
        med.dosage = dosage
        med.unit = unit
        med.colorHex = colorHex
        med.isActive = true
        med.currentCount = 0
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        med.sortOrder = 0
        med.createdAt = Date()
        return med
    }

    // MARK: - Computed

    var color: Color {
        Color(hex: colorHex ?? "#5B8AF0")
    }

    var isRefillWarning: Bool {
        currentCount > 0 && currentCount <= refillThreshold
    }

    var wrappedName: String { name ?? "" }
    var wrappedDosage: String { dosage ?? "" }
    var wrappedUnit: String { unit ?? "pill" }
    var wrappedColorHex: String { colorHex ?? "#5B8AF0" }
    var wrappedNotes: String { notes ?? "" }

    var schedulesArray: [Schedule] {
        (schedules as? Set<Schedule>)?.sorted { $0.hour < $1.hour } ?? []
    }

    var doseLogsArray: [DoseLog] {
        (doseLogs as? Set<DoseLog>)?.sorted { $0.scheduledAt < $1.scheduledAt } ?? []
    }
}
```

- [ ] **Step 2: Write Schedule+Extensions.swift**

```swift
// DoseTrack/Models/Schedule+Extensions.swift
import CoreData

extension Schedule {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        medication: Medication,
        hour: Int16 = 8,
        minute: Int16 = 0,
        frequency: String = "daily"
    ) -> Schedule {
        let schedule = Schedule(context: context)
        schedule.id = UUID()
        schedule.hour = hour
        schedule.minute = minute
        schedule.frequency = frequency
        schedule.intervalDays = 1
        schedule.isEnabled = true
        schedule.medication = medication
        return schedule
    }

    // MARK: - Computed

    /// Decoded days of week. Empty means every day.
    var daysOfWeekArray: [Int] {
        get { (daysOfWeek as? [NSNumber])?.map { $0.intValue } ?? [] }
        set { daysOfWeek = newValue.map { NSNumber(value: $0) } as NSArray }
    }

    var notificationIdsArray: [String] {
        get { (notificationIds as? [NSString])?.map { $0 as String } ?? [] }
        set { notificationIds = newValue as NSArray }
    }

    var timeDescription: String {
        let h = Int(hour)
        let m = Int(minute)
        let components = DateComponents(hour: h, minute: m)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var wrappedFrequency: String { frequency ?? "daily" }
}
```

- [ ] **Step 3: Write DoseLog+Extensions.swift**

```swift
// DoseTrack/Models/DoseLog+Extensions.swift
import CoreData

enum DoseStatus: String, CaseIterable {
    case taken = "taken"
    case skipped = "skipped"
    case missed = "missed"

    var displayName: String {
        switch self {
        case .taken:   return "Taken"
        case .skipped: return "Skipped"
        case .missed:  return "Missed"
        }
    }
}

extension DoseLog {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        medication: Medication,
        scheduledAt: Date,
        status: DoseStatus
    ) -> DoseLog {
        let log = DoseLog(context: context)
        log.id = UUID()
        log.scheduledAt = scheduledAt
        log.loggedAt = Date()
        log.status = status.rawValue
        log.medication = medication
        return log
    }

    // MARK: - Computed

    var doseStatus: DoseStatus {
        DoseStatus(rawValue: status ?? "missed") ?? .missed
    }

    var wrappedNotes: String { notes ?? "" }
}
```

- [ ] **Step 4: Write ColorExtensions.swift** (needed by Medication extension)

```swift
// DoseTrack/Utilities/ColorExtensions.swift
import SwiftUI

extension Color {
    /// Initialise from a hex string like "#5B8AF0" or "5B8AF0"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
```

- [ ] **Step 5: Commit model extensions**

```bash
git add DoseTrack/Models/ DoseTrack/Utilities/ColorExtensions.swift
git commit -m "feat: add NSManagedObject extensions for Medication, Schedule, DoseLog"
```

---

## Chunk 3: PersistenceController

### Task 6: Write PersistenceController

**Files:**
- Create: `DoseTrack/App/PersistenceController.swift`

- [ ] **Step 1: Write PersistenceController.swift**

```swift
// DoseTrack/App/PersistenceController.swift
import CoreData
import CloudKit

/// Central CoreData stack. Uses NSPersistentCloudKitContainer for Pro subscribers,
/// NSPersistentContainer for free tier. Call `reconfigure(isPro:)` when subscription
/// status changes — this tears down and rebuilds the stack.
final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    // MARK: - Public

    private(set) var container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Init

    init(inMemory: Bool = false) {
        let isPro = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        container = Self.makeContainer(isPro: isPro, inMemory: inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Container switching

    /// Call after subscription status changes. Saves any pending changes first.
    func reconfigure(isPro: Bool) {
        try? container.viewContext.save()
        container = Self.makeContainer(isPro: isPro, inMemory: false)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Surface in debug; in production, log to analytics
            assertionFailure("CoreData save failed: \(error)")
        }
    }

    // MARK: - Private factory

    private static func makeContainer(isPro: Bool, inMemory: Bool) -> NSPersistentContainer {
        let modelURL = Bundle.main.url(forResource: "DoseTrack", withExtension: "momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!

        let container: NSPersistentContainer
        if isPro {
            container = NSPersistentCloudKitContainer(name: "DoseTrack", managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: "DoseTrack", managedObjectModel: model)
        }

        let storeURL: URL
        if inMemory {
            storeURL = URL(fileURLWithPath: "/dev/null")
        } else {
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Constants.AppGroup.identifier
            )
            storeURL = (groupURL ?? URL.documentsDirectory)
                .appendingPathComponent("DoseTrack.sqlite")
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        if isPro {
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.robbrown.dosetrack")
        }

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                // In production, handle gracefully (corrupt store recovery, migration failure)
                fatalError("CoreData store failed to load: \(error)")
            }
        }

        return container
    }
}

// MARK: - Preview helper

extension PersistenceController {
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Seed a sample medication for SwiftUI previews
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        Schedule.create(in: context, medication: med, hour: 20, minute: 0)

        let log = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        _ = log

        try? context.save()
        return controller
    }()
}
```

- [ ] **Step 2: Create DoseTrackApp.swift entry point**

```swift
// DoseTrack/App/DoseTrackApp.swift
import SwiftUI

@main
struct DoseTrackApp: App {
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(subscriptionManager)
                .onChange(of: subscriptionManager.isProSubscriber) { _, isPro in
                    persistence.reconfigure(isPro: isPro)
                }
        }
    }
}
```

- [ ] **Step 3: Create placeholder ContentView.swift**

```swift
// DoseTrack/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("DoseTrack — Phase 1 complete")
            .padding()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
```

- [ ] **Step 4: Commit**

```bash
git add DoseTrack/App/
git commit -m "feat: add PersistenceController with free/Pro container switching"
```

---

## Chunk 4: SubscriptionManager

### Task 7: Create Products.storekit configuration

**Files:**
- Create: `DoseTrack/Resources/Products.storekit`

- [ ] **Step 1: Write Products.storekit**

```json
{
  "identifier" : "8A4B3C2D-1E0F-4A5B-8C7D-9E0F1A2B3C4D",
  "nonConsumableProducts" : [],
  "consumableProducts" : [],
  "subscriptionGroups" : [
    {
      "id" : "pro-subscription-group",
      "localizations" : [],
      "name" : "DoseTrack Pro",
      "subscriptions" : [
        {
          "adHocOffers" : [],
          "displayPrice" : "3.99",
          "familySharable" : false,
          "groupNumber" : 1,
          "introductoryOffer" : {
            "duration" : 1,
            "durationUnit" : "WEEK",
            "offerIdentifier" : "weekly_free_trial",
            "offerMode" : "FREE_TRIAL",
            "periodCount" : 1
          },
          "localizations" : [
            {
              "description" : "Full access to all DoseTrack Pro features",
              "displayName" : "DoseTrack Pro Monthly",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.robbrown.dosetrack.pro.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "Pro Monthly",
          "subscriptionGroupID" : "pro-subscription-group",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [],
          "displayPrice" : "29.99",
          "familySharable" : false,
          "groupNumber" : 2,
          "introductoryOffer" : null,
          "localizations" : [
            {
              "description" : "Full access to all DoseTrack Pro features — save 37%",
              "displayName" : "DoseTrack Pro Annual",
              "locale" : "en_US"
            }
          ],
          "productID" : "com.robbrown.dosetrack.pro.annual",
          "recurringSubscriptionPeriod" : "P1Y",
          "referenceName" : "Pro Annual",
          "subscriptionGroupID" : "pro-subscription-group",
          "type" : "RecurringSubscription"
        }
      ]
    }
  ],
  "version" : {
    "major" : 2,
    "minor" : 0
  }
}
```

---

### Task 8: Write SubscriptionManager

**Files:**
- Create: `DoseTrack/Services/SubscriptionManager.swift`

- [ ] **Step 1: Write SubscriptionManager.swift**

```swift
// DoseTrack/Services/SubscriptionManager.swift
import StoreKit
import Combine

/// Manages StoreKit 2 subscription state. Publish `isProSubscriber` to drive
/// UI gating and CoreData container switching.
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Published

    @Published private(set) var isProSubscriber: Bool = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false

    // MARK: - Private

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        isProSubscriber = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        startListeningForTransactionUpdates()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Public API

    func checkEntitlement() async -> Bool {
        await refreshEntitlement()
        return isProSubscriber
    }

    func purchase(_ product: Product) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshEntitlement()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            availableProducts = try await Product.products(for: [
                Constants.StoreKit.proMonthly,
                Constants.StoreKit.proAnnual
            ])
        } catch {
            // Products unavailable — likely in sandbox without network
        }
    }

    @discardableResult
    private func refreshEntitlement() async -> Bool {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               (transaction.productID == Constants.StoreKit.proMonthly ||
                transaction.productID == Constants.StoreKit.proAnnual),
               transaction.revocationDate == nil {
                hasPro = true
                break
            }
        }
        isProSubscriber = hasPro
        UserDefaults.standard.set(hasPro, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        return hasPro
    }

    private func startListeningForTransactionUpdates() {
        updatesTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add DoseTrack/Services/SubscriptionManager.swift DoseTrack/Resources/Products.storekit
git commit -m "feat: add SubscriptionManager with StoreKit 2 async/await"
```

---

## Chunk 5: Unit Tests

### Task 9: Write CoreData CRUD unit tests

**Files:**
- Create: `DoseTrackTests/CoreDataTests.swift`

- [ ] **Step 1: Write CoreDataTests.swift**

```swift
// DoseTrackTests/CoreDataTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class CoreDataTests: XCTestCase {

    var sut: PersistenceController!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        sut = PersistenceController(inMemory: true)
        context = sut.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        sut = nil
    }

    // MARK: - Medication

    func testCreateMedication_persistsCorrectly() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        let results = try context.fetch(fetch)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Aspirin")
        XCTAssertEqual(results.first?.dosage, "81mg")
        XCTAssertTrue(results.first?.isActive == true)
        XCTAssertNotNil(results.first?.id)
        XCTAssertNotNil(results.first?.createdAt)
    }

    func testSoftDeleteMedication_setsIsActiveToFalse() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        try context.save()

        med.isActive = false
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        fetch.predicate = NSPredicate(format: "isActive == YES")
        let activeResults = try context.fetch(fetch)
        XCTAssertEqual(activeResults.count, 0)
    }

    func testDeleteMedication_cascadesToSchedulesAndLogs() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        try context.save()

        context.delete(med)
        try context.save()

        let schedFetch = NSFetchRequest<Schedule>(entityName: "Schedule")
        let logFetch = NSFetchRequest<DoseLog>(entityName: "DoseLog")
        let schedules = try context.fetch(schedFetch)
        let logs = try context.fetch(logFetch)

        XCTAssertEqual(schedules.count, 0, "Schedules should cascade-delete with medication")
        XCTAssertEqual(logs.count, 0, "DoseLogs should cascade-delete with medication")
    }

    // MARK: - Schedule

    func testCreateSchedule_linkedToMedication() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000 IU")
        let schedule = Schedule.create(in: context, medication: med, hour: 9, minute: 30)
        try context.save()

        XCTAssertEqual(schedule.medication, med)
        XCTAssertEqual(schedule.hour, 9)
        XCTAssertEqual(schedule.minute, 30)
        XCTAssertTrue(schedule.isEnabled)
        XCTAssertNotNil(schedule.id)
    }

    func testSchedule_daysOfWeekRoundTrip() throws {
        let med = Medication.create(in: context, name: "Omega-3", dosage: "1000mg")
        let schedule = Schedule.create(in: context, medication: med)
        schedule.daysOfWeekArray = [2, 4, 6] // Mon, Wed, Fri
        try context.save()

        // Fetch fresh to verify transformer round-trip
        context.refresh(schedule, mergeChanges: false)
        XCTAssertEqual(schedule.daysOfWeekArray, [2, 4, 6])
    }

    // MARK: - DoseLog

    func testCreateDoseLog_withTakenStatus() throws {
        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        let scheduled = Date()
        let log = DoseLog.create(in: context, medication: med, scheduledAt: scheduled, status: .taken)
        try context.save()

        XCTAssertEqual(log.doseStatus, .taken)
        XCTAssertEqual(log.scheduledAt, scheduled)
        XCTAssertNotNil(log.loggedAt)
        XCTAssertEqual(log.medication, med)
    }

    func testCreateDoseLog_allStatuses() throws {
        let med = Medication.create(in: context, name: "Atorvastatin", dosage: "20mg")
        let date = Date()
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .skipped)
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .missed)
        try context.save()

        let fetch = NSFetchRequest<DoseLog>(entityName: "DoseLog")
        let logs = try context.fetch(fetch)
        let statuses = Set(logs.map { $0.doseStatus })
        XCTAssertEqual(statuses, [.taken, .skipped, .missed])
    }

    // MARK: - PersistenceController

    func testPersistenceController_saveNoop_whenNoChanges() {
        // Should not throw or crash when context has no changes
        sut.save()
    }

    func testPersistenceController_preview_hasSeedData() {
        let previewContext = PersistenceController.preview.viewContext
        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        let results = try? previewContext.fetch(fetch)
        XCTAssertFalse(results?.isEmpty ?? true, "Preview should have seed medication")
    }

    // MARK: - Free Tier Limit

    func testFreeTierLimit_maxFiveMedications() throws {
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        fetch.predicate = NSPredicate(format: "isActive == YES")
        let count = try context.count(for: fetch)
        XCTAssertEqual(count, Constants.FreeTier.maxMedications)
    }
}
```

- [ ] **Step 2: Write SubscriptionManager unit tests**

```swift
// DoseTrackTests/SubscriptionManagerTests.swift
import XCTest
@testable import DoseTrack

/// Note: Full StoreKit 2 purchase-flow testing requires a StoreKit test environment.
/// These tests verify the synchronous/cached behaviour that doesn't need the App Store.
final class SubscriptionManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset cached Pro status before each test
        UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.isProSubscriber)
    }

    func testIsProSubscriber_defaultsToFalse() {
        let manager = SubscriptionManager()
        XCTAssertFalse(manager.isProSubscriber)
    }

    func testIsProSubscriber_respectsCachedValue() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        let manager = SubscriptionManager()
        XCTAssertTrue(manager.isProSubscriber)
    }

    func testConstants_productIDs_areCorrect() {
        XCTAssertEqual(Constants.StoreKit.proMonthly, "com.robbrown.dosetrack.pro.monthly")
        XCTAssertEqual(Constants.StoreKit.proAnnual, "com.robbrown.dosetrack.pro.annual")
    }

    func testConstants_freeTier_maxFiveMeds() {
        XCTAssertEqual(Constants.FreeTier.maxMedications, 5)
    }
}
```

- [ ] **Step 3: Run all tests and verify they pass**

```bash
xcodebuild test \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:DoseTrackTests \
  | xcpretty
```

Expected: All tests PASS. Zero failures.

- [ ] **Step 4: Commit**

```bash
git add DoseTrackTests/
git commit -m "test: add CoreData CRUD and SubscriptionManager unit tests — all pass"
```

---

## Chunk 6: Build Verification

### Task 10: Verify clean build

- [ ] **Step 1: Attempt a build for simulator**

```bash
xcodebuild build \
  -project DoseTrack.xcodeproj \
  -scheme DoseTrack \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  | tail -20
```

Expected final line: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Fix any compiler errors before proceeding to Phase 2**

If build fails, read the error output carefully and fix the specific file(s) before moving on.

- [ ] **Step 3: Tag Phase 1 complete**

```bash
git tag phase1-complete
echo "Phase 1 complete. Ready for Phase 2: Core UI."
```

---

## Phase Boundary

**Phase 1 is complete when:**
- `xcodebuild test` passes with zero failures
- `xcodebuild build` succeeds with zero warnings
- All three CoreData entities exist in the model
- `PersistenceController` loads in-memory and on-disk
- `SubscriptionManager` initialises without crashing

**Next plan:** `2026-06-28-phase2-core-ui.md` — TabView shell, Today screen, Medications list, Add/Edit form.
