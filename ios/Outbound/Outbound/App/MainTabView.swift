import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ActivityFeedView()
                .tabItem { Label("Social", systemImage: "person.2.fill") }

            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle.fill") }

            ProfileView()
                .tabItem { Label("Me", systemImage: "person.fill") }
        }
        .tint(.orange)
    }
}
