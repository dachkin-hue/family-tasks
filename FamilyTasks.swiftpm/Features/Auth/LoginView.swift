import SwiftUI

/// Экран входа и регистрации. Логика вынесена в `AppSession`,
/// потому что состояние авторизации нужно всему приложению, а не одному экрану.
struct LoginView: View {

    private enum Mode: String, CaseIterable {
        case signIn = "Вход"
        case signUp = "Регистрация"
    }

    private enum Field: Hashable {
        case name, email, password
    }

    @Environment(AppSession.self) private var session

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Режим", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    if mode == .signUp {
                        TextField("Имя", text: $name)
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                    }

                    TextField("Электронная почта", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("Пароль", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } footer: {
                    if let error = session.authError {
                        Text(error.message)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if session.isProcessing {
                                ProgressView()
                            } else {
                                Text(mode == .signIn ? "Войти" : "Создать аккаунт")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isFormValid || session.isProcessing)
                }

                if AppConfig.useMockBackend {
                    Section {
                        Text("Бэкенд ещё не подключён: приложение работает на встроенных данных. Подойдёт любая почта и пароль от 4 символов.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .organicBackground()
            .navigationTitle("Семейные задачи")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.count > 4
        let passwordValid = password.count >= 4
        let nameValid = mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return emailValid && passwordValid && nameValid
    }

    private func submit() {
        guard isFormValid, !session.isProcessing else { return }
        focusedField = nil
        Task {
            switch mode {
            case .signIn:
                await session.signIn(email: email, password: password)
            case .signUp:
                await session.register(name: name, email: email, password: password)
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    LoginView()
        .environment(environment.session)
}
