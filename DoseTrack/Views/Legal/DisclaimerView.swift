// DoseTrack/Views/Legal/DisclaimerView.swift
// One-time Terms of Use & Medical Disclaimer shown right after a user creates an account. It must
// be accepted to reach the app; declining signs the user out. Acceptance is recorded via
// DisclaimerManager (locally + on the Supabase profile).

import SwiftUI

struct DisclaimerConsentView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var agreed = false
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Text(DisclaimerContent.intro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(DisclaimerContent.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.heading)
                                .font(.headline)
                            Text(section.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }

            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(hex: "#3B5FCC"))
            Text("Important — Please Read")
                .font(.title2.bold())
            Text("Terms of Use & Medical Disclaimer")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Divider()

            Button {
                agreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(agreed ? Color(hex: "#3B5FCC") : .secondary)
                    Text("I have read, understand, and agree to the Terms of Use and Medical Disclaimer, and I understand I am waiving certain legal rights by agreeing.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Button {
                isSubmitting = true
                onAccept()
            } label: {
                Text("I Agree")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!agreed || isSubmitting)
            .padding(.horizontal, 20)

            Button("Decline & Sign Out", role: .cancel, action: onDecline)
                .font(.subheadline)
                .disabled(isSubmitting)
                .padding(.bottom, 8)
        }
        .background(.bar)
    }
}

// MARK: - Content

enum DisclaimerContent {
    struct Section: Identifiable {
        let id = UUID()
        let heading: String
        let body: String
    }

    static let intro = "Please read this agreement carefully before using DoseTrack. It explains what DoseTrack is, what it is not, and the limits of our responsibility. You must accept these terms to use the app."

    static let sections: [Section] = [
        Section(
            heading: "Not medical advice",
            body: "DoseTrack does not provide medical or pharmaceutical advice. It is a medication reminder tool only, and is only as accurate as the information you enter. Information shown in the app is for scheduling purposes only and must never replace advice given by a qualified medical practitioner. Always seek advice from a qualified medical practitioner before taking, changing, or stopping any medication."
        ),
        Section(
            heading: "Your responsibility",
            body: "You are solely responsible for entering all medication information and for verifying that everything you enter is correct. DoseTrack assumes no responsibility for errors in data entry, misinterpretation of medical instructions, or the consequences of taking the wrong medication or dosage."
        ),
        Section(
            heading: "Reminders may fail",
            body: "DoseTrack is a software application that relies on third-party hardware, operating systems, and networks, all of which are subject to failure. We do not guarantee that push notifications, alarms, or reminders will be delivered accurately, on time, or at all. You agree to use DoseTrack strictly as a supplementary backup reminder — never as your sole method for managing critical, life-sustaining, or time-sensitive medications."
        ),
        Section(
            heading: "In an emergency",
            body: "In the event of a medical emergency, a missed dose of a critical medication, an accidental overdose, or an adverse drug interaction, contact your local emergency services or a poison control centre immediately. Do not rely on DoseTrack for emergency assistance or instructions."
        ),
        Section(
            heading: "Limitation of liability",
            body: "DoseTrack will not be liable for the mismanagement of medication or for inaccurate inputs. To the maximum extent permitted by applicable law, in no event shall Neurotrocity, or its directors, employees, partners, agents, suppliers, or affiliates, be liable for any direct, indirect, incidental, special, consequential, punitive, or exemplary damages arising from your use of, or inability to use, DoseTrack."
        ),
        Section(
            heading: "Your agreement",
            body: "By tapping \u{201C}I Agree\u{201D} (or by checking the consent box or using DoseTrack), you acknowledge that you have read this agreement, understand it, and agree to be bound by its terms and conditions. You understand that you are waiving certain legal rights by agreeing to these terms."
        ),
    ]
}

#Preview {
    DisclaimerConsentView(onAccept: {}, onDecline: {})
}
