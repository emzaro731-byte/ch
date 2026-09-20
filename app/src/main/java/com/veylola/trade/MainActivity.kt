package com.veylola.trade

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.realtime.Realtime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

private val supabase: SupabaseClient = createSupabaseClient(
    supabaseUrl = BuildConfig.SUPABASE_URL,
    supabaseKey = BuildConfig.SUPABASE_PUBLISHABLE_KEY
) {
    install(Auth)
    install(Postgrest)
    install(Realtime)
}

@Serializable
data class TradingSettings(
    val user_id: String,
    val symbol: String = "BTCUSDT",
    val position_limit_usdt: Double = 5.0,
    val stop_loss_pct: Double = 2.0,
    val take_profit_pct: Double = 3.0,
    val paper_mode: Boolean = true
)

@Serializable
data class TradingStatus(
    val user_id: String,
    val symbol: String = "BTCUSDT",
    val mode: String = "PAPER",
    val state: String = "STOPPED",
    val price: Double? = null,
    val action: String = "HOLD",
    val confidence: Double = 0.0,
    val reason: String? = null
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { VeylolaTradeApp() }
    }
}

@Composable
private fun VeylolaTradeApp() {
    var loggedIn by remember { mutableStateOf(supabase.auth.currentSessionOrNull() != null) }

    MaterialTheme {
        if (loggedIn) {
            Dashboard(onLogout = {
                CoroutineScope(Dispatchers.IO).launch {
                    supabase.auth.signOut()
                    loggedIn = false
                }
            })
        } else {
            LoginScreen(onLoggedIn = { loggedIn = true })
        }
    }
}

@Composable
private fun LoginScreen(onLoggedIn: () -> Unit) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("Veylola Trade", style = MaterialTheme.typography.headlineMedium)
        Text("Use the same Supabase account as the website.")
        Spacer(Modifier.height(18.dp))
        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(14.dp))
        Button(
            enabled = !busy,
            onClick = {
                busy = true
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        supabase.auth.signInWith(Email) {
                            this.email = email
                            this.password = password
                        }
                        onLoggedIn()
                    } catch (e: Exception) {
                        message = e.message ?: "Login failed"
                    } finally {
                        busy = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (busy) "Signing in..." else "Sign in")
        }
        Spacer(Modifier.height(8.dp))
        Text(message)
    }
}

@Composable
private fun Dashboard(onLogout: () -> Unit) {
    val userId = supabase.auth.currentUserOrNull()?.id
    var symbol by remember { mutableStateOf("BTCUSDT") }
    var limit by remember { mutableStateOf("5") }
    var stopLoss by remember { mutableStateOf("2") }
    var takeProfit by remember { mutableStateOf("3") }
    var paperMode by remember { mutableStateOf(true) }
    var status by remember { mutableStateOf<TradingStatus?>(null) }
    var message by remember { mutableStateOf("Syncing...") }

    LaunchedEffect(userId) {
        if (userId == null) return@LaunchedEffect
        try {
            supabase.from("trading_bot_settings")
                .selectSingleValueAsFlow(TradingSettings::user_id) {
                    TradingSettings::user_id eq userId
                }
                .collect { row ->
                    symbol = row.symbol
                    limit = row.position_limit_usdt.toString()
                    stopLoss = row.stop_loss_pct.toString()
                    takeProfit = row.take_profit_pct.toString()
                    paperMode = row.paper_mode
                    message = "Settings synced"
                }
        } catch (_: Exception) {
            message = "Settings sync waiting for a saved row"
        }
    }

    LaunchedEffect(userId) {
        if (userId == null) return@LaunchedEffect
        try {
            supabase.from("trading_bot_status")
                .selectSingleValueAsFlow(TradingStatus::user_id) {
                    TradingStatus::user_id eq userId
                }
                .collect { row ->
                    status = row
                }
        } catch (_: Exception) {
            message = "Status sync waiting for bot status"
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Veylola Trade", style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = onLogout) { Text("Log out") }
        }

        Text(message)
        Spacer(Modifier.height(12.dp))

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Trading settings", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(10.dp))

                OutlinedTextField(
                    value = symbol,
                    onValueChange = { symbol = it.uppercase() },
                    label = { Text("Symbol") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = limit,
                    onValueChange = { limit = it },
                    label = { Text("Position limit USDT") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = stopLoss,
                    onValueChange = { stopLoss = it },
                    label = { Text("Stop loss %") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = takeProfit,
                    onValueChange = { takeProfit = it },
                    label = { Text("Take profit %") },
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { paperMode = true }) { Text("Paper") }
                    Button(onClick = { paperMode = false }) { Text("Live") }
                }

                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = {
                        if (userId == null) return@Button
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                supabase.from("trading_bot_settings").upsert(
                                    TradingSettings(
                                        user_id = userId,
                                        symbol = symbol,
                                        position_limit_usdt = limit.toDoubleOrNull() ?: 5.0,
                                        stop_loss_pct = stopLoss.toDoubleOrNull() ?: 2.0,
                                        take_profit_pct = takeProfit.toDoubleOrNull() ?: 3.0,
                                        paper_mode = paperMode
                                    )
                                )
                                message = "Saved to Supabase"
                            } catch (e: Exception) {
                                message = e.message ?: "Save failed"
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Save settings")
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Bot status", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(8.dp))
                Text("Mode: ${status?.mode ?: "--"}")
                Text("State: ${status?.state ?: "--"}")
                Text("Action: ${status?.action ?: "--"}")
                Text("Confidence: ${status?.confidence ?: 0}%")
                Text("Price: ${status?.price ?: "--"}")
                Text("Reason: ${status?.reason ?: "--"}")
            }
        }

        Spacer(Modifier.height(14.dp))
        Text("The Android app uses the Supabase publishable key only. Binance/Groq secrets stay server-side.")
    }
}
