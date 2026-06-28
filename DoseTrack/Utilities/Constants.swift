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
