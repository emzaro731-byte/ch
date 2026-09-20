package com.veylola.trade

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
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

private val VeylolaColors = darkColorScheme(
    primary = Color(0xFF9B8CFF), secondary = Color(0xFF58D8FF),
    background = Color(0xFF060812), surface = Color(0xFF0D1422),
    surfaceVariant = Color(0xFF121C2D)
)

private val supabase: SupabaseClient = createSupabaseClient(
    supabaseUrl = BuildConfig.SUPABASE_URL,
    supabaseKey = BuildConfig.SUPABASE_PUBLISHABLE_KEY
) { install(Auth); install(Postgrest); install(Realtime) }

@Serializable
data class TradingSettings(
    val user_id: String, val symbol: String = "BTCUSDT",
    val position_limit_usdt: Double = 5.0, val stop_loss_pct: Double = 2.0,
    val take_profit_pct: Double = 3.0, val paper_mode: Boolean = true
)

@Serializable
data class TradingStatus(
    val user_id: String, val symbol: String = "BTCUSDT", val mode: String = "PAPER",
    val state: String = "WAITING", val price: Double? = null, val action: String = "HOLD",
    val confidence: Double = 0.0, val reason: String? = null
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
    MaterialTheme(colorScheme = VeylolaColors) {
        if (loggedIn) Dashboard {
            CoroutineScope(Dispatchers.IO).launch { supabase.auth.signOut(); loggedIn = false }
        } else LoginScreen { loggedIn = true }
    }
}

@Composable
private fun LoginScreen(onLoggedIn: () -> Unit) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp), verticalArrangement = Arrangement.Center) {
        Text("Veylola Trade", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text("AI crypto command center", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(email, { email = it }, label = { Text("Email") }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(password, { password = it }, label = { Text("Password") }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(14.dp))
        Button(enabled = !busy, onClick = {
            busy = true
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    supabase.auth.signInWith(Email) { this.email = email; this.password = password }
                    onLoggedIn(); message = "Signed in"
                } catch (e: Exception) { message = e.message ?: "Login failed" }
                finally { busy = false }
            }
        }, modifier = Modifier.fillMaxWidth()) { Text(if (busy) "Signing in…" else "Sign in") }
        Spacer(Modifier.height(8.dp))
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
    var message by remember { mutableStateOf("Connecting…") }

    LaunchedEffect(userId) {
        if (userId == null) return@LaunchedEffect
        try {
            supabase.from("trading_bot_settings").selectSingleValueAsFlow(TradingSettings::user_id) {
                TradingSettings::user_id eq userId
            }.collect { row ->
                symbol = row.symbol; limit = row.position_limit_usdt.toString()
                stopLoss = row.stop_loss_pct.toString(); takeProfit = row.take_profit_pct.toString()
                paperMode = row.paper_mode; message = "Settings synced"
            }
        } catch (_: Exception) { message = "Settings sync waiting" }
    }

    LaunchedEffect(userId) {
        if (userId == null) return@LaunchedEffect
        try {
            supabase.from("trading_bot_status").selectSingleValueAsFlow(TradingStatus::user_id) {
                TradingStatus::user_id eq userId
            }.collect { status = it }
        } catch (_: Exception) { message = "Status sync waiting" }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).background(MaterialTheme.colorScheme.background).padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column {
                Text("Veylola", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("Trade", color = MaterialTheme.colorScheme.primary)
            }
            OutlinedButton(onClick = onLogout) { Text("Log out") }
        }
        Spacer(Modifier.height(16.dp))
        StatusCard(status)
        Spacer(Modifier.height(12.dp))
        RiskCard(symbol, { symbol = it }, limit, { limit = it }, stopLoss, { stopLoss = it },
            takeProfit, { takeProfit = it }, paperMode, { paperMode = true }) {
            if (userId == null) return@RiskCard
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    supabase.from("trading_bot_settings").upsert(
                        TradingSettings(userId, symbol.uppercase(),
                            (limit.toDoubleOrNull() ?: 5.0).coerceAtLeast(.1),
                            (stopLoss.toDoubleOrNull() ?: 2.0).coerceAtLeast(.1),
                            (takeProfit.toDoubleOrNull() ?: 3.0).coerceAtLeast(.1), paperMode)
                    )
                    message = "Saved to Supabase"
                } catch (e: Exception) { message = e.message ?: "Save failed" }
            }
        }
        Spacer(Modifier.height(12.dp))
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(18.dp)) {
                Text("Security", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("✓ Supabase publishable key only")
                Text("✓ Binance/Groq secrets remain server-side")
                Text("✓ Paper trading is the default")
                Text("✓ Live execution is not enabled by this client")
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatusCard(status: TradingStatus?) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text("AI market status", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(status?.symbol ?: "BTCUSDT", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(status?.action ?: "HOLD", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(14.dp))
            Text("Mode: " + (status?.mode ?: "PAPER") + "    State: " + (status?.state ?: "WAITING"))
            Text("Price: " + (status?.price ?: "—"))
            Text("Confidence: " + (status?.confidence ?: 0) + "%")
            Spacer(Modifier.height(6.dp))
            Text(status?.reason ?: "Waiting for bot analysis.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RiskCard(
    symbol: String, onSymbol: (String) -> Unit, limit: String, onLimit: (String) -> Unit,
    stop: String, onStop: (String) -> Unit, take: String, onTake: (String) -> Unit,
    paper: Boolean, onPaper: (Boolean) -> Unit, onSave: () -> Unit
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp)) {
            Text("Risk controls", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("Guarded settings · no profit guarantee", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(symbol, onSymbol, label = { Text("Pair") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(limit, onLimit, label = { Text("Position limit USDT") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(stop, onStop, label = { Text("Stop loss %") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(take, onTake, label = { Text("Take profit %") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column { Text("Paper trading"); Text("Recommended", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Switch(checked = paper, onCheckedChange = { onPaper(true) })
            }
            Spacer(Modifier.height(8.dp))
            Button(onClick = onSave, modifier = Modifier.fillMaxWidth()) { Text("Save & sync") }
        }
    }
}
