import SwiftUI

// Draws the markdown blocks Md.render made (p, h3-h5, ul/li, pre, table,
// code, strong, a) with native text styles.

private func inline(_ bs: [Block]) -> AttributedString {
    var out = AttributedString()
    for b in bs {
        if let t = b.text {
            out += AttributedString(t)
            continue
        }
        var part = inline(b.kids ?? [])
        switch b.tag {
        case "code":
            part.font = .body.monospaced()
            part.backgroundColor = Color(.secondarySystemFill)
        case "strong":
            part.font = .body.weight(.semibold)
        // a link opens in the browser (Text follows .link on a tap)
        case "a":
            if let h = b.href, let u = URL(string: h) {
                part.link = u
                part.underlineStyle = .single
            }
        default:
            break
        }
        out += part
    }
    return out
}

struct MarkdownView: View {
    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                BlockView(block: b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: Block

    var body: some View {
        if let t = block.text {
            Text(t)
        } else {
            let kids = block.kids ?? []
            switch block.tag {
            case "p": Text(inline(kids))
            case "h3": Text(inline(kids)).font(.title3.bold())
            case "h4": Text(inline(kids)).font(.headline)
            case "h5": Text(inline(kids)).font(.subheadline.bold())
            case "ul":
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(kids.enumerated()), id: \.offset) { _, li in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(inline(li.kids ?? []))
                        }
                    }
                }
            case "pre":
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.plain).font(.callout.monospaced()).padding(12)
                }
                .background(Color.secondaryBackground)
            case "table": TableBlock(rows: kids)
            // the web page's copy button: the message's context menu copies
            case "button": EmptyView()
            default: MarkdownView(blocks: kids)
            }
        }
    }
}

// A markdown table: a header row (th) in bold over a tint, the rows below
// with hairlines between them. A table wider than the column scrolls
// sideways rather than squeezing its cells.
private struct TableBlock: View {
    let rows: [Block]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    let cells = r.kids ?? []
                    let head = cells.first?.tag == "th"
                    if i > 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                            Text(inline(c.kids ?? []))
                                .font(head ? .callout.weight(.semibold) : .callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 60, maxWidth: 320, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                    }
                    .background(head ? Color.secondary.opacity(0.12) : Color.clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)).allowsHitTesting(false))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
