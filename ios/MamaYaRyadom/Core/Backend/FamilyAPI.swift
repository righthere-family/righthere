import Foundation
import Supabase

// MARK: - Errors

enum FamilyAPIError: Error {
    case notConfigured
    case unknownFamily
}

// MARK: - API

struct FamilyAPI: Sendable {
    func snapshot() async throws -> TodaySnapshot {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        let response = try await client.rpc(
            "app_snapshot",
            params: ["p_app_token": AppConfig.familyToken]
        ).execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try decoder.decode(SnapshotPayload?.self, from: response.data) else {
            throw FamilyAPIError.unknownFamily
        }
        SharedStore.cachedSnapshot = response.data
        return payload.model
    }

    func month(year: Int, month: Int, parentId: UUID? = nil) async throws -> MonthPayload {
        try await call(
            "app_month",
            params: MonthParams(
                pAppToken: AppConfig.familyToken,
                pYear: year,
                pMonth: month,
                pParentId: parentId
            )
        )
    }

    func meds(parentId: UUID? = nil) async throws -> [MedInfo] {
        try await call(
            "app_meds",
            params: MedsParams(pAppToken: AppConfig.familyToken, pParentId: parentId)
        )
    }

    func addMed(title: String, times: [String], parentId: UUID? = nil) async throws {
        struct AddResult: Decodable {
            let id: UUID
        }
        let _: AddResult = try await call(
            "app_med_add",
            params: MedAddParams(
                pAppToken: AppConfig.familyToken,
                pTitle: title,
                pTimes: times,
                pParentId: parentId
            )
        )
    }

    func updateMed(id: UUID, title: String, times: [String]) async throws {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        _ = try await client.rpc(
            "app_med_update",
            params: MedUpdateParams(pAppToken: AppConfig.familyToken, pMedId: id, pTitle: title, pTimes: times)
        ).execute()
    }

    func deleteMed(id: UUID) async throws {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        _ = try await client.rpc(
            "app_med_delete",
            params: MedDeleteParams(pAppToken: AppConfig.familyToken, pMedId: id)
        ).execute()
    }

