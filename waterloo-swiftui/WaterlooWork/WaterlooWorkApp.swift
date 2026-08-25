import SwiftUI
import Foundation

private enum Config {
    static let base = URL(string: "https://drfcchmwqxxpngpdvskg.supabase.co")!
    static let key = "sb_publishable_bXyuWwukxjPQzvhxvRgsCg_gU-ClKef"
}

struct AuthResponse: Decodable {
    let accessToken: String
    let user: AuthUser
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", user }
}

struct AuthUser: Decodable {
    let id: String
    let email: String?
}

struct AppProfile: Decodable, Identifiable {
    let id: String
    let fullName: String?
    let role: String
    let isActive: Bool?
    enum CodingKeys: String, CodingKey {
        case id, role
        case fullName = "full_name"
        case isActive = "is_active"
    }
}

struct Job: Decodable, Identifiable {
    let id: String
    let title: String
    let area: String?
    let category: String?
    let status: String?
    let brief: String?
    let customerName: String?
    let customerEmail: String?
    let customerPhone: String?
    let serviceAddress: String?
    let managerNotes: String?
    let scheduledStart: String?
    let hourlyRate: Double?
    let estimatedHours: Double?
    enum CodingKeys: String, CodingKey {
        case id, title, area, category, status, brief
        case customerName = "customer_name"
        case customerEmail = "customer_email"
        case customerPhone = "customer_phone"
        case serviceAddress = "service_address"
        case managerNotes = "manager_notes"
        case scheduledStart = "scheduled_start"
        case hourlyRate = "hourly_rate"
        case estimatedHours = "estimated_hours"
    }
}

struct JobBroadcast: Decodable, Identifiable {
    var id: String { jobId }
    let jobId: String
    let title: String
    let area: String?
    let category: String?
    let brief: String?
    let hourlyRate: Double
    let estimatedHours: Double?
    let scheduledStart: String?
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case title, area, category, brief
        case hourlyRate = "hourly_rate"
        case estimatedHours = "estimated_hours"
        case scheduledStart = "scheduled_start"
    }
}

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

