// DoseTrack/Utilities/BuildEnvironment.swift
import Foundation

/// Distinguishes real App Store installs from Xcode debug runs and TestFlight builds.
///
/// Both Xcode-launched debug builds and TestFlight builds carry a StoreKit sandbox
/// receipt named "sandboxReceipt"; a build downloaded from the App Store carries one
/// named "receipt". This is the standard (if slightly informal — Apple doesn't
/// document the filename as a stable contract) way to detect TestFlight at runtime,
/// since there's no dedicated API for it.
enum BuildEnvironment {
    static var isTestFlightOrDebug: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