    func updateParent(
        name: String,
        city: String,
        timezone: String,
        checkinTime: String,
        phone: String,
        parentId: UUID? = nil,
        botLanguage: String? = nil
    ) async throws {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        struct Params: Encodable {
            let pAppToken: String
            let pName: String
            let pCity: String
            let pTimezone: String
            let pCheckinTime: String
            let pPhone: String
            let pParentId: UUID?
            let pLang: String?

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pName = "p_name"
                case pCity = "p_city"
                case pTimezone = "p_timezone"
                case pCheckinTime = "p_checkin_time"
                case pPhone = "p_phone"
                case pParentId = "p_parent_id"
                case pLang = "p_lang"
            }
        }
        _ = try await client.rpc(
            "app_update_parent",
            params: Params(
                pAppToken: AppConfig.familyToken,
                pName: name,
                pCity: city,
                pTimezone: timezone,
                pCheckinTime: checkinTime,
                pPhone: phone,
                pParentId: parentId,
                pLang: botLanguage
            )
        ).execute()
    }

    func myFamilyToken() async throws -> String? {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        guard client.auth.currentSession != nil else { return nil }
        struct MyFamily: Decodable {
            let appToken: UUID
        }
        let response = try await client.rpc("my_family").execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(MyFamily?.self, from: response.data)
        return payload?.appToken.uuidString.lowercased()
    }

    func recordSubscription(entitlement: String, product: String, expiresAt: Date?) async throws {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        struct Params: Encodable {
            let pAppToken: String
            let pEntitlement: String
            let pProduct: String
            let pExpiresAt: Date?

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pEntitlement = "p_entitlement"
                case pProduct = "p_product"
                case pExpiresAt = "p_expires_at"
            }
        }
        _ = try await client.rpc(
            "app_set_subscription",
            params: Params(
                pAppToken: AppConfig.familyToken,
                pEntitlement: entitlement,
                pProduct: product,
                pExpiresAt: expiresAt
            )
        ).execute()
    }

    func setPushToken(
        _ token: String,
        environment: String,
        timezone: String,
        language: String
    ) async throws {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        await ensureSession()
        struct Params: Encodable {
            let pAppToken: String
            let pToken: String
            let pEnv: String
            let pTimezone: String
            let pLang: String

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pToken = "p_token"
                case pEnv = "p_env"
                case pTimezone = "p_timezone"
                case pLang = "p_lang"
            }
        }
        _ = try await client.rpc(
            "app_set_push_token",
            params: Params(
                pAppToken: AppConfig.familyToken,
                pToken: token,
                pEnv: environment,
                pTimezone: timezone,
                pLang: language
            )
        ).execute()
    }

    func newInviteCode() async throws -> String {
        struct InvitePayload: Decodable {
            let inviteCode: String
        }
        let payload: InvitePayload = try await call(
            "app_new_invite",
            params: ["p_app_token": AppConfig.familyToken]
        )
        return payload.inviteCode
    }

    func createFamily(
        momName: String,
        momCity: String,
        momTimezone: String,
        checkinTime: String,
        childName: String,
        childGender: String,
        botLanguage: String
    ) async throws -> CreatedFamily {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        if client.auth.currentSession == nil {
            try await client.auth.signInAnonymously()
        }
        let params = CreateFamilyParams(
            pParentName: momName,
            pCity: momCity,
            pTimezone: momTimezone,
            pCheckinTime: checkinTime,
            pChildName: childName,
            pChildGender: childGender,
            pChildTimezone: TimeZone.current.identifier,
            pLang: botLanguage
        )
        let response = try await client.rpc("create_family_with_parent", params: params).execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let created = try decoder.decode(CreatedFamily?.self, from: response.data) else {
            throw FamilyAPIError.unknownFamily
        }
        return created
    }

    func sendPostcard(parentId: UUID, body: String, photoPath: String? = nil) async throws -> Bool {
        try await call(
            "app_send_postcard",
            params: PostcardParams(
                pAppToken: AppConfig.familyToken,
                pParentId: parentId,
                pBody: body,
                pPhotoPath: photoPath
            )
        )
    }

    func uploadPostcardPhoto(_ data: Data) async throws -> String {
        // The worker keeps the photo in KV and hands back a key; it never
        // reaches the database. Base64 through PostgREST stays as the fallback
        // because it is the one transport that has never failed this app —
        // the worker route has stalled from the simulator's network stack
        // before — and the server reads either kind of key on delivery.
        if let key = try? await uploadPhotoToWorker(data) {
            return key
        }
        struct Params: Encodable {
            let pAppToken: String
            let pData: String

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pData = "p_data"
            }
        }
        let blobId: UUID = try await call(
            "app_store_postcard_photo",
            params: Params(pAppToken: AppConfig.familyToken, pData: data.base64EncodedString())
        )
        return blobId.uuidString.lowercased()
    }

    private func uploadPhotoToWorker(_ data: Data) async throws -> String {
        struct Stored: Decodable { let path: String }
        guard let endpoint = URL(string: "\(AppConfig.joinBaseURL)/postcard-photo") else {
            throw FamilyAPIError.notConfigured
        }
        // The fallback below exists because this route has stalled before, and a
        // stall costs the default 60 seconds of spinner before it starts. Ten
        // is long enough for a slow upload on mobile data and short enough that
        // the fallback is a hiccup rather than a wait.
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue(AppConfig.familyToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        // Content-Length is set by URLSession itself for a body it holds in
        // memory — it is one of the reserved headers, and setting it here would
        // be ignored. The worker measures the bytes it actually received
        // anyway, so nothing depends on the header being right.
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FamilyAPIError.unknownFamily
        }
        return try JSONDecoder().decode(Stored.self, from: body).path
    }

    func parentMessages(limit: Int = 100) async throws -> [ParentMessage] {
        struct Params: Encodable {
            let pAppToken: String
            let pLimit: Int

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pLimit = "p_limit"
            }
        }
        return try await call(
            "app_parent_messages",
            params: Params(pAppToken: AppConfig.familyToken, pLimit: limit)
        )
    }

    // Trades the family token for a short-lived signed link to one voice note.
    // The token goes up in a header and stays there; what comes back grants
    // exactly this file and expires in minutes.
    func voicePlaybackURL(fileId: String) async throws -> URL {
        struct Link: Decodable { let url: String }
        guard let endpoint = URL(string: "\(AppConfig.joinBaseURL)/story-voice/link") else {
            throw FamilyAPIError.notConfigured
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(AppConfig.familyToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["file": fileId])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FamilyAPIError.unknownFamily
        }
        guard let link = URL(string: try JSONDecoder().decode(Link.self, from: data).url) else {
            throw FamilyAPIError.unknownFamily
        }
        return link
    }

    func setEveningTime(parentId: UUID, time: String?) async throws -> Bool {
        struct Params: Encodable {
            let pAppToken: String
            let pParentId: UUID
            let pTime: String?

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pParentId = "p_parent_id"
                case pTime = "p_time"
            }
        }
        return try await call(
            "app_set_evening_time",
            params: Params(pAppToken: AppConfig.familyToken, pParentId: parentId, pTime: time)
        )
    }

    func trends(parentId: UUID? = nil) async throws -> TrendsPayload {
        struct Params: Encodable {
            let pAppToken: String
            let pParentId: UUID?

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pParentId = "p_parent_id"
            }
        }
        return try await call(
            "app_trends",
            params: Params(pAppToken: AppConfig.familyToken, pParentId: parentId)
        )
    }

    func setWindow(parentId: UUID, minutes: Int) async throws -> Bool {
        struct Params: Encodable {
            let pAppToken: String
            let pParentId: UUID
            let pMinutes: Int

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pParentId = "p_parent_id"
                case pMinutes = "p_minutes"
            }
        }
        return try await call(
            "app_set_window",
            params: Params(pAppToken: AppConfig.familyToken, pParentId: parentId, pMinutes: minutes)
        )
    }

    func dates() async throws -> [FamilyDate] {
        try await call("app_dates", params: ["p_app_token": AppConfig.familyToken])
    }

    func addDate(title: String, month: Int, day: Int) async throws -> UUID {
        struct Params: Encodable {
            let pAppToken: String
            let pTitle: String
            let pMonth: Int
            let pDay: Int

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pTitle = "p_title"
                case pMonth = "p_month"
                case pDay = "p_day"
            }
        }
        return try await call(
            "app_date_add",
            params: Params(pAppToken: AppConfig.familyToken, pTitle: title, pMonth: month, pDay: day)
        )
    }

    func deleteDate(id: UUID) async throws {
        struct Params: Encodable {
            let pAppToken: String
            let pId: UUID

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pId = "p_id"
            }
        }
        let _: Bool = try await call(
            "app_date_delete",
            params: Params(pAppToken: AppConfig.familyToken, pId: id)
        )
    }

    func stories() async throws -> [FamilyStory] {
        try await call("app_stories", params: ["p_app_token": AppConfig.familyToken])
    }

    // A device that joined via the family link has no auth session of its
    // own — the app works through the family token alone. Everything keyed
    // to auth.uid() (push token, role, leaving) must mint one first.
    private func ensureSession() async {
        guard let client = SupabaseHub.client else { return }
        if client.auth.currentSession == nil {
            try? await client.auth.signInAnonymously()
        }
    }

    func myRole() async throws -> String? {
        await ensureSession()
        return try? await call("my_role", params: ["p_app_token": AppConfig.familyToken])
    }

    func deleteAccount() async throws -> String? {
        await ensureSession()
        return try await call("app_delete_account", params: ["p_app_token": AppConfig.familyToken])
    }

    func familyEntitlement() async throws -> String? {
        try? await call("family_entitlement", params: ["p_app_token": AppConfig.familyToken])
    }

    func addParent(
        name: String,
        kind: String,
        city: String,
        timezone: String,
        checkinTime: String,
        botLanguage: String
    ) async throws -> AddedParent {
        try await call(
            "app_add_parent",
            params: AddParentParams(
                pAppToken: AppConfig.familyToken,
                pDisplayName: name,
                pKind: kind,
                pCity: city,
                pTimezone: timezone,
                pCheckinTime: checkinTime,
                pLang: botLanguage
            )
        )
    }

    func removeParent(id: UUID) async throws -> Bool {
        struct Params: Encodable {
            let pAppToken: String
            let pParentId: UUID

            enum CodingKeys: String, CodingKey {
                case pAppToken = "p_app_token"
                case pParentId = "p_parent_id"
            }
        }
        return try await call(
            "app_remove_parent",
            params: Params(pAppToken: AppConfig.familyToken, pParentId: id)
        )
    }

    private func call<Payload: Decodable>(
        _ function: String,
        params: some Encodable & Sendable
    ) async throws -> Payload {
        guard let client = SupabaseHub.client else { throw FamilyAPIError.notConfigured }
        let response = try await client.rpc(function, params: params).execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try decoder.decode(Payload?.self, from: response.data) else {
            throw FamilyAPIError.unknownFamily
        }
        return payload
    }
}

