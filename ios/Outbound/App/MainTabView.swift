import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ActivityFeedView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }

            ProfileView()
                .tabItem { Label("Me", systemImage: "person.fill") }
        }
        .tint(.orange)
    }
}
