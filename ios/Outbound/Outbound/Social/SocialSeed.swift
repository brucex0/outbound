#if OUTBOUND_ENABLE_SOCIAL
import SwiftUI

enum SocialSeed {
    static let maya = SocialPerson(id: "maya", firstName: "Maya", fullName: "Maya Chen", initials: "MC", tint: .orange, isRunning: true)
    static let leo = SocialPerson(id: "leo", firstName: "Leo", fullName: "Leo Park", initials: "LP", tint: .blue, isRunning: true)
    static let zoe = SocialPerson(id: "zoe", firstName: "Zoe", fullName: "Zoe Kim", initials: "ZK", tint: .pink, isRunning: false)
    static let noah = SocialPerson(id: "noah", firstName: "Noah", fullName: "Noah Singh", initials: "NS", tint: .green, isRunning: true)
    static let ava = SocialPerson(id: "ava", firstName: "Ava", fullName: "Ava Brooks", initials: "AB", tint: .purple, isRunning: false)
    static let chen = SocialPerson(id: "chen", firstName: "Chen", fullName: "Chen Li", initials: "CL", tint: .teal, isRunning: true)

    static let people = [maya, leo, zoe, noah, ava, chen]

    static let feedPosts = [
        SocialFeedPost(
            id: "maya-waterfront",
            author: maya,
            context: "Waterfront Loop - 8 min ago",
            caption: "Negative split the last kilometer. Someone take this segment before dinner.",
            activity: SocialActivitySummary(routeName: "Pier Dash", distanceKm: 5.4, duration: "26:12", pace: "4:51 /km"),
            kind: .challenge,
            gradient: [.orange.opacity(0.85), .blue.opacity(0.62)],
            isLive: false,
            cheers: 18,
            comments: 4
        ),
        SocialFeedPost(
            id: "leo-relay",
            author: leo,
            context: "Mission Relay - live now",
            caption: "Holding a conversational pace for anyone who wants to jump in remotely.",
            activity: SocialActivitySummary(routeName: "Mission Grid", distanceKm: 3.1, duration: "15:48", pace: "5:05 /km"),
            kind: .relay,
            gradient: [.green.opacity(0.82), .cyan.opacity(0.55)],
            isLive: true,
            cheers: 11,
            comments: 7
        ),
        SocialFeedPost(
            id: "zoe-hills",
            author: zoe,
            context: "Twin Peaks - yesterday",
            caption: "Hill repeats are better when the group chat is watching.",
            activity: SocialActivitySummary(routeName: "Peak Steps", distanceKm: 6.8, duration: "41:03", pace: "6:02 /km"),
            kind: .run,
            gradient: [.pink.opacity(0.78), .orange.opacity(0.58)],
            isLive: false,
            cheers: 24,
            comments: 6
        )
    ]

    static let clubs = [
        SocialClub(
            id: "sf-dawn",
            name: "SF Dawn Patrol",
            subtitle: "Early runs, quiet streets, coffee after.",
            symbol: "sunrise.fill",
            tint: .orange,
            memberInitials: ["MC", "LP", "ZK", "CL"],
            memberCount: 128,
            nextRun: "Tue 6:30"
        ),
        SocialClub(
            id: "founders",
            name: "Founders 5K",
            subtitle: "Fast lunch loops for builders and designers.",
            symbol: "building.2.fill",
            tint: .blue,
            memberInitials: ["AB", "NS", "LP", "MC"],
            memberCount: 74,
            nextRun: "Today"
        )
    ]

    static let challenges = [
        SocialChallenge(
            id: "seven-day-chain",
            title: "7 Day Chain",
            subtitle: "Four teammates have checked in today.",
            reward: "2 days left",
            progress: 0.71,
            tint: .green
        ),
        SocialChallenge(
            id: "city-segments",
            title: "City Segments",
            subtitle: "Own three short routes before Sunday.",
            reward: "1 segment held",
            progress: 0.33,
            tint: .blue
        )
    ]

    static let rivals = [
        SocialRival(id: "r1", rank: 1, person: maya, weeklyKm: 32.4, delta: "+1.8 km", note: "Won Pier Dash"),
        SocialRival(id: "r2", rank: 2, person: chen, weeklyKm: 30.6, delta: "You", note: "2 runs logged"),
        SocialRival(id: "r3", rank: 3, person: leo, weeklyKm: 28.1, delta: "-2.5 km", note: "Live relay open"),
        SocialRival(id: "r4", rank: 4, person: zoe, weeklyKm: 24.7, delta: "-5.9 km", note: "Climbing week")
    ]
}
#endif