// MARK: - Params

private struct PostcardParams: Encodable {
    let pAppToken: String
    let pParentId: UUID
    let pBody: String
    let pPhotoPath: String?

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pParentId = "p_parent_id"
        case pBody = "p_body"
        case pPhotoPath = "p_photo_path"
    }
}

private struct AddParentParams: Encodable {
    let pAppToken: String
    let pDisplayName: String
    let pKind: String
    let pCity: String
    let pTimezone: String
    let pCheckinTime: String
    let pLang: String

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pDisplayName = "p_display_name"
        case pKind = "p_kind"
        case pCity = "p_city"
        case pTimezone = "p_timezone"
        case pCheckinTime = "p_checkin_time"
        case pLang = "p_lang"
    }
}

private struct MonthParams: Encodable {
    let pAppToken: String
    let pYear: Int
    let pMonth: Int
    let pParentId: UUID?

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pYear = "p_year"
        case pMonth = "p_month"
        case pParentId = "p_parent_id"
    }
}

private struct MedsParams: Encodable {
    let pAppToken: String
    let pParentId: UUID?

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pParentId = "p_parent_id"
    }
}

private struct CreateFamilyParams: Encodable {
    let pParentName: String
    let pCity: String
    let pTimezone: String
    let pCheckinTime: String
    let pChildName: String
    let pChildGender: String
    let pChildTimezone: String
    let pLang: String

