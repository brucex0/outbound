import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @EnvironmentObject var authStore: AuthStore
    @State private var phone = ""
    @State private var code = ""
    @State private var verificationId: String?
    @State private var step: Step = .phone

    enum Step { case phone, code }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
            Text("Outbound").font(.largeTitle.bold())

            if step == .phone {
                VStack(spacing: 12) {
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                    Button("Continue") { sendCode() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            } else {
                VStack(spacing: 12) {
                    TextField("Verification code", text: $code)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Verify") { verifyCode() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
            Spacer()
        }
        .padding(32)
    }

    private func sendCode() {
        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { id, _ in
            if let id { verificationId = id; step = .code }
        }
    }

    private func verifyCode() {
        guard let vid = verificationId else { return }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: vid, verificationCode: code)
        Auth.auth().signIn(with: credential) { _, _ in }
    }
}
