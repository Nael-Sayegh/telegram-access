import SwiftUI

struct PhoneNumberView: View {
    @Bindable var auth: AuthViewModel
    @State private var number = ""
    @State private var showsCountryPicker = false

    var body: some View {
        Form {
            Section {
                Button {
                    showsCountryPicker = true
                } label: {
                    HStack {
                        Text("Pays")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(countryDisplay)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityValue(countryValue)
                .accessibilityHint("Ouvre la liste des pays, avec recherche.")
                .accessibilityAddTraits(.isButton)
                .authField(.country, label: "Pays", auth: auth, isTextInput: false)

                TextField("Numéro de téléphone", text: $number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .authField(.phoneNumber, label: "Numéro de téléphone", auth: auth)
            } header: {
                Text("Votre numéro de téléphone")
            } footer: {
                Text("Sans l'indicatif du pays, ou au format international en commençant par plus.")
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Recevoir le code", isBusy: auth.isBusy) {
                    auth.submitPhoneNumber(number)
                }
            } footer: {
                AppDisclaimer()
            }
        }
        .navigationTitle("Connexion")
        .sheet(isPresented: $showsCountryPicker) {
            CountryPickerView(
                countries: auth.countries,
                selection: $auth.selectedCountry,
                onRetry: auth.reloadCountries
            )
        }
    }

    private var countryDisplay: String {
        guard let country = auth.selectedCountry else { return "Choisir" }
        return "\(country.flag) \(country.name) +\(country.callingCode)"
    }

    private var countryValue: String {
        guard let country = auth.selectedCountry else { return "Aucun pays choisi" }
        return AuthLabels.country(name: country.name, callingCode: country.callingCode)
    }
}

struct CountryPickerView: View {
    let countries: [Country]
    @Binding var selection: Country?
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if countries.isEmpty {
                    ContentUnavailableView {
                        Label("Liste des pays indisponible", systemImage: "globe")
                    } description: {
                        Text("Vérifiez votre connexion à Internet.")
                    } actions: {
                        Button("Réessayer", action: onRetry)
                    }
                } else {
                    List(filteredCountries) { country in
                        row(for: country)
                    }
                    .overlay {
                        if filteredCountries.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Nom du pays ou indicatif"
            )
            .navigationTitle("Choisir un pays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .accessibilityAction(.escape) { dismiss() }
        }
    }

    private func row(for country: Country) -> some View {
        Button {
            selection = country
            dismiss()
        } label: {
            HStack {
                Text(country.flag)
                Text(country.name)
                Spacer()
                Text("+\(country.callingCode)")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AuthLabels.country(name: country.name, callingCode: country.callingCode))
        .accessibilityAddTraits(selection == country ? [.isButton, .isSelected] : [.isButton])
    }

    private var filteredCountries: [Country] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return countries }
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let digits = trimmed.filter(\.isNumber)
        return countries.filter { country in
            country.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(folded)
                || (!digits.isEmpty && country.callingCode.hasPrefix(digits))
        }
    }
}