    enum CodingKeys: String, CodingKey {
        case pParentName = "p_parent_name"
        case pCity = "p_city"
        case pTimezone = "p_timezone"
        case pCheckinTime = "p_checkin_time"
        case pChildName = "p_child_name"
        case pChildGender = "p_child_gender"
        case pChildTimezone = "p_child_timezone"
        case pLang = "p_lang"
    }
}

private struct MedAddParams: Encodable {
    let pAppToken: String
    let pTitle: String
    let pTimes: [String]
    let pParentId: UUID?

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pTitle = "p_title"
        case pTimes = "p_times"
        case pParentId = "p_parent_id"
    }
}

private struct MedUpdateParams: Encodable {
    let pAppToken: String
    let pMedId: UUID
    let pTitle: String
    let pTimes: [String]

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pMedId = "p_med_id"
        case pTitle = "p_title"
        case pTimes = "p_times"
    }
}

private struct MedDeleteParams: Encodable {
    let pAppToken: String
    let pMedId: UUID

    enum CodingKeys: String, CodingKey {
        case pAppToken = "p_app_token"
        case pMedId = "p_med_id"
    }
}

// MARK: - Med Info

struct MedInfo: Decodable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let times: [String]
}

// MARK: - Created Family

struct CreatedFamily: Decodable, Sendable {
    let familyId: UUID
    let appToken: UUID
    let parentId: UUID
    let inviteCode: String
}

// MARK: - Payloads

struct AddedParent: Decodable, Sendable {
    let parentId: UUID
    let inviteCode: String
}

struct FamilyDate: Decodable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let month: Int
    let day: Int
}

struct ParentMessage: Decodable, Identifiable, Sendable {
    let id: UUID
    let parentId: UUID
    let kind: String
    let body: String?
    let voiceFileId: String?
    let photoFileId: String?
    let createdAt: Date
}

struct FamilyStory: Decodable, Identifiable, Sendable {
    let id: UUID
    let parentId: UUID
    let question: String
    let answerText: String?
    let voiceFileId: String?
    let answeredAt: Date?

    var hasVoice: Bool { voiceFileId != nil }
}

struct TrendsPayload: Decodable, Sendable {
    let recentAvgMinute: Int?
    let beforeAvgMinute: Int?
    let shiftMinutes: Int?
    let missed30d: Int?

    // convertFromSnakeCase turns "missed_30d" into "missed30D"; explicit keys
    // keep the digit-suffixed field decodable.
    enum CodingKeys: String, CodingKey {
        case recentAvgMinute
        case beforeAvgMinute
        case shiftMinutes
        case missed30d = "missed30D"
    }
}

