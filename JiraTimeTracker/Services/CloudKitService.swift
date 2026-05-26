import CloudKit
import WidgetKit

extension Notification.Name {
    static let cloudKitTimerChanged = Notification.Name("cloudKitTimerChanged")
}

actor CloudKitService {
    static let shared = CloudKitService()

    private let container = CKContainer.default()
    private let recordType = "TimerState"
    private let recordID = CKRecord.ID(recordName: "activeTimer")
    private let subscriptionID = "timer-changes"

    private(set) var lastError: String?

    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    func saveTimerState(_ timer: SharedTimerData?) async {
        lastError = nil
        do {
            if let timer = timer {
                let record: CKRecord
                do {
                    record = try await database.record(for: recordID)
                } catch {
                    record = CKRecord(recordType: recordType, recordID: recordID)
                }
                record["issueKey"] = timer.issueKey as CKRecordValue
                record["issueSummary"] = timer.issueSummary as CKRecordValue
                record["startTime"] = timer.startTime as CKRecordValue
                record["isActive"] = 1 as CKRecordValue
                try await database.save(record)
            } else {
                do {
                    let record = try await database.record(for: recordID)
                    record["isActive"] = 0 as CKRecordValue
                    try await database.save(record)
                } catch {
                    // Record doesn't exist, nothing to clear
                }
            }
        } catch {
            lastError = "CloudKit save: \(error.localizedDescription)"
        }
    }

    func fetchTimerState() async -> SharedTimerData? {
        lastError = nil
        do {
            let record = try await database.record(for: recordID)
            guard let isActive = record["isActive"] as? Int64, isActive == 1,
                  let issueKey = record["issueKey"] as? String,
                  let issueSummary = record["issueSummary"] as? String,
                  let startTime = record["startTime"] as? Date else {
                return nil
            }
            return SharedTimerData(issueKey: issueKey, issueSummary: issueSummary, startTime: startTime)
        } catch {
            lastError = "CloudKit fetch: \(error.localizedDescription)"
            return nil
        }
    }

    func setupSubscription() async {
        do {
            let existing = try? await database.subscription(for: subscriptionID)
            if existing != nil { return }

            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )

            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info

            try await database.save(subscription)
        } catch {
            lastError = "CloudKit subscription: \(error.localizedDescription)"
        }
    }

    func syncFromCloud() async {
        let timerData = await fetchTimerState()
        await MainActor.run {
            SharedData.saveTimerState(timerData)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Push Token Storage

    private let pushTokenRecordID = CKRecord.ID(recordName: "pushToStartToken")

    func savePushToStartToken(_ tokenHex: String) async {
        do {
            let record: CKRecord
            do {
                record = try await database.record(for: pushTokenRecordID)
            } catch {
                record = CKRecord(recordType: "PushToken", recordID: pushTokenRecordID)
            }
            record["token"] = tokenHex as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            try await database.save(record)
        } catch {
            lastError = "CloudKit push token save: \(error.localizedDescription)"
        }
    }

    func fetchPushToStartToken() async -> String? {
        do {
            let record = try await database.record(for: pushTokenRecordID)
            return record["token"] as? String
        } catch {
            return nil
        }
    }
}
