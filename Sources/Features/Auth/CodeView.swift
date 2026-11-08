import SwiftUI

struct CodeView: View {
    @Bindable var auth: AuthViewModel
    let info: CodeInfo
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                Text(AuthLabels.codeSent(info))
                TextField("Code", text: $code)
                    .keyboardType(isDigitCode ? .numberPad : .default)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .authField(label: "Code de connexion", error: auth.errorMessage, errorCount: auth.errorCount)
            }

            ErrorSection(message: auth.errorMessage)

            Section {
                SubmitButton(title: "Valider le code", isBusy: auth.isBusy) {
                    auth.submitCode(code)
                }
            }

            Section {
                if let next = info.nextDelivery {
                    Button(AuthLabels.resendButton(next)) { auth.resendCode() }
                        .disabled(auth.isBusy)
                }
                ChangePhoneNumberButton(auth: auth)
            } footer: {
                if info.nextDelivery != nil {
                    Text(AuthLabels.resendAvailability(after: info.resendTimeout))
                }
            }
        }
        .navigationTitle("Code de connexion")
        .onChange(of: info) { code = "" }
    }

    private var isDigitCode: Bool {
        switch info.delivery {
        case .smsWord, .smsPhrase: return false
        default: return true
        }
    }
}