actor SupabaseClient {
    static let shared = SupabaseClient()
    private let decoder = JSONDecoder()

    private func call(_ path: String, method: String = "GET", token: String? = nil, body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Config.base) else { throw APIError.message("Invalid URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(Config.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("Invalid server response") }
        guard (200...299).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["message"] as? String ?? object?["error_description"] as? String ?? object?["error"] as? String ?? "Request failed (\(http.statusCode))"
            throw APIError.message(message)
        }
        return data
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        let data = try await call("/auth/v1/token?grant_type=password", method: "POST", body: ["email": email, "password": password])
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func currentUser(token: String) async throws -> AuthUser {
        let data = try await call("/auth/v1/user", token: token)
        return try decoder.decode(AuthUser.self, from: data)
    }

    func profile(userID: String, token: String) async throws -> AppProfile {
        let data = try await call("/rest/v1/app_profiles?id=eq.\(userID)&select=id,full_name,role,is_active", token: token)
        let rows = try decoder.decode([AppProfile].self, from: data)
        guard let profile = rows.first else { throw APIError.message("No Manager/Worker profile is assigned to this account.") }
        guard profile.isActive != false else { throw APIError.message("This account is inactive.") }
        return profile
    }

    func jobs(token: String) async throws -> [Job] {
        let data = try await call("/rest/v1/jobs?select=*&order=created_at.desc", token: token)
        return try decoder.decode([Job].self, from: data)
    }

    func finalize(jobID: String, brief: String, rate: Double, hours: Double?, token: String) async throws -> Int? {
        var patch: [String: Any] = [
            "brief": brief,
            "hourly_rate": rate,
            "status": "finalized",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        patch["estimated_hours"] = hours ?? NSNull()
        _ = try await call("/rest/v1/jobs?id=eq.\(jobID)", method: "PATCH", token: token, body: patch, prefer: "return=minimal")
        let data = try await call("/rest/v1/rpc/finalize_job_and_send_to_workers", method: "POST", token: token, body: ["p_job_id": jobID])
        if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (value["sent_to_workers"] as? NSNumber)?.intValue
        }
        if let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = values.first {
            return (first["sent_to_workers"] as? NSNumber)?.intValue
        }
        return nil
    }

    func broadcasts(token: String) async throws -> [JobBroadcast] {
        let data = try await call("/rest/v1/job_broadcasts?status=eq.open&select=*&order=created_at.desc", token: token)
        return try decoder.decode([JobBroadcast].self, from: data)
    }

    func respond(jobID: String, response: String, token: String) async throws {
        _ = try await call("/rest/v1/rpc/respond_to_job_offer", method: "POST", token: token, body: ["p_job_id": jobID, "p_response": response])
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var token: String?
    @Published var user: AuthUser?
    @Published var profile: AppProfile?
    @Published var loading = true
    @Published var error: String?

    init() { token = UserDefaults.standard.string(forKey: "waterloo.accessToken") }

    func restore() async {
        defer { loading = false }
        guard let token else { return }
        do {
            let user = try await SupabaseClient.shared.currentUser(token: token)
            let profile = try await SupabaseClient.shared.profile(userID: user.id, token: token)
            self.user = user
            self.profile = profile
        } catch { signOut() }
    }

    func signIn(email: String, password: String) async {
        error = nil
        do {
            let auth = try await SupabaseClient.shared.signIn(email: email, password: password)
            let profile = try await SupabaseClient.shared.profile(userID: auth.user.id, token: auth.accessToken)
            UserDefaults.standard.set(auth.accessToken, forKey: "waterloo.accessToken")
            token = auth.accessToken
            user = auth.user
            self.profile = profile
        } catch { self.error = error.localizedDescription }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: "waterloo.accessToken")
        token = nil
        user = nil
        profile = nil
    }
}

@main
struct WaterlooWorkApp: App {
    @StateObject private var session = SessionStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if session.loading {
                    ProgressView("Loading Waterloo Work…")
                } else if session.token == nil || session.profile == nil {
                    LoginView()
                } else if session.profile?.role.lowercased() == "manager" {
                    ManagerJobsView()
                } else {
                    WorkerJobsView()
                }
            }
            .environmentObject(session)
            .task { if session.loading { await session.restore() } }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Waterloo Work").font(.largeTitle.bold())
                    Text("Manager & Worker").foregroundStyle(.secondary)
                }
                Section("Sign in") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                    if let error = session.error { Text(error).foregroundStyle(.red) }
                    Button {
                        submitting = true
                        Task {
                            await session.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                            submitting = false
                        }
                    } label: {
                        HStack { Spacer(); if submitting { ProgressView() } else { Text("Sign in").fontWeight(.semibold) }; Spacer() }
                    }
                    .disabled(email.isEmpty || password.isEmpty || submitting)
                }
            }
            .navigationTitle("Waterloo Work")
        }
    }
}