struct SnapshotPayload: Decodable {
    let parent: ParentPayload
    let status: StatusPayload
    let streak: Int
    let inviteCode: String?
    let meds: MedsPayload?
    let parents: [SnapshotPayload]?
    let evening: EveningPayload?
    let upcomingDate: UpcomingDatePayload?

    struct UpcomingDatePayload: Decodable {
        let title: String
        let daysLeft: Int
    }

    struct EveningPayload: Decodable {
        let status: String
        let at: Date?
    }

    struct MedsPayload: Decodable {
        let taken: Int
        let total: Int
    }

    struct ParentPayload: Decodable {
        let id: UUID
        let kind: String
        let displayName: String
        let city: String?
        let phone: String?
        let timezone: String
        let checkinTime: String
        let windowMin: Int
        let eveningTime: String?
        let lang: String?
    }

    struct StatusPayload: Decodable {
        let state: String
        let at: Date?
        let kind: String?
        let quote: String?
        let deadline: Date?
        let usualBy: Date?
        let until: String?
    }
}

struct MonthPayload: Decodable {
    let today: Int?
    let days: [Day]

    struct Day: Decodable {
        let day: Int
        let mark: String
        let time: String?
        let quote: String?
    }
}

// MARK: - Mapping

extension SnapshotPayload {
    var model: TodaySnapshot {
        // The payload repeats the first parent at the top level, so the tail is
        // everyone else: older builds read the top level and never look here.
        let others = (parents ?? []).dropFirst().map(\.selfModel)
        var model = selfModel.withOthers(others)
        if let upcomingDate {
            model.upcomingDate = TodaySnapshot.UpcomingDate(
                title: upcomingDate.title,
                daysLeft: upcomingDate.daysLeft
            )
        }
        return model
    }

    private var eveningModel: TodaySnapshot.Evening? {
        guard let evening else { return nil }
        return TodaySnapshot.Evening(isOk: evening.status == "ok", at: evening.at)
    }

    private var selfModel: TodaySnapshot {
        TodaySnapshot(
            parent: parentModel,
            status: statusModel,
            streak: streak,
            isWaitingParent: status.state == "waiting_parent",
            inviteCode: inviteCode,
            medsTaken: meds?.taken ?? 0,
            medsTotal: meds?.total ?? 0,
            evening: eveningModel
        )
    }

    private var parentModel: Parent {
        Parent(
            id: parent.id,
            kind: Parent.Kind(rawValue: parent.kind) ?? .mom,
            displayName: parent.displayName,
            cityName: Self.localizedCity(parent.city) ?? Self.city(fromTimezone: parent.timezone),
            phone: parent.phone,
            timezone: parent.timezone,
            checkinTime: parent.checkinTime,
            windowMinutes: parent.windowMin,
            eveningTime: parent.eveningTime,
            botLanguage: parent.lang ?? "ru"
        )
    }

    private var statusModel: DayStatus {
        switch status.state {
        case "ok":
            .ok(at: status.at ?? .now)
        case "not_ok":
            .notOk(
                kind: DayStatus.NotOkKind(rawValue: status.kind ?? "") ?? .unspecified,
                quote: status.quote
            )
        case "reminded":
            .reminded(at: status.at ?? .now, deadline: status.deadline ?? .now)
        case "quiet":
            .quiet(since: status.at)
        case "paused":
            .paused(until: Self.day(status.until) ?? .now, reason: nil)
        default:
            .stillMorning(usualBy: status.usualBy)
        }
    }

    // The stored city is whatever the family typed — usually Cyrillic. The
    // display dictionary is keyed by the name itself, so «Ульяновск» renders
    // as Ulyanovsk in English and "Samara" as Самара in Russian; a city we
    // do not know stays exactly as typed.
    private static func localizedCity(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let key = "city.\(raw.lowercased().replacingOccurrences(of: " ", with: "_"))"
        return L10n.bundle.localizedString(forKey: key, value: raw, table: nil)
    }

    private static func city(fromTimezone timezone: String) -> String {
        let raw = timezone.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? timezone
        let key = "city.\(raw.lowercased().replacingOccurrences(of: " ", with: "_"))"
        let localized = L10n.bundle.localizedString(forKey: key, value: raw, table: nil)
        return localized
    }

    private static func day(_ value: String?) -> Date? {
        guard let value else { return nil }
        return try? Date("\(value)T00:00:00Z", strategy: .iso8601)
    }
}
