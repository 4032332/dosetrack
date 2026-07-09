// DoseTrack/Utilities/ToastView.swift
import SwiftUI

/// A small, self-dismissing banner for lightweight confirmations (e.g. "Saved") that
/// shouldn't interrupt the user with a blocking alert requiring a tap to dismiss.
struct ToastView: View {
    let message: String
    let systemImage: String
    var isError: Bool = false

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isError ? Color.red : Color.green, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ToastView(message: toast.text, systemImage: toast.systemImage, isError: toast.isError)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { self.toast = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: toast)
    }
}

struct ToastMessage: Equatable {
    let text: String
    let systemImage: String
    var isError: Bool = false
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(toast: message))
    }
}
