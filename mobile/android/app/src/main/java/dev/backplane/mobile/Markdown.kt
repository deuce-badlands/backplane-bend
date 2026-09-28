package dev.backplane.mobile

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

// Draws the markdown blocks Md.render made (p, h3-h5, ul/li, pre, code,
// strong) with native text styles.

fun plain(bs: List<Block>): String = buildString {
    for (b in bs) when (b) {
        is Block.Txt -> append(b.text)
        is Block.El -> append(plain(b.kids))
    }
}

@Composable
private fun inline(bs: List<Block>): AnnotatedString {
    val code = MaterialTheme.colorScheme.surfaceVariant
    fun AnnotatedString.Builder.go(xs: List<Block>) {
        for (b in xs) when (b) {
            is Block.Txt -> append(b.text)
            is Block.El -> when (b.tag) {
                "code" -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = code)) { go(b.kids) }
                "strong" -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { go(b.kids) }
                else -> go(b.kids)
            }
        }
    }
    return buildAnnotatedString { go(bs) }
}

@Composable
fun Markdown(blocks: List<Block>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (b in blocks) MdBlock(b)
    }
}

@Composable
private fun MdBlock(b: Block) {
    val t = MaterialTheme.typography
    when (b) {
        is Block.Txt -> Text(b.text, style = t.bodyLarge)
        is Block.El -> when (b.tag) {
            "p" -> Text(inline(b.kids), style = t.bodyLarge)
            "h3" -> Text(inline(b.kids), style = t.titleLarge)
            "h4" -> Text(inline(b.kids), style = t.titleMedium)
            "h5" -> Text(inline(b.kids), style = t.titleSmall)
            "ul" -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (li in b.kids) if (li is Block.El) Row {
                    Text("•  ", style = t.bodyLarge)
                    Text(inline(li.kids), style = t.bodyLarge)
                }
            }
            "pre" -> Surface(color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                Text(plain(b.kids), style = t.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    softWrap = false,
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(12.dp))
            }
            // a table (Md.table): the header's cells bold over a rule, each
            // column as wide as its widest cell, sideways when wider
            "table" -> {
                val rows = b.kids.filterIsInstance<Block.El>().map { tr -> tr.kids.filterIsInstance<Block.El>() }
                val n = rows.maxOfOrNull { it.size } ?: 0
                val widths = (0 until n).map { i -> rows.maxOf { r -> r.getOrNull(i)?.let { plain(it.kids).length } ?: 0 } }
                Column(Modifier.horizontalScroll(rememberScrollState())) {
                    rows.forEachIndexed { ri, r ->
                        Row {
                            r.forEachIndexed { i, c ->
                                Text(inline(c.kids), style = if (c.tag == "th") t.bodyMedium.copy(fontWeight = FontWeight.SemiBold) else t.bodyMedium,
                                    modifier = Modifier.width((widths[i].coerceIn(3, 40) * 8 + 16).dp).padding(horizontal = 8.dp, vertical = 4.dp))
                            }
                        }
                        if (ri == 0 && r.any { it.tag == "th" }) HorizontalDivider()
                    }
                }
            }
            // the web page's copy button: long-press the message instead
            "button" -> Unit
            else -> for (k in b.kids) MdBlock(k)
        }
    }
}
