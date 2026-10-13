package com.plainstride.outbound.core.model.activity

import kotlinx.serialization.Serializable

@Serializable data class GroupActivityPerson(val id: String, val displayName: String, val avatarUrl: String? = null)
@Serializable data class GroupActivityParticipant(val person: GroupActivityPerson, val status: String = "going", val outcome: String? = null, val attendanceMode: String? = null, val startedAt: String? = null, val isRecording: Boolean = false)
@Serializable data class GroupActivityGroup(val id: String, val name: String)
@Serializable data class GroupActivityDetail(val id: String, val title: String, val group: GroupActivityGroup? = null, val participants: List<GroupActivityParticipant> = emptyList()) {
    fun attribution(accountId: String) = GroupActivityAttribution(id, title, group?.name,
        participants.filter { it.startedAt != null && it.person.id != accountId }.map { GroupActivityCompanion(it.person, it.attendanceMode) })
}
@Serializable data class GroupActivityCompanion(val person: GroupActivityPerson, val attendanceMode: String? = null)
@Serializable data class GroupActivityAttribution(val id: String? = null, val title: String? = null, val groupName: String? = null, val participants: List<GroupActivityCompanion> = emptyList())
