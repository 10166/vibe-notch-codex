//
//  MarkdownRenderer.swift
//  ClaudeIsland
//
//  Markdown renderer using swift-markdown for efficient parsing
//

import Markdown
import SwiftUI

// MARK: - Document Cache

/// Caches parsed markdown documents to avoid re-parsing
private final class DocumentCache: @unchecked Sendable {
    static let shared = DocumentCache()
    private var cache: [String: Document] = [:]
    private let lock = NSLock()
    private let maxSize = 100

    func document(for text: String) -> Document {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[text] {
            return cached
        }
        // Enable strikethrough and other extended syntax
        let doc = Document(parsing: text, options: [.parseBlockDirectives, .parseSymbolLinks])
        if cache.count >= maxSize {
            cache.removeAll()
        }
        cache[text] = doc
        return doc
    }
}

// MARK: - Markdown Text View

/// Renders markdown text with inline formatting using swift-markdown
struct MarkdownText: View {
    let text: String
    let baseColor: Color
    let fontSize: CGFloat

    private let document: Document

    init(_ text: String, color: Color = .white.opacity(0.9), fontSize: CGFloat = 13) {
        self.text = text
        self.baseColor = color
        self.fontSize = fontSize
        self.document = DocumentCache.shared.document(for: text)
    }

    var body: some View {
        let children = Array(document.children)
        if children.isEmpty {
            // Fallback for empty parse result
            SwiftUI.Text(text)
                .foregroundColor(baseColor)
                .font(.system(size: fontSize))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    BlockRenderer(markup: child, baseColor: baseColor, fontSize: fontSize)
                }
            }
        }
    }
}

// MARK: - Block Renderer

