import CoreData
import Foundation

// MARK: - Core Data Stack
class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "KochiDataModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func save() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save Core Data context: \(error)")
            }
        }
    }
}

// MARK: - Core Data Extensions
extension Recording {
    var wrappedDate: Date {
        date ?? Date()
    }
    
    var wrappedTranscription: String {
        transcription ?? ""
    }
    
    var wrappedFilePath: String {
        filePath ?? ""
    }
    
    var fileURL: URL? {
        guard !wrappedFilePath.isEmpty else { return nil }
        return URL(fileURLWithPath: wrappedFilePath)
    }
}

extension GoalEntity {
    var wrappedText: String {
        get { text ?? "" }
        set { text = newValue }
    }
    
    var wrappedId: UUID {
        id ?? UUID()
    }
}

// MARK: - Core Data Manager
class CoreDataManager {
    private let context = CoreDataStack.shared.context
    
    // MARK: - Recording Management
    func saveRecording(url: URL, duration: TimeInterval, transcription: String) {
        let recording = Recording(context: context)
        recording.id = UUID()
        recording.date = Date()
        recording.duration = duration
        recording.transcription = transcription
        recording.filePath = url.path
        
        CoreDataStack.shared.save()
    }
    
    func fetchRecordings() -> [Recording] {
        let request: NSFetchRequest<Recording> = Recording.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch recordings: \(error)")
            return []
        }
    }
    
    func deleteRecording(_ recording: Recording) {
        // Delete audio file
        if let url = recording.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Delete from Core Data
        context.delete(recording)
        CoreDataStack.shared.save()
    }
    
    // MARK: - Goal Management
    func saveGoal(_ goal: Goal) {
        let goalEntity = GoalEntity(context: context)
        goalEntity.id = goal.id
        goalEntity.text = goal.text
        goalEntity.isCompleted = goal.isCompleted
        goalEntity.createdDate = Date()
        
        CoreDataStack.shared.save()
    }
    
    func fetchGoals() -> [GoalEntity] {
        let request: NSFetchRequest<GoalEntity> = GoalEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdDate", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch goals: \(error)")
            return []
        }
    }
    
    func updateGoal(_ goalEntity: GoalEntity, with goal: Goal) {
        goalEntity.text = goal.text
        goalEntity.isCompleted = goal.isCompleted
        
        CoreDataStack.shared.save()
    }
    
    func deleteGoal(_ goalEntity: GoalEntity) {
        context.delete(goalEntity)
        CoreDataStack.shared.save()
    }
    
    // MARK: - Session Management
    func saveSession(goals: [Goal], notes: String, recordings: [Recording]) {
        let session = Session(context: context)
        session.id = UUID()
        session.date = Date()
        session.notes = notes
        
        // Link recordings to session
        for recording in recordings {
            recording.session = session
        }
        
        CoreDataStack.shared.save()
    }
    
    func fetchSessions() -> [Session] {
        let request: NSFetchRequest<Session> = Session.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.relationshipKeyPathsForPrefetching = ["recordings"]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch sessions: \(error)")
            return []
        }
    }
}