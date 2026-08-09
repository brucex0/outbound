import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        VStack(spacing: 0) {
            Text("OUTBOUND")
                .font(.subheadline.weight(.medium))
                .tracking(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            WelcomeOrbit()
                .frame(height: 245)

            VStack(spacing: 8) {
                Text("YOUR AI RUNNING COMPANION")
                    .font(.caption.weight(.medium))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                Text("Train with purpose.\nRun with your people.")
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer(minLength: 22)

            VStack(spacing: 10) {
                providerButton("Continue with Apple", icon: {
                    Image(systemName: "apple.logo")
                }, action: {
                    Task { await authStore.signInWithApple() }
                })
                .disabled(!authStore.isAppleSignInAvailable || authStore.isBusy)

                providerButton("Continue with Google", icon: {
                    Text("G").font(.headline)
                }, action: {
                    Task { await authStore.signInWithGoogle() }
                })
                .disabled(!authStore.isFirebaseConfigured || authStore.isBusy)

                if authStore.isBusy {
                    ProgressView()
                        .tint(OutboundPalette.companion)
                        .padding(.top, 4)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(authStore.authError == nil ? Color.secondary : Color.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutboundPalette.background.ignoresSafeArea())
    }

    private func providerButton<Icon: View>(
        _ title: String,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon()
                    .frame(width: 20)
                Text(title)
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.primary)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
    }

    private var statusMessage: String? {
        if let error = authStore.authError { return error }
        if !authStore.isFirebaseConfigured {
            return "Sign in is unavailable in this build."
        }
        if !authStore.isAppleSignInAvailable {
            return "Apple sign-in is unavailable. Continue with Google."
        }
        return nil
    }
}

private struct WelcomeOrbit: View {
    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: 121)

            ZStack {
                Ellipse()
                    .stroke(Color.primary.opacity(0.16), lineWidth: 2)
                    .frame(width: min(proxy.size.width - 48, 255), height: 145)
                    .rotationEffect(.degrees(-8))
                    .position(center)

                orbitPerson("Family", systemImage: "heart.fill", fill: Color(red: 0.88, green: 0.91, blue: 0.88))
                    .position(x: center.x - 102, y: 61)

                orbitPerson("Friends", systemImage: "person.2.fill", fill: Color(red: 0.84, green: 0.86, blue: 0.94))
                    .position(x: center.x + 99, y: 114)

                orbitPerson("Clubs", systemImage: "flag.fill", fill: Color(red: 0.91, green: 0.88, blue: 0.80))
                    .position(x: center.x - 79, y: 146)

                ZStack(alignment: .topTrailing) {
                    orbitPerson("You", systemImage: "person.crop.circle.fill", fill: Color(red: 0.94, green: 0.78, blue: 0.71), size: 72)

                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(OutboundPalette.companion, in: Circle())
                        .overlay(Circle().stroke(OutboundPalette.background, lineWidth: 3))
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
                .position(x: center.x, y: 111)

                Label("Better together", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(OutboundPalette.companion)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(OutboundPalette.companion.opacity(0.1), in: Capsule())
                    .position(x: center.x, y: 220)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your AI running companion brings your training together with family, friends, and clubs.")
    }

    private func orbitPerson(
        _ label: String,
        systemImage: String,
        fill: Color,
        size: CGFloat = 58
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: size == 72 ? 28 : 21, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(OutboundPalette.background, lineWidth: 4))

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