private struct BlockRenderer: View {
    let markup: Markup
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let paragraph = markup as? Paragraph {
            InlineRenderer(children: Array(paragraph.inlineChildren), baseColor: baseColor, fontSize: fontSize)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if let heading = markup as? Heading {
            headingView(heading)
        } else if let codeBlock = markup as? CodeBlock {
            CodeBlockView(code: codeBlock.code)
        } else if let blockQuote = markup as? BlockQuote {
            blockQuoteView(blockQuote)
        } else if let table = markup as? Markdown.Table {
            MarkdownTableView(table: table, baseColor: baseColor, fontSize: fontSize)
        } else if let list = markup as? UnorderedList {
            unorderedListView(list)
        } else if let list = markup as? OrderedList {
            orderedListView(list)
        } else if markup is ThematicBreak {
            Divider()
                .background(baseColor.opacity(0.3))
                .padding(.vertical, 4)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func headingView(_ heading: Heading) -> some View {
        let text = InlineRenderer(children: Array(heading.inlineChildren), baseColor: baseColor, fontSize: fontSize).asText()
        switch heading.level {
        case 1: text.bold().italic().underline()
        case 2: text.bold()
        default: text.bold().foregroundColor(baseColor.opacity(0.7))
        }
    }

    @ViewBuilder
    private func blockQuoteView(_ blockQuote: BlockQuote) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(baseColor.opacity(0.4))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    if let para = child as? Paragraph {
                        InlineRenderer(children: Array(para.inlineChildren), baseColor: baseColor.opacity(0.7), fontSize: fontSize)
                            .asText()
                            .italic()
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func unorderedListView(_ list: UnorderedList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text("•")
                        .font(.system(size: fontSize))
                        .foregroundColor(baseColor.opacity(0.6))
                        .frame(width: 12, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            if let para = child as? Paragraph {
                                InlineRenderer(children: Array(para.inlineChildren), baseColor: baseColor, fontSize: fontSize)
                            } else {
                                BlockRenderer(markup: child, baseColor: baseColor, fontSize: fontSize)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func orderedListView(_ list: OrderedList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text("\(index + 1).")
                        .font(.system(size: fontSize))
                        .foregroundColor(baseColor.opacity(0.6))
                        .frame(width: 20, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            if let para = child as? Paragraph {
                                InlineRenderer(children: Array(para.inlineChildren), baseColor: baseColor, fontSize: fontSize)
                            } else {
                                BlockRenderer(markup: child, baseColor: baseColor, fontSize: fontSize)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Table View

private struct MarkdownTableView: View {
    let table: Markdown.Table
    let baseColor: Color
    let fontSize: CGFloat

    private var columnCount: Int {
        max(table.maxColumnCount, 1)
    }

    private var headerCells: [Markdown.Table.Cell] {
        Array(table.head.cells)
    }

    private var bodyRows: [[Markdown.Table.Cell]] {
        Array(table.body.rows).map { Array($0.cells) }
    }

    private var columnWidths: [CGFloat] {
        (0..<columnCount).map { column in
            let headerLength = plainTextLength(cell(at: column, in: headerCells))
            let bodyLength = bodyRows.map { plainTextLength(cell(at: column, in: $0)) }.max() ?? 0
            let longest = max(headerLength, bodyLength)
            return min(max(CGFloat(longest) * 7 + 28, 72), 220)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownTableRowView(
                    cells: headerCells,
                    widths: columnWidths,
                    alignments: table.columnAlignments,
                    isHeader: true,
                    baseColor: baseColor,
                    fontSize: fontSize
                )

                ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                    MarkdownTableRowView(
                        cells: row,
                        widths: columnWidths,
                        alignments: table.columnAlignments,
                        isHeader: false,
                        baseColor: baseColor,
                        fontSize: fontSize
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(baseColor.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(at index: Int, in cells: [Markdown.Table.Cell]) -> Markdown.Table.Cell? {
        guard cells.indices.contains(index) else { return nil }
        return cells[index]
    }

    private func plainTextLength(_ cell: Markdown.Table.Cell?) -> Int {
        cell?.plainText.count ?? 0
    }
}

private struct MarkdownTableRowView: View {
    let cells: [Markdown.Table.Cell]
    let widths: [CGFloat]
    let alignments: [Markdown.Table.ColumnAlignment?]
    let isHeader: Bool
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(widths.indices, id: \.self) { index in
                MarkdownTableCellView(
                    cell: cell(at: index),
                    width: widths[index],
                    alignment: alignment(at: index),
                    isHeader: isHeader,
                    baseColor: baseColor,
                    fontSize: fontSize
                )
            }
        }
    }

    private func cell(at index: Int) -> Markdown.Table.Cell? {
        guard cells.indices.contains(index) else { return nil }
        return cells[index]
    }

    private func alignment(at index: Int) -> Alignment {
        guard alignments.indices.contains(index), let alignment = alignments[index] else {
            return .leading
        }

        switch alignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
}

private struct MarkdownTableCellView: View {
    let cell: Markdown.Table.Cell?
    let width: CGFloat
    let alignment: Alignment
    let isHeader: Bool
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        InlineRenderer(
            children: cell.map { Array($0.inlineChildren) } ?? [],
            baseColor: isHeader ? baseColor : baseColor.opacity(0.85),
            fontSize: fontSize
        )
        .font(.system(size: fontSize, weight: isHeader ? .semibold : .regular))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, alignment: alignment)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isHeader ? baseColor.opacity(0.10) : Color.white.opacity(0.035))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(baseColor.opacity(0.10))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(baseColor.opacity(isHeader ? 0.18 : 0.08))
                .frame(height: 1)
        }
    }
}

// MARK: - Inline Renderer

private struct InlineRenderer: View {
    let children: [InlineMarkup]
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        asText()
    }

    func asText() -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for child in children {
            result = result + renderInline(child)
        }
        return result
    }

    private func renderInline(_ inline: InlineMarkup) -> SwiftUI.Text {
        if let text = inline as? Markdown.Text {
            return SwiftUI.Text(text.string).foregroundColor(baseColor)
        } else if let strong = inline as? Strong {
            let plainText = strong.plainText
            return SwiftUI.Text(plainText)
                .fontWeight(.bold)
                .foregroundColor(baseColor)
        } else if let emphasis = inline as? Emphasis {
            let plainText = emphasis.plainText
            return SwiftUI.Text(plainText)
                .italic()
                .foregroundColor(baseColor)
        } else if let code = inline as? InlineCode {
            return SwiftUI.Text(code.code)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(baseColor)
        } else if let link = inline as? Markdown.Link {
            let plainText = link.plainText
            return SwiftUI.Text(plainText)
                .foregroundColor(Color.blue)
                .underline()
        } else if let strike = inline as? Strikethrough {
            let plainText = strike.plainText
            return SwiftUI.Text(plainText)
                .strikethrough()
                .foregroundColor(baseColor)
        } else if inline is SoftBreak {
            return SwiftUI.Text(" ")
        } else if inline is LineBreak {
            return SwiftUI.Text("\n")
        } else {
            return SwiftUI.Text(inline.plainText).foregroundColor(baseColor)
        }
    }

    private func renderChildren(_ children: [InlineMarkup]) -> SwiftUI.Text {
        var result = SwiftUI.Text("")
        for child in children {
            result = result + renderInline(child)
        }
        return result
    }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            SwiftUI.Text(code)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(6)
    }
}
