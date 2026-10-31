package com.plainstride.outbound

import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.feature.social.*
import com.plainstride.outbound.feature.community.CommunityRouteRepository
import com.plainstride.outbound.core.data.ActivityRepository

    @EntryPoint @InstallIn(SingletonComponent::class)
    interface NavigationFixtureDependencies {
        fun session(): SessionCoordinator
        fun database(): PlainstrideDatabase
        fun social(): SocialRepository
        fun details(): SocialDestinationCache
        fun routes(): CommunityRouteRepository
        fun activities(): ActivityRepository
    }
