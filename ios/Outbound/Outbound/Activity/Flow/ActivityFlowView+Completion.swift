import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var activityFullscreenSurface: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if let postSaveCelebrationActivity = model.review.postSaveCelebrationActivity {
                Group {
                    if let postSaveStretchContext = model.review.postSaveStretchContext {
                        PostWorkoutStretchView(
                            context: postSaveStretchContext,
                            activity: postSaveCelebrationActivity,
                            voiceProfileID: model.dependencies.guideCatalog.selectedVoice.id,
                            onExit: model.finishPostSaveStretch
                        )
                    } else {
                        PostSaveCelebrationView(activity: postSaveCelebrationActivity, onContinue: model.finishPostSaveCelebration)
                    }
                }
                .zIndex(3)
                .onAppear {
                    guard model.review.lastPostSaveCelebrationExposureID != postSaveCelebrationActivity.id else { return }
                    model.review.lastPostSaveCelebrationExposureID = postSaveCelebrationActivity.id
                    model.track(.init(.featureExposed, properties: [
                        .feature: .string("activity_post_save_celebration")
                    ]))
                }
            }
            else if let pendingActivity = model.review.pendingActivity { postRunSummarySurface(pendingActivity).transition(postRunSummaryTransition).zIndex(1) }
            else {
                liveRecordingSurface
                    .transition(liveRunCompletionTransition)
                    .zIndex(0)
            }
        }
        .animation(model.activityCompletionAnimation, value: model.review.pendingActivity?.id)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    func postRunSummarySurface(_ activity: PendingFinishedActivity) -> some View {
        PostRunSummaryView(
            summary: activity.summary,
            activityType: model.activeIntent?.resolvedActivityType ?? .running,
            weightKilograms: model.dependencies.onboardingStore.latestWeightKilograms,
            photos: activity.photos,
            reflection: activity.reflection,
            recognitionPreviews: activity.recognitionPreviews,
            guidanceReport: activity.guidanceReport,
            workoutID: (model.activeIntent ?? model.setup.plannedIntent)?.id ?? "freestyle-run",
            onGuidanceFeedback: model.handleGuidanceFeedback,
            onDiscardPrompted: {
                var properties = model.outcomeProperties(for: activity.summary)
                properties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(activity.photos.count))
                model.track(.init(.activityDiscardPrompted, properties: properties))
            },
            onSave: { selectedPhotos, reflection in
                await model.savePendingActivity(activity, photos: selectedPhotos, reflection: reflection)
            },
            onDiscard: model.discardPendingActivity
        )
    }

    var liveRunCompletionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.98).combined(with: .opacity)
    }

    var postRunSummaryTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 1.02).combined(with: .opacity)
    }
}
