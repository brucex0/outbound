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
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
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
import com.plainstride.outbound.subscriptions.RevenueCatCoordinator
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.models.StoreTransaction
import com.revenuecat.purchases.ui.revenuecatui.ExperimentalPreviewRevenueCatUIPurchasesAPI
import com.revenuecat.purchases.ui.revenuecatui.PaywallDialog
import com.revenuecat.purchases.ui.revenuecatui.PaywallDialogOptions
import com.revenuecat.purchases.ui.revenuecatui.PaywallListener
import com.revenuecat.purchases.ui.revenuecatui.customercenter.CustomerCenter

data class RewardsUiState(
    val status: RewardsStatusDto? = null,
    val loading: Boolean = true,
    val working: Boolean = false,
    val subscriptionAvailable: Boolean = false,
    val subscriptionActive: Boolean = false,
    val message: Int? = null,
)

@HiltViewModel
class RewardsViewModel @Inject constructor(
    private val api: RewardsApiService,
    private val tokens: AccessTokenProvider,
    private val analytics: ProductAnalytics,
    revenueCat: RevenueCatCoordinator,
) : ViewModel() {
    private val mutableState = MutableStateFlow(RewardsUiState())
    val state: StateFlow<RewardsUiState> = mutableState

    init {
        viewModelScope.launch {
            revenueCat.ready.collect { ready -> mutableState.value = mutableState.value.copy(subscriptionAvailable = ready) }
        }
        viewModelScope.launch {
            revenueCat.hasProEntitlement.collect { active -> mutableState.value = mutableState.value.copy(subscriptionActive = active) }
        }
        refresh()
    }

    fun rewardsCenterOpened() = analytics.record(AnalyticsEvent("rewards_center_opened"))

    fun refresh() = viewModelScope.launch {
        mutableState.value = mutableState.value.copy(loading = true)
        val token = tokens.validAccessToken()
        val result = token?.let { runCatching { api.status("Bearer $it") }.getOrNull() }
        mutableState.value = if (result?.isSuccessful == true) mutableState.value.copy(status = result.body(), loading = false)
        else mutableState.value.copy(loading = false, message = R.string.rewards_load_failed)
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

    fun shared(source: String, foundingMember: Boolean) = analytics.record(
        AnalyticsEvent("referral_code_shared", mapOf(
            AnalyticsProperty.SourceType to source,
            AnalyticsProperty.SelectionType to if (foundingMember) "founding" else "reward_eligible",
        )),
    )

    fun paywallOpened(source: String) = analytics.record(AnalyticsEvent("subscription_paywall_opened", mapOf(AnalyticsProperty.EntrySource to source)))

    fun customerCenterOpened(source: String) = analytics.record(AnalyticsEvent("subscription_customer_center_opened", mapOf(AnalyticsProperty.EntrySource to source)))

    fun reconcileSubscription(source: String) = viewModelScope.launch {
        mutableState.value = mutableState.value.copy(working = true, message = null)
        val token = tokens.validAccessToken()
        val response = token?.let { runCatching { api.reconcileSubscription("Bearer $it") }.getOrNull() }
        val success = response?.isSuccessful == true
        analytics.record(AnalyticsEvent("subscription_reconciled", mapOf(
            AnalyticsProperty.SourceType to source,
            AnalyticsProperty.Result to if (success) "success" else "failure",
        )))
        mutableState.value = mutableState.value.copy(
            working = false,
            message = if (success) R.string.rewards_subscription_synced else R.string.rewards_subscription_sync_failed,
        )
        if (success) refresh()
    }

    fun clearMessage() { mutableState.value = mutableState.value.copy(message = null) }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalPreviewRevenueCatUIPurchasesAPI::class)
@Composable fun PlusRoute(
    onBack: () -> Unit,
    entrySource: String = "settings",
    viewModel: RewardsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var showPaywall by remember { mutableStateOf(false) }
    var showCustomerCenter by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    state.message?.let { message ->
        LaunchedEffect(message) {
            snackbar.showSnackbar(context.getString(message))
            viewModel.clearMessage()
        }
    }
    if (showPaywall) {
        PaywallDialog(
            PaywallDialogOptions.Builder()
                .setDismissRequest { showPaywall = false }
                .setListener(object : PaywallListener {
                    override fun onPurchaseCompleted(customerInfo: CustomerInfo, storeTransaction: StoreTransaction) {
                        showPaywall = false
                        viewModel.reconcileSubscription("purchase")
                    }
                    override fun onRestoreCompleted(customerInfo: CustomerInfo) {
                        showPaywall = false
                        viewModel.reconcileSubscription("restore")
                    }
                })
                .build(),
        )
    }
    if (showCustomerCenter) {
        CustomerCenter(
            modifier = Modifier.fillMaxSize(),
            onDismiss = {
                showCustomerCenter = false
                viewModel.reconcileSubscription("customer_center")
            },
        )
        return
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, topBar = { TopAppBar(title = { Text(stringResource(R.string.rewards_plus)) }, navigationIcon = {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rewards_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.rewards_plus), style = MaterialTheme.typography.headlineSmall)
                    Text(stringResource(R.string.rewards_plus_tagline), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(capabilities) { capability ->
                val allowed = state.status?.entitlements?.firstOrNull { it.capability == capability.first }?.allowed == true
                ListItem(
                    headlineContent = { Text(stringResource(capability.second)) },
                    supportingContent = { Text(stringResource(capability.third)) },
                    trailingContent = { Icon(if (allowed) Icons.Outlined.CheckCircle else Icons.Outlined.Lock, null, tint = if (allowed) MaterialTheme.colorScheme.primary else LocalContentColor.current) },
                )
            }
            item { Text(stringResource(R.string.rewards_free_fallback), style = MaterialTheme.typography.bodySmall) }
            if (state.subscriptionAvailable) {
                item {
                    Button(onClick = {
                        if (state.subscriptionActive) {
                            viewModel.customerCenterOpened(entrySource)
                            showCustomerCenter = true
                        } else {
                            viewModel.paywallOpened(entrySource)
                            showPaywall = true
                        }
                    }, Modifier.fillMaxWidth(), enabled = !state.working) {
                        Text(stringResource(if (state.subscriptionActive) R.string.rewards_manage_subscription else R.string.rewards_view_subscription))
                    }
                }
            }
            item {
                Text(
                    stringResource(if (state.subscriptionActive) R.string.rewards_plus_active_detail else R.string.rewards_plus_options_detail),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun RewardsRoute(
    onBack: () -> Unit,
    onRedeem: () -> Unit,
    viewModel: RewardsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(Unit) { viewModel.rewardsCenterOpened() }
    state.message?.let { message ->
        LaunchedEffect(message) {
            snackbar.showSnackbar(context.getString(message))
            viewModel.clearMessage()
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, topBar = { TopAppBar(title = { Text(stringResource(R.string.rewards_title)) }, navigationIcon = {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rewards_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(stringResource(R.string.rewards_current_rewards), style = MaterialTheme.typography.titleMedium) }
            val rewards = state.status?.entitlements.orEmpty().mapNotNull { entitlement ->
                capabilities.firstOrNull { it.first == entitlement.capability }
                    ?.takeIf { entitlement.allowed && entitlement.sources.any { source -> source != "revenuecat" } }
            }
            if (state.status != null && rewards.isEmpty() && state.status?.bankedRewardDays == 0) {
                item { Text(stringResource(R.string.rewards_no_active_rewards), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            items(rewards, key = { it.first }) { reward ->
                ListItem(
                    headlineContent = { Text(stringResource(reward.second)) },
                    supportingContent = { Text(stringResource(reward.third)) },
                    leadingContent = { Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary) },
                )
            }
            state.status?.bankedRewardDays?.takeIf { it > 0 }?.let { days ->
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.rewards_banked_days, days)) },
                        leadingContent = { Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary) },
                    )
                }
            }
            item { Text(stringResource(R.string.rewards_current_rewards_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            item { HorizontalDivider() }
            item { Button(onRedeem, Modifier.fillMaxWidth()) { Text(stringResource(R.string.rewards_redeem)) } }
            item { Text(stringResource(R.string.rewards_redeem_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun RewardRedemptionRoute(onBack: () -> Unit, viewModel: RewardsViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var invitationCode by remember { mutableStateOf("") }
    var entitlementCode by remember { mutableStateOf("") }
    val snackbar = remember { SnackbarHostState() }
    state.message?.let { message ->
        LaunchedEffect(message) {
            snackbar.showSnackbar(context.getString(message))
            viewModel.clearMessage()
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, topBar = { TopAppBar(title = { Text(stringResource(R.string.rewards_redeem)) }, navigationIcon = {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rewards_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (state.status?.referral?.claimStatus == null) {
                item { OutlinedTextField(invitationCode, { invitationCode = it.take(64) }, label = { Text(stringResource(R.string.rewards_invitation_code)) }, modifier = Modifier.fillMaxWidth(), singleLine = true) }
                item { Button({ viewModel.redeem(invitationCode, true); invitationCode = "" }, Modifier.fillMaxWidth(), enabled = !state.working && invitationCode.isNotBlank()) { Text(stringResource(R.string.rewards_claim_invitation)) } }
            }
            item { OutlinedTextField(entitlementCode, { entitlementCode = it.take(64) }, label = { Text(stringResource(R.string.rewards_entitlement_code)) }, modifier = Modifier.fillMaxWidth(), singleLine = true) }
            item { Button({ viewModel.redeem(entitlementCode, false); entitlementCode = "" }, Modifier.fillMaxWidth(), enabled = !state.working && entitlementCode.isNotBlank()) { Text(stringResource(R.string.rewards_redeem_reward)) } }
            item { Text(stringResource(R.string.rewards_redeem_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun InvitationCodeRoute(onBack: () -> Unit, viewModel: RewardsViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    state.message?.let { message ->
        LaunchedEffect(message) {
            snackbar.showSnackbar(context.getString(message))
            viewModel.clearMessage()
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, topBar = { TopAppBar(title = { Text(stringResource(R.string.rewards_my_invitation_code)) }, navigationIcon = {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.rewards_back)) }
    }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            state.status?.let { status ->
                val referral = status.referral
                val program = status.referralProgram
                item { ListItem(headlineContent = { Text(stringResource(R.string.rewards_your_code)) }, supportingContent = { Text(referral.code) }) }
                item { Button(onClick = {
                    viewModel.shared("me_invitation_code", program.foundingMember)
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(
                            Intent.EXTRA_TEXT,
                            context.getString(
                                if (program.inviterRewardEligible) R.string.rewards_share_message else R.string.rewards_share_message_founding,
                                program.inviteeRewardDays,
                                referral.shareURL,
                            ),
                        )
                    }, null))
                }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.rewards_share_invitation)) } }
                item {
                    Text(stringResource(
                        if (program.foundingMember) R.string.rewards_invite_counts_founding else R.string.rewards_invite_counts,
                        referral.qualifiedCount,
                        referral.pendingCount,
                    ))
                }
                item {
                    Text(
                        if (program.inviterRewardEligible) {
                            stringResource(
                                R.string.rewards_invite_detail,
                                program.inviteeRewardDays,
                                program.inviterRewardDays,
                                program.qualifyingActivitySeconds / 60,
                            )
                        } else {
                            stringResource(
                                R.string.rewards_invite_detail_founding,
                                program.inviteeRewardDays,
                                program.claimWindowDays,
                            )
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        }
    }
}

private val capabilities = listOf(
    Triple("ai_planning_dynamic", R.string.rewards_ai_planning, R.string.rewards_ai_planning_detail),
    Triple("live_coach_dynamic", R.string.rewards_live_coach, R.string.rewards_live_coach_detail),
    Triple("live_cheer_voice", R.string.rewards_voice_cheers, R.string.rewards_voice_cheers_detail),
)
