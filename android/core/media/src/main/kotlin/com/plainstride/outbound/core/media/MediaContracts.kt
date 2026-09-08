package com.plainstride.outbound.core.media

enum class AudioInterruption { Began, Ended }

interface CoachingAudioPlayer { suspend fun stop() }
