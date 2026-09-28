package dev.backplane.mobile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp

// Settings' rows as the hub describes them (Mob.settings): a section's
// heading (what it has set, and a mark when it needs you), then each row's
// label, note and the control its kind names. The same rows the iPhone,
// iPad and Mac draw; Android keeps them in one list.

private val shape = RoundedCornerShape(4.dp)
private val ok = Color(0xFF34A853)
private val warn = Color(0xFFF29900)

// a section's heading
@Composable
fun SettingsHead(s: SetSection) {
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(s.title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        if (s.attention) Icon(Icons.Filled.Error, "Needs attention", tint = warn, modifier = Modifier.size(16.dp))
        Text(s.summary, style = MaterialTheme.typography.bodySmall, color = if (s.attention) warn else MaterialTheme.colorScheme.outline,
            maxLines = 1, modifier = Modifier.weight(1f))
    }
}

// the rows' sections, in the hub's order (a hub that sends none: the rows' own)
fun settingsSections(st: Settings): List<SetSection> =
    st.sections.ifEmpty { st.rows.map { it.section }.distinct().map { SetSection(it, "", "", false) } }

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingRow(m: AppModel, r: SetRow) {
    // the field's text: a secret's stays here until its button sends it;
    // any other goes to the hub as it is typed, and what was typed here is
    // never overwritten by a screen still echoing it
    var text by remember(r.label) { mutableStateOf(r.field?.text ?: "") }
    var typed by remember(r.label) { mutableStateOf(setOf<String>()) }
    var asking by remember { mutableStateOf<SetButton?>(null) }
    LaunchedEffect(r.field?.text) {
        val t = r.field?.text ?: ""
        if (t !in typed) text = t
        typed = emptySet()
    }

    fun send(b: SetButton) {
        val f = r.field
        when {
            f == null -> m.act(b.action, b.value)
            f.secret && b.needs -> {
                val t = text.trim()
                if (t.isEmpty()) return
                text = ""
                m.act(b.action, t)
            }
            b.needs -> {
                if (text.isBlank()) return
                m.field(f.name, text)
                m.act(b.action, b.value)
            }
            else -> m.act(b.action, b.value)
        }
    }

    fun press(b: SetButton) {
        if (b.danger && b.confirm.isNotEmpty()) asking = b else send(b)
    }

    @Composable
    fun Buttons() {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (b in r.buttons) {
                val idle = b.needs && text.isBlank()
                when {
                    b.danger -> OutlinedButton(onClick = { press(b) }, shape = shape,
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(b.label) }
                    b.on -> Button(onClick = { press(b) }, shape = shape, enabled = !idle) { Text(b.label) }
                    else -> OutlinedButton(onClick = { press(b) }, shape = shape, enabled = !idle) { Text(b.label) }
                }
            }
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(r.label, style = MaterialTheme.typography.bodyLarge)
                if (r.note.isNotEmpty()) Text(r.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
            when (r.kind) {
                "switch" -> {
                    val on = r.buttons.firstOrNull { it.yes }?.on ?: false
                    Switch(checked = on, onCheckedChange = { want -> r.buttons.firstOrNull { it.yes == want }?.let(::press) },
                        modifier = Modifier.semantics { contentDescription = r.label })
                }
                "status" -> if (r.value.isNotEmpty()) Text(r.value, style = MaterialTheme.typography.bodyMedium,
                    color = when (r.tone) { "ok" -> ok; "warn" -> warn; else -> MaterialTheme.colorScheme.outline })
                "stepper" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    r.buttons.getOrNull(0)?.let { b -> OutlinedButton(onClick = { press(b) }, shape = shape) { Text("−") } }
                    Text(r.value, style = MaterialTheme.typography.bodyMedium)
                    r.buttons.getOrNull(1)?.let { b -> OutlinedButton(onClick = { press(b) }, shape = shape) { Text("+") } }
                }
                "menu" -> {
                    var open by remember { mutableStateOf(false) }
                    Column {
                        TextButton(onClick = { open = true }) {
                            Text(r.buttons.firstOrNull { it.on }?.label ?: "Choose")
                            Icon(Icons.Filled.ArrowDropDown, null)
                        }
                        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                            for (b in r.buttons) DropdownMenuItem(text = { Text(b.label) }, onClick = { open = false; press(b) })
                        }
                    }
                }
                else -> Unit
            }
        }
        when (r.kind) {
            "switch", "stepper", "menu" -> Unit
            "field" -> {
                val f = r.field
                if (f != null) OutlinedTextField(
                    value = text,
                    onValueChange = { t ->
                        text = t
                        if (!f.secret) { typed = typed + t; m.field(f.name, t) }
                    },
                    placeholder = { Text(f.hint) },
                    singleLine = true,
                    visualTransformation = if (f.secret) PasswordVisualTransformation() else VisualTransformation.None,
                    modifier = Modifier.fillMaxWidth())
                if (r.buttons.isNotEmpty()) Buttons()
            }
            "status" -> if (r.buttons.isNotEmpty()) Buttons()
            else -> if (r.buttons.isNotEmpty()) Buttons()
        }
        if (r.chips.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (c in r.chips) InputChip(selected = false, onClick = { m.act(c.action, c.value) }, label = { Text(c.label) },
                trailingIcon = { Icon(Icons.Filled.Close, "Remove ${c.label}", modifier = Modifier.size(16.dp)) })
        }
    }

    asking?.let { b ->
        AlertDialog(
            onDismissRequest = { asking = null },
            text = { Text(b.confirm) },
            confirmButton = { TextButton(onClick = { asking = null; send(b) }) { Text(b.label, color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { asking = null }) { Text("Cancel") } })
    }
}
