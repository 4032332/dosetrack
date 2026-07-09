// DoseTrack/Views/Settings/ProfileView.swift
import SwiftUI
import Auth

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @AppStorage("patientName")           private var patientName: String = ""
    @AppStorage("patientDOBInterval")    private var patientDOBInterval: Double = 0
    @AppStorage("patientGender")         private var patientGender: String = ""
    @AppStorage("patientPhone")          private var patientPhone: String = ""
    @AppStorage("patientCountry")        private var patientCountry: String = ""
    @AppStorage("patientState")          private var patientState: String = ""
    @AppStorage("selectedAvatar")        private var selectedAvatar: String = "milli"
    @AppStorage("customAvatarData")      private var customAvatarDataBase64: String = ""

    @State private var showingAvatarPicker = false
    @State private var isSaving = false
    @State private var toast: ToastMessage? = nil
    @State private var countryInput: String = ""
    @State private var countryFocused = false

    /// Bridge between Data and the Base64 string stored in AppStorage.
    private var customPhotoData: Binding<Data?> {
        Binding(
            get: {
                customAvatarDataBase64.isEmpty ? nil
                    : Data(base64Encoded: customAvatarDataBase64)
            },
            set: { newData in
                customAvatarDataBase64 = newData?.base64EncodedString() ?? ""
            }
        )
    }

    private var patientDOB: Binding<Date> {
        Binding(
            get: {
                patientDOBInterval == 0
                    ? Calendar.current.date(byAdding: .year, value: -30, to: Date())!
                    : Date(timeIntervalSince1970: patientDOBInterval)
            },
            set: { patientDOBInterval = $0.timeIntervalSince1970 }
        )
    }

    private var genderEligibleForContraceptive: Bool {
        patientGender != "Male" && !patientGender.isEmpty
    }

    private var isPro: Bool { subscriptionManager.isProSubscriber }

    var body: some View {
        List {
            // MARK: Avatar
            Section {
                HStack {
                    Spacer()
                    Button { showingAvatarPicker = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarBadge(avatarKey: selectedAvatar, isPro: isPro,
                                        size: 90, customImageData: customPhotoData.wrappedValue)
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.accentColor)
                                .background(Circle().fill(.white).padding(2))
                                .offset(x: 4, y: 4)
                        }
                        .accessibilityLabel("Change profile photo")
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)

                if isPro {
                    HStack {
                        Spacer()
                        Label("Milli Pro", systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.15), in: Capsule())
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            // MARK: Personal
            Section("Personal") {
                HStack {
                    Label("Full Name", systemImage: "person.fill")
                    TextField("Your name", text: $patientName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                if patientDOBInterval != 0 {
                    CollapsibleDatePicker(
                        label: "Date of Birth",
                        systemImage: "calendar",
                        date: patientDOB,
                        range: ...Date()
                    )
                    Button("Remove date of birth", role: .destructive) {
                        patientDOBInterval = 0
                    }
                    .font(.caption)
                } else {
                    Button {
                        patientDOBInterval = Calendar.current
                            .date(byAdding: .year, value: -30, to: Date())!
                            .timeIntervalSince1970
                    } label: {
                        HStack {
                            Label("Date of Birth", systemImage: "calendar")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Add")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                Picker(selection: $patientGender) {
                    Text("Not set").tag("")
                    Text("Female").tag("Female")
                    Text("Male").tag("Male")
                    Text("Non-binary").tag("Non-binary")
                    Text("Other").tag("Other")
                    Text("Prefer not to say").tag("Prefer not to say")
                } label: {
                    Label("Gender", systemImage: "person.crop.circle")
                }
            }

            // MARK: Account
            Section("Account") {
                HStack {
                    Label("Email", systemImage: "envelope.fill")
                    Spacer()
                    Text(auth.userEmail.isEmpty ? "Guest" : auth.userEmail)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                HStack {
                    Label("Phone", systemImage: "phone.fill")
                    TextField("Optional", text: $patientPhone)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.phonePad)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Location
            Section {
                CountryAutocompleteField(
                    selectedCountry: $patientCountry,
                    inputText: $countryInput,
                    isFocused: $countryFocused
                )

                HStack {
                    Label("State / Province", systemImage: "map.fill")
                    TextField("Optional", text: $patientState)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Helps contextualise medications — some drugs have country-specific brand names or dosing guidelines.")
                    .font(.caption)
            }
            .onAppear { countryInput = patientCountry }

            // MARK: Health Preferences
            if genderEligibleForContraceptive {
                Section {
                    NavigationLink(destination: ContraceptiveTrackerView()) {
                        Label("Contraceptive Tracker", systemImage: "calendar.badge.clock")
                    }
                } header: {
                    Text("Health Preferences")
                } footer: {
                    Text("Track implants, IUDs, injections, pills and more with personalised due-date reminders.")
                }
            }
        }
        .scrollIndicators(.visible)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await saveToSupabase(showToast: true) }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }
        }
        .sheet(isPresented: $showingAvatarPicker) {
            AvatarPickerView(selectedKey: $selectedAvatar, customPhotoData: customPhotoData)
        }
        .toast($toast)
        // Local fields (@AppStorage) save instantly as the user types, but the remote
        // Supabase copy only updated on an explicit tap of the toolbar Save button — so
        // if a user edited a field and just navigated back, the next pull-on-launch would
        // silently overwrite their edit with the stale remote value (this is exactly how
        // Date of Birth kept reverting). Saving on disappear closes that gap.
        .onDisappear {
            Task { await saveToSupabase(showToast: true) }
        }
    }

    // MARK: - Supabase sync

    private func saveToSupabase(showToast: Bool) async {
        guard auth.isSignedIn, !auth.isGuest else {
            // Guest mode — data is local only, that's fine
            if showToast { toast = ToastMessage(text: "Saved", systemImage: "checkmark.circle.fill") }
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            var metadata: [String: AnyJSON] = [
                "full_name": .string(patientName),
                "gender": .string(patientGender),
                "phone": .string(patientPhone),
                "country": .string(patientCountry),
                "state": .string(patientState),
            ]
            if patientDOBInterval > 0 {
                metadata["date_of_birth"] = .string(
                    ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: patientDOBInterval))
                )
            }
            // Refresh the JWT before updating — prevents "Auth session missing" on stale tokens
            _ = try await auth.client.auth.session
            try await auth.client.auth.update(user: UserAttributes(data: metadata))
            // Also persist all settings to Supabase user_settings table
            await SupabaseSyncManager.shared.pushSettings()
            if showToast { toast = ToastMessage(text: "Saved", systemImage: "checkmark.circle.fill") }
        } catch {
            if showToast {
                toast = ToastMessage(text: "Save failed", systemImage: "exclamationmark.triangle.fill", isError: true)
            }
        }
    }
}

// MARK: - Country Autocomplete Field

private struct CountryAutocompleteField: View {
    @Binding var selectedCountry: String
    @Binding var inputText: String
    @Binding var isFocused: Bool

    @FocusState private var fieldFocused: Bool

    private static let allCountries: [String] = Locale.Region.isoRegions
        .compactMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
        .sorted()

    private var suggestions: [String] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != selectedCountry.lowercased() else { return [] }
        return Self.allCountries
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Country", text: $inputText)
                    .focused($fieldFocused)
                    .autocorrectionDisabled()
                    .onChange(of: fieldFocused) { _, focused in
                        isFocused = focused
                        if focused && !selectedCountry.isEmpty {
                            inputText = selectedCountry
                        }
                    }
                    .onChange(of: inputText) { _, text in
                        // If the typed text exactly matches a country, select it immediately
                        if let match = Self.allCountries.first(where: {
                            $0.lowercased() == text.lowercased()
                        }) {
                            selectedCountry = match
                        }
                    }
                    .onSubmit {
                        // On return: commit the top suggestion if available
                        if let top = suggestions.first {
                            selectedCountry = top
                            inputText = top
                        }
                        fieldFocused = false
                    }
                if !selectedCountry.isEmpty && !isFocused {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)

            // Inline suggestion list
            if !suggestions.isEmpty && isFocused {
                Divider().padding(.vertical, 4)
                ForEach(suggestions, id: \.self) { country in
                    Button {
                        selectedCountry = country
                        inputText = country
                        fieldFocused = false
                    } label: {
                        HStack {
                            Text(country)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            // Highlight the matching portion
                            if let range = country.range(of: inputText,
                                options: .caseInsensitive) {
                                let matched = String(country[range])
                                Text(matched)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if country != suggestions.last {
                        Divider()
                    }
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && selectedCountry.isEmpty {
                inputText = ""
            } else if !focused {
                inputText = selectedCountry
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthManager.shared)
            .environmentObject(SubscriptionManager())
    }
}
