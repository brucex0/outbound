package com.plainstride.outbound

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.network.*
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class RewardsUiState(val status: RewardsStatusDto? = null, val loading: Boolean = true, val working: Boolean = false, val message: Int? = null)

@HiltViewModel
class RewardsViewModel @Inject constructor(
    private val api: RewardsApiService,
    private val tokens: AccessTokenProvider,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableState = MutableStateFlow(RewardsUiState())
    val state: StateFlow<RewardsUiState> = mutableState

    init { analytics.record(AnalyticsEvent("rewards_center_opened")); refresh() }

    fun refresh() = viewModelScope.launch {
        mutableState.value = mutableState.value.copy(loading = true)
        val token = tokens.validAccessToken()
        val result = token?.let { runCatching { api.status("Bearer $it") }.getOrNull() }
        mutableState.value = if (result?.isSuccessful == true) RewardsUiState(status = result.body(), loading = false)
        else RewardsUiState(loading = false, message = R.string.rewards_load_failed)
    }

    fun redeem(code: String, invitation: Boolean) = viewModelScope.launch {
        if (code.isBlank()) return@launch
        mutableState.value = mutableState.value.copy(working = true, message = null)
        val token = tokens.validAccessToken()
        val result = token?.let {
            runCatching {
                if (invitation) api.claimInvitation("Bearer $it", RewardCodeRequestDto(code.trim()))
                else api.redeemEntitlement("Bearer $it", RewardCodeRequestDto(code.trim()))
            }.getOrNull()
        }
        val success = result?.isSuccessful == true
        analytics.record(AnalyticsEvent("reward_code_redeemed", mapOf(
            AnalyticsProperty.SourceType to if (invitation) "referral" else "contribution",
            AnalyticsProperty.Result to if (success) "success" else "failure",
        )))
        mutableState.value = mutableState.value.copy(working = false, message = if (success) R.string.rewards_redeemed else R.string.rewards_redeem_failed)
        if (success) refresh()
    }

    fun shared() = analytics.record(AnalyticsEvent("referral_code_shared", mapOf(AnalyticsProperty.SourceType to "rewards_center")))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun RewardsRoute(onBack: () -> Unit, viewModel: RewardsViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var invitationCode by remember { mutableStateOf("") }
    var entitlementCode by remember { mutableStateOf("") }
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.rewards_title)) }, navigationIcon = {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rewards_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(stringResource(R.string.rewards_plus), style = MaterialTheme.typography.titleMedium) }
            items(capabilities) { capability ->
                val allowed = state.status?.entitlements?.firstOrNull { it.capability == capability.first }?.allowed == true
                ListItem(
                    headlineContent = { Text(stringResource(capability.second)) },
                    supportingContent = { Text(stringResource(capability.third)) },
                    trailingContent = { Icon(if (allowed) Icons.Outlined.CheckCircle else Icons.Outlined.Lock, null, tint = if (allowed) MaterialTheme.colorScheme.primary else LocalContentColor.current) },
                )
            }
            item { Text(stringResource(R.string.rewards_free_fallback), style = MaterialTheme.typography.bodySmall) }
            state.status?.referral?.let { referral ->
                item { HorizontalDivider(); Text(stringResource(R.string.rewards_invite), style = MaterialTheme.typography.titleMedium) }
                item { ListItem(headlineContent = { Text(stringResource(R.string.rewards_your_code)) }, supportingContent = { Text(referral.code) }) }
                item { Button(onClick = {
                    viewModel.shared()
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"; putExtra(Intent.EXTRA_TEXT, context.getString(R.string.rewards_share_message, referral.shareURL))
                    }, null))
                }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.rewards_share_invitation)) } }
                item { Text(stringResource(R.string.rewards_invite_counts, referral.qualifiedCount, referral.pendingCount)) }
            }
            item { HorizontalDivider(); Text(stringResource(R.string.rewards_redeem), style = MaterialTheme.typography.titleMedium) }
            if (state.status?.referral?.claimStatus == null) {
                item { OutlinedTextField(invitationCode, { invitationCode = it.take(64) }, label = { Text(stringResource(R.string.rewards_invitation_code)) }, modifier = Modifier.fillMaxWidth(), singleLine = true) }
                item { Button({ viewModel.redeem(invitationCode, true); invitationCode = "" }, Modifier.fillMaxWidth(), enabled = !state.working && invitationCode.isNotBlank()) { Text(stringResource(R.string.rewards_claim_invitation)) } }
            }
            item { OutlinedTextField(entitlementCode, { entitlementCode = it.take(64) }, label = { Text(stringResource(R.string.rewards_entitlement_code)) }, modifier = Modifier.fillMaxWidth(), singleLine = true) }
            item { Button({ viewModel.redeem(entitlementCode, false); entitlementCode = "" }, Modifier.fillMaxWidth(), enabled = !state.working && entitlementCode.isNotBlank()) { Text(stringResource(R.string.rewards_redeem_reward)) } }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            state.message?.let { message -> item { Text(stringResource(message), color = MaterialTheme.colorScheme.secondary) } }
        }
    }
}

private val capabilities = listOf(
    Triple("ai_planning_dynamic", R.string.rewards_ai_planning, R.string.rewards_ai_planning_detail),
    Triple("live_coach_dynamic", R.string.rewards_live_coach, R.string.rewards_live_coach_detail),
    Triple("live_cheer_voice", R.string.rewards_voice_cheers, R.string.rewards_voice_cheers_detail),
)
