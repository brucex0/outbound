package run.plainstride.app

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalResources
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import run.plainstride.app.auth.AuthMessage
import run.plainstride.app.auth.AuthOperation
import run.plainstride.app.auth.AuthUiState
import run.plainstride.app.auth.AuthViewModel
import run.plainstride.core.auth.SessionState

private enum class TopLevelDestination(
    val route: String,
    @param:StringRes val label: Int,
    @param:StringRes val headline: Int,
    @param:StringRes val body: Int,
) {
    Social("social", R.string.tab_social, R.string.social_headline, R.string.social_body),
    Today("today", R.string.tab_today, R.string.today_headline, R.string.today_body),
    Me("me", R.string.tab_me, R.string.me_headline, R.string.me_body),
}

@Composable
fun PlainstrideApp(transferCode: String? = null, onTransferCodeConsumed: () -> Unit = {}) {
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val resources = LocalResources.current
    LaunchedEffect(authViewModel) {
        authViewModel.messages.collect { snackbar.showSnackbar(resources.getString(authMessageResource(it))) }
    }
    when (authState.session) {
        SessionState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        SessionState.SignedOut -> SignInScreen(authState, authViewModel, snackbar, transferCode, onTransferCodeConsumed)
        is SessionState.SignedIn, is SessionState.Refreshing -> SignedInApp(authState, authViewModel, snackbar)
    }
}

@Composable
private fun SignedInApp(authState: AuthUiState, authViewModel: AuthViewModel, snackbar: SnackbarHostState) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            NavigationBar {
                TopLevelDestination.entries.forEach { destination ->
                    NavigationBarItem(
                        selected = currentDestination?.hierarchy?.any {
                            it.route == destination.route
                        } == true,
                        onClick = {
                            navController.navigate(destination.route) {
                                popUpTo(TopLevelDestination.Today.route) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Text(stringResource(destination.label).take(1)) },
                        label = { Text(stringResource(destination.label)) },
                    )
                }
            }
        },
    ) { contentPadding ->
        NavHost(
            navController = navController,
            startDestination = TopLevelDestination.Today.route,
            modifier = Modifier.padding(contentPadding),
        ) {
            TopLevelDestination.entries.forEach { destination ->
                composable(destination.route) {
                    FoundationScreen(destination, authState, authViewModel)
                }
            }
        }
    }
    if (authState.confirmDeletion) AlertDialog(
        onDismissRequest = authViewModel::cancelDeletion,
        title = { Text(stringResource(R.string.delete_account_title)) },
        text = { Text(stringResource(R.string.delete_account_body)) },
        confirmButton = { TextButton(onClick = authViewModel::deleteAccount) { Text(stringResource(R.string.delete_account_confirm)) } },
        dismissButton = { TextButton(onClick = authViewModel::cancelDeletion) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun FoundationScreen(destination: TopLevelDestination, authState: AuthUiState, authViewModel: AuthViewModel) {
    Box(
        modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(destination.headline),
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )
            Text(
                text = stringResource(destination.body),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
            )
            if (destination == TopLevelDestination.Me) {
                Button(onClick = authViewModel::linkGoogle, enabled = authState.operation == null) {
                    Text(stringResource(R.string.link_google))
                }
                TextButton(onClick = authViewModel::signOut, enabled = authState.operation == null) {
                    Text(stringResource(R.string.sign_out))
                }
                TextButton(onClick = authViewModel::requestDeletion, enabled = authState.operation == null) {
                    Text(stringResource(R.string.delete_account))
                }
            }
        }
    }
}

@Composable
private fun SignInScreen(
    state: AuthUiState,
    viewModel: AuthViewModel,
    snackbar: SnackbarHostState,
    initialTransferCode: String?,
    onTransferCodeConsumed: () -> Unit,
) {
    var showsTransfer by remember { mutableStateOf(initialTransferCode != null) }
    var transferCode by remember { mutableStateOf(initialTransferCode.orEmpty()) }
    LaunchedEffect(initialTransferCode) {
        if (initialTransferCode != null) {
            showsTransfer = true
            transferCode = initialTransferCode
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(stringResource(R.string.auth_welcome), style = MaterialTheme.typography.headlineLarge, textAlign = TextAlign.Center)
            Text(stringResource(R.string.auth_welcome_body), modifier = Modifier.padding(vertical = 16.dp), textAlign = TextAlign.Center)
            Button(onClick = viewModel::signIn, enabled = state.operation == null) {
                Text(stringResource(if (state.operation == null) R.string.continue_with_google else R.string.signing_in))
            }
            TextButton(onClick = { showsTransfer = !showsTransfer }, enabled = state.operation == null) {
                Text(stringResource(R.string.transfer_existing_account))
            }
            if (showsTransfer) {
                Text(
                    stringResource(R.string.transfer_explanation),
                    modifier = Modifier.padding(top = 12.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )
                OutlinedTextField(
                    value = transferCode,
                    onValueChange = { transferCode = it.take(32) },
                    label = { Text(stringResource(R.string.transfer_code_label)) },
                    singleLine = true,
                    enabled = state.operation == null,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Button(
                    onClick = {
                        viewModel.redeemTransfer(transferCode)
                        onTransferCodeConsumed()
                    },
                    enabled = state.operation == null && transferCode.isNotBlank(),
                    modifier = Modifier.padding(top = 8.dp),
                ) {
                    Text(stringResource(if (state.operation == AuthOperation.Redeem) R.string.transfer_connecting else R.string.transfer_connect))
                }
            }
            Text(stringResource(R.string.auth_terms_notice), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 16.dp), textAlign = TextAlign.Center)
        }
    }
}

@StringRes
private fun authMessageResource(message: AuthMessage) = when (message) {
    AuthMessage.Cancelled -> R.string.auth_cancelled
    AuthMessage.Configuration -> R.string.auth_configuration_error
    AuthMessage.InvalidCredential -> R.string.auth_invalid_credential
    AuthMessage.InvalidTransfer -> R.string.transfer_invalid
    AuthMessage.Conflict -> R.string.auth_identity_conflict
    AuthMessage.Offline -> R.string.auth_offline
    AuthMessage.Unavailable -> R.string.auth_unavailable
    AuthMessage.Generic -> R.string.auth_generic_error
    AuthMessage.Linked -> R.string.auth_linked
    AuthMessage.Transferred -> R.string.transfer_complete
    AuthMessage.SignedOut -> R.string.auth_signed_out
    AuthMessage.Deleted -> R.string.auth_deleted
}
