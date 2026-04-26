import SwiftUI

struct ActivityFeedView: View {
    @State private var posts: [FeedPost] = []

    var body: some View {
        NavigationStack {
            List(posts) { post in
                FeedPostCell(post: post)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .listStyle(.plain)
            .navigationTitle("Outbound")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "bell") }
                }
            }
            .task { await loadFeed() }
        }
    }

    private func loadFeed() async {
        // TODO: fetch from /v1/social/feed/:userId
    }
}

struct FeedPostCell: View {
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(.orange).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.userName).font(.subheadline.bold())
                    Text(post.timeAgo).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let caption = post.caption {
                Text(caption).font(.subheadline)
            }
            if let activity = post.activity {
                ActivityStatBar(activity: activity)
            }
            HStack(spacing: 16) {
                ForEach(["🔥", "👏", "❤️", "💪"], id: \.self) { emoji in
                    Button(emoji) {}
                        .font(.title3)
                }
                Spacer()
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct ActivityStatBar: View {
    let activity: FeedActivity

    var body: some View {
        HStack(spacing: 20) {
            Label(String(format: "%.1f km", activity.distanceKm), systemImage: "figure.run")
            Label(activity.durationStr, systemImage: "timer")
            if let pace = activity.paceStr {
                Label(pace, systemImage: "speedometer")
            }
        }
        .font(.caption.bold())
        .padding(10)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - View models (replaced by real API models later)

struct FeedPost: Identifiable {
    let id: String
    let userName: String
    let timeAgo: String
    let caption: String?
    let activity: FeedActivity?
}

struct FeedActivity {
    let distanceKm: Double
    let durationStr: String
    let paceStr: String?
}
