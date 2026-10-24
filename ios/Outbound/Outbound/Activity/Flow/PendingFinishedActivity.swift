import UIKit

struct PendingFinishedActivity: Identifiable {
    let id: UUID
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
    let guidanceReport: LiveGuidanceSessionReport

    init(
        id: UUID = UUID(),
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection,
        recognitionPreviews: [RecognitionPreview],
        guidanceReport: LiveGuidanceSessionReport
    ) {
        self.id = id
        self.summary = summary
        self.photos = photos
        self.reflection = reflection
        self.recognitionPreviews = recognitionPreviews
        self.guidanceReport = guidanceReport
    }
}