struct ManagerJobsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var jobs: [Job] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(jobs) { job in
                    NavigationLink {
                        ManagerJobDetailView(job: job) { await load() }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.title).font(.headline)
                            Text([job.area, job.category].compactMap { $0 }.joined(separator: " • ")).foregroundStyle(.secondary)
                            HStack {
                                Text(job.status?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown")
                                Spacer()
                                if let rate = job.hourlyRate { Text(rate, format: .currency(code: "CAD")).fontWeight(.semibold) }
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            }
            .overlay { if loading && jobs.isEmpty { ProgressView() } }
            .navigationTitle("Manager Jobs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Sign out") { session.signOut() } }
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
            }
            .refreshable { await load() }
            .task { if jobs.isEmpty { await load() } }
        }
    }

    private func load() async {
        guard let token = session.token else { return }
        loading = true; error = nil
        do { jobs = try await SupabaseClient.shared.jobs(token: token) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct ManagerJobDetailView: View {
    @EnvironmentObject private var session: SessionStore
    let job: Job
    let onChanged: () async -> Void
    @State private var brief: String
    @State private var rate: String
    @State private var hours: String
    @State private var sending = false
    @State private var result: String?

    init(job: Job, onChanged: @escaping () async -> Void) {
        self.job = job; self.onChanged = onChanged
        _brief = State(initialValue: job.brief ?? "")
        _rate = State(initialValue: job.hourlyRate.map { String(format: "%.2f", $0) } ?? "")
        _hours = State(initialValue: job.estimatedHours.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        Form {
            Section("Job") {
                Text(job.title).font(.headline)
                LabeledContent("Area", value: job.area ?? "Not provided")
                LabeledContent("Category", value: job.category ?? "General")
            }
            Section("Customer — manager only") {
                LabeledContent("Name", value: job.customerName ?? "Not provided")
                LabeledContent("Email", value: job.customerEmail ?? "Not provided")
                LabeledContent("Phone", value: job.customerPhone ?? "Not provided")
                LabeledContent("Address", value: job.serviceAddress ?? "Not provided")
            }
            Section("Worker-facing brief") {
                TextEditor(text: $brief).frame(minHeight: 130)
                TextField("Hourly rate (CAD)", text: $rate).keyboardType(.decimalPad)
                TextField("Estimated hours", text: $hours).keyboardType(.decimalPad)
            }
            if let notes = job.managerNotes, !notes.isEmpty { Section("Manager notes") { Text(notes) } }
            if let result { Section { Text(result).foregroundStyle(.secondary) } }
            Section {
                Button {
                    guard let token = session.token, let value = Double(rate), value > 0 else { return }
                    sending = true
                    Task {
                        do {
                            let count = try await SupabaseClient.shared.finalize(jobID: job.id, brief: brief.trimmingCharacters(in: .whitespacesAndNewlines), rate: value, hours: hours.isEmpty ? nil : Double(hours), token: token)
                            result = count.map { "Sent to \($0) eligible worker(s)." } ?? "Job finalized and sent."
                            await onChanged()
                        } catch { result = error.localizedDescription }
                        sending = false
                    }
                } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Label("Finalize & Send to Workers", systemImage: "paperplane.fill") }; Spacer() }
                }
                .disabled(sending || brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(rate) == nil)
            }
        }
        .navigationTitle("Review Job")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkerJobsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var jobs: [JobBroadcast] = []
    @State private var loading = false
    @State private var error: String?
    @State private var acting: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(job.title).font(.headline)
                        Text([job.area, job.category].compactMap { $0 }.joined(separator: " • ")).foregroundStyle(.secondary)
                        Text(job.hourlyRate, format: .currency(code: "CAD")).font(.title2.bold()).foregroundStyle(.green)
                        if let hours = job.estimatedHours { Text("\(hours, specifier: "%.1f") estimated hours").font(.subheadline) }
                        if let brief = job.brief { Text(brief) }
                        HStack {
                            Button("Accept") { respond(job, "accepted") }.buttonStyle(.borderedProminent)
                            Button("Decline", role: .destructive) { respond(job, "declined") }.buttonStyle(.bordered)
                        }.disabled(acting == job.jobId)
                    }.padding(.vertical, 6)
                }
            }
            .overlay { if loading && jobs.isEmpty { ProgressView() } }
            .navigationTitle("Available Jobs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Sign out") { session.signOut() } }
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
            }
            .refreshable { await load() }
            .task { if jobs.isEmpty { await load() } }
        }
    }

    private func load() async {
        guard let token = session.token else { return }
        loading = true; error = nil
        do { jobs = try await SupabaseClient.shared.broadcasts(token: token) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func respond(_ job: JobBroadcast, _ response: String) {
        guard let token = session.token else { return }
        acting = job.jobId
        Task {
            do { try await SupabaseClient.shared.respond(jobID: job.jobId, response: response, token: token); await load() }
            catch { self.error = error.localizedDescription }
            acting = nil
        }
    }
}
