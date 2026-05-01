import XCTest
import STBaseProject
@testable import STBaseProjectExample

private struct MockCodeBlockRenderer: STMarkdownCodeBlockRendering {
    func renderCodeBlock(language: String?, code: String, style: STMarkdownStyle) -> NSAttributedString? {
        NSAttributedString(string: "[code:\(language ?? "plain")]\(code)")
    }
}

private struct MockInlineMathRenderer: STMarkdownInlineMathRendering {
    func renderInlineMath(formula: String, style: STMarkdownStyle, baseFont: UIFont, textColor: UIColor) -> NSAttributedString? {
        NSAttributedString(string: "[math:\(formula)]")
    }
}

private final class MockImageLoader: STMarkdownImageLoading {
    private(set) var lastURL: URL?

    func loadImage(from url: URL, completion: @escaping @Sendable (UIImage?) -> Void) {
        self.lastURL = url
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        completion(image)
    }
}

private final class CancellableMockImageLoader: STMarkdownCancellableImageLoading {
    private(set) var cancellable = MockImageCancellable()
    private(set) var requestedURL: URL?

    func loadImage(from url: URL, completion: @escaping @Sendable (UIImage?) -> Void) {
        _ = self.loadCancellableImage(from: url, completion: completion)
    }

    func loadCancellableImage(from url: URL, completion: @escaping @Sendable (UIImage?) -> Void) -> STMarkdownImageLoadCancellable? {
        self.requestedURL = url
        return self.cancellable
    }
}

private final class MockImageCancellable: STMarkdownImageLoadCancellable {
    private(set) var didCancel = false

    func cancel() {
        self.didCancel = true
    }
}

final class STMarkdownPipelineTests: XCTestCase {

    func testInputSanitizerConvertsHtmlLinkToMarkdown() {
        let sanitizer = STMarkdownInputSanitizer(
            rules: [
                STHtmlNormalizeRule(),
                STHtmlLinkToMarkdownRule(),
            ]
        )

        let result = sanitizer.sanitize(#"<a href=\"https://example.com\">Example</a>"#)

        XCTAssertEqual(result.sanitizedText, "[Example](https://example.com)")
        XCTAssertTrue(result.appliedRules.contains("STHtmlLinkToMarkdownRule"))
    }

    func testStructureParserPreservesOrderedListStartIndex() {
        let parser = STMarkdownStructureParser()

        let document = parser.parse(
            """
            3. 第三项
            4. 第四项
            """
        )

        guard case .list(let kind, let items)? = document.blocks.first else {
            return XCTFail("Expected first block to be list")
        }

        guard case .ordered(let startIndex) = kind else {
            return XCTFail("Expected ordered list kind")
        }

        XCTAssertEqual(startIndex, 3)
        XCTAssertEqual(items.count, 2)
    }

    func testRenderAdapterFlattensOrderedListIndices() {
        let parser = STMarkdownStructureParser()
        let adapter = STMarkdownRenderAdapter()
        let document = parser.parse(
            """
            5. 第一项
            6. 第二项
            """
        )

        let renderDocument = adapter.adapt(document)

        guard case .list(let items)? = renderDocument.blocks.first else {
            return XCTFail("Expected first render block to be list")
        }

        XCTAssertEqual(items.map(\.orderedIndex), [5, 6])
        XCTAssertTrue(items.allSatisfy(\.ordered))
    }

    func testMarkdownEngineReturnsSourceAndRenderDocuments() {
        let engine = STMarkdownEngine()

        let result = engine.process("**标题**")

        XCTAssertFalse(result.sourceDocument.blocks.isEmpty)
        XCTAssertFalse(result.renderDocument.blocks.isEmpty)
        XCTAssertEqual(result.rawMarkdown, "**标题**")
    }

    func testSoftBreakCollapsingNormalizerRemovesAdjacentSoftBreaks() {
        let document = STMarkdownDocument(
            blocks: [
                .paragraph([
                    .text("A"),
                    .softBreak,
                    .softBreak,
                    .text("B"),
                ])
            ]
        )
        let normalizer = STMarkdownSoftBreakCollapsingNormalizer()

        let normalized = normalizer.normalize(document)

        guard case .paragraph(let inlines)? = normalized.blocks.first else {
            return XCTFail("Expected paragraph block")
        }
        XCTAssertEqual(inlines, [.text("A"), .softBreak, .text("B")])
    }

    func testSoftBreakCollapsingNormalizerRecursivelyNormalizesNestedChildren() {
        let document = STMarkdownDocument(
            blocks: [
                .quote([
                    .paragraph([
                        .text("outer"),
                        .softBreak,
                        .softBreak,
                        .text("tail"),
                    ]),
                    .list(
                        kind: .unordered,
                        items: [
                            STMarkdownListItemNode(
                                blocks: [
                                    .paragraph([
                                        .text("item"),
                                        .softBreak,
                                        .softBreak,
                                        .text("end"),
                                    ])
                                ]
                            )
                        ]
                    ),
                ])
            ]
        )
        let normalizer = STMarkdownSoftBreakCollapsingNormalizer()

        let normalized = normalizer.normalize(document)

        guard case .quote(let blocks)? = normalized.blocks.first else {
            return XCTFail("Expected quote block")
        }
        guard case .paragraph(let outer)? = blocks.first else {
            return XCTFail("Expected first quote child to be paragraph")
        }
        XCTAssertEqual(outer, [.text("outer"), .softBreak, .text("tail")])

        guard case .list(_, let items)? = blocks.last,
              case .paragraph(let nested)? = items.first?.blocks.first
        else {
            return XCTFail("Expected list paragraph in quote")
        }
        XCTAssertEqual(nested, [.text("item"), .softBreak, .text("end")])
    }

    func testAttributedStringRendererUsesDistinctBoldFontForStrongText() {
        let renderer = STMarkdownAttributedStringRenderer()
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .strong([.text("粗体")]),
                    .text(" 普通"),
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let strongFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let normalFont = attributed.attribute(.font, at: attributed.length - 1, effectiveRange: nil) as? UIFont

        XCTAssertNotNil(strongFont)
        XCTAssertNotNil(normalFont)
        XCTAssertNotEqual(strongFont?.fontName, normalFont?.fontName)
    }

    func testAttributedStringRendererRendersOrderedListMarker() {
        let renderer = STMarkdownAttributedStringRenderer()
        let document = STMarkdownRenderDocument(
            blocks: [
                .list([
                    STMarkdownRenderListItem(
                        content: [.text("第一项")],
                        ordered: true,
                        level: 0,
                        orderedIndex: 3,
                        childBlocks: []
                    )
                ])
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.hasPrefix("3.\t"))
        XCTAssertTrue(attributed.string.contains("第一项"))
    }

    func testMarkdownStreamingTextViewRendersMarkdown() {
        let view = STMarkdownStreamingTextView()

        view.setMarkdown("**标题**\n\n1. 第一项", animated: false)

        XCTAssertTrue(view.attributedText.string.contains("标题"))
        XCTAssertTrue(view.attributedText.string.contains("第一项"))
    }

    func testMarkdownStreamingTextViewReplacesTrailingRangeWhenRenderedPrefixMutates() {
        let view = STMarkdownStreamingTextView()

        view.setMarkdown("[链接](https://example.com", animated: false)
        view.updateStreamingMarkdown("[链接](https://example.com)")

        let range = (view.attributedText.string as NSString).range(of: "链接")
        let link = view.attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL

        XCTAssertEqual(link?.absoluteString, "https://example.com")
    }

    func testMarkdownTextViewRendersMarkdown() {
        let view = STMarkdownTextView()

        view.setMarkdown("## 标题\n\n- 列表项")

        XCTAssertTrue(view.attributedText.string.contains("标题"))
        XCTAssertTrue(view.attributedText.string.contains("列表项"))
    }

    func testMarkdownTextViewResetClearsContent() {
        let view = STMarkdownTextView()
        view.setMarkdown("普通文本")

        view.reset()

        XCTAssertTrue(view.attributedText.string.isEmpty)
        XCTAssertTrue(view.rawMarkdown.isEmpty)
    }

    func testRenderAdapterPreservesNestedListLevel() {
        let parser = STMarkdownStructureParser()
        let adapter = STMarkdownRenderAdapter()
        let document = parser.parse(
            """
            1. 第一项
               - 子项
            """
        )

        let renderDocument = adapter.adapt(document)

        guard
            case .list(let items)? = renderDocument.blocks.first,
            case .list(let childItems)? = items.first?.childBlocks.first
        else {
            return XCTFail("Expected nested render list")
        }

        XCTAssertEqual(items.first?.level, 0)
        XCTAssertEqual(childItems.first?.level, 1)
    }

    func testAttributedStringRendererOffsetsLooseListParagraphIndent() {
        let renderer = STMarkdownAttributedStringRenderer()
        let document = STMarkdownRenderDocument(
            blocks: [
                .list([
                    STMarkdownRenderListItem(
                        blocks: [
                            .paragraph([.text("第一段")]),
                            .paragraph([.text("第二段")]),
                        ],
                        ordered: true,
                        level: 0,
                        orderedIndex: 1
                    )
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let secondParagraphLocation = (attributed.string as NSString).range(of: "第二段").location
        let paragraphStyle = attributed.attribute(.paragraphStyle, at: secondParagraphLocation, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertNotNil(paragraphStyle)
        XCTAssertGreaterThan(paragraphStyle?.headIndent ?? 0, 0)
    }

    func testAttributedStringRendererUsesCustomCodeBlockRenderer() {
        let renderer = STMarkdownAttributedStringRenderer(
            advancedRenderers: STMarkdownAdvancedRenderers(
                codeBlockRenderer: MockCodeBlockRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .codeBlock(language: "swift", code: "print(1)")
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertEqual(attributed.string, "[code:swift]print(1)")
    }

    func testAttributedStringRendererUsesCustomInlineMathRenderer() {
        let renderer = STMarkdownAttributedStringRenderer(
            advancedRenderers: STMarkdownAdvancedRenderers(
                inlineMathRenderer: MockInlineMathRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .text("结果 "),
                    .inlineMath("x+y", isDisplayMode: false),
                ])
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.contains("[math:x+y]"))
    }

    func testDefaultMathRendererRendersSuperscriptContent() {
        let renderer = STMarkdownAttributedStringRenderer(
            advancedRenderers: STMarkdownAdvancedRenderers(
                inlineMathRenderer: STMarkdownDefaultMathRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .inlineMath("x^2", isDisplayMode: false)
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let baselineOffset = attributed.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? CGFloat

        XCTAssertEqual(attributed.string, "x2")
        XCTAssertNotNil(baselineOffset)
        XCTAssertGreaterThan(baselineOffset ?? 0, 0)
    }

    func testStructureParserExtractsInlineMathNodes() {
        let parser = STMarkdownStructureParser()
        let document = parser.parse(#"结果是 \(x^2+y^2\)"#)

        guard case .paragraph(let inlines)? = document.blocks.first else {
            return XCTFail("Expected paragraph block")
        }

        XCTAssertTrue(inlines.contains { node in
            if case .inlineMath(let formula, _) = node {
                return formula == "x^2+y^2"
            }
            return false
        })
    }

    func testDefaultCodeBlockRendererIncludesLanguageHeader() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                codeBlockRenderer: STMarkdownDefaultCodeBlockRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .codeBlock(language: "swift", code: "print(\"hi\")")
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.hasPrefix("SWIFT\n"))
        XCTAssertTrue(attributed.string.contains("print(\"hi\")"))
    }

    func testDefaultCodeBlockRendererUsesMonospacedFont() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                codeBlockRenderer: STMarkdownDefaultCodeBlockRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .codeBlock(language: nil, code: "let value = 1")
            ]
        )

        let attributed = renderer.render(document: document)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont

        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontName.lowercased().contains("mono") == true)
    }

    func testDefaultTableRendererRendersHeaderAndSeparator() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                tableRenderer: STMarkdownDefaultTableRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .table(
                    STMarkdownTableModel(
                        header: [
                            [.text("名称")],
                            [.text("值")],
                        ],
                        rows: [
                            [
                                [.text("速度")],
                                [.text("快")],
                            ]
                        ]
                    )
                )
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.contains("名称"))
        XCTAssertTrue(attributed.string.contains("值"))
        XCTAssertTrue(attributed.string.contains("┼"))
        XCTAssertTrue(attributed.string.contains("速度"))
    }

    func testDefaultTableRendererUsesMonospacedFont() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                tableRenderer: STMarkdownDefaultTableRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .table(
                    STMarkdownTableModel(
                        header: nil,
                        rows: [
                            [
                                [.text("A")],
                                [.text("B")],
                            ]
                        ]
                    )
                )
            ]
        )

        let attributed = renderer.render(document: document)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont

        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontName.lowercased().contains("mono") == true)
    }

    func testDefaultImageRendererUsesAltTextForInlineImage() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                imageRenderer: STMarkdownDefaultImageRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .image(source: "https://example.com/a.png", alt: "示意图", title: nil)
                ])
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.contains("示意图"))
    }

    func testDefaultImageRendererRendersBlockCaption() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                imageRenderer: STMarkdownDefaultImageRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .image(url: "https://example.com/a.png", altText: "", title: "图片说明")
            ]
        )

        let attributed = renderer.render(document: document)

        XCTAssertTrue(attributed.string.contains("[image] a.png"))
        XCTAssertTrue(attributed.string.contains("图片说明"))
    }

    func testDefaultHorizontalRuleRendererUsesConfiguredLength() {
        let style = STMarkdownStyle(
            font: .systemFont(ofSize: 16, weight: .regular),
            textColor: .label,
            lineHeight: 24,
            kern: 0.12,
            horizontalRuleLength: 10
        )
        let renderer = STMarkdownAttributedStringRenderer(
            style: style,
            advancedRenderers: STMarkdownAdvancedRenderers(
                horizontalRuleRenderer: STMarkdownDefaultHorizontalRuleRenderer()
            )
        )
        let document = STMarkdownRenderDocument(blocks: [.thematicBreak])

        let attributed = renderer.render(document: document)

        XCTAssertEqual(attributed.string, String(repeating: "─", count: 12))
    }

    func testCodeBlockAttachmentRendererProducesAttachment() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                codeBlockRenderer: STMarkdownCodeBlockAttachmentRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .codeBlock(language: "swift", code: "print(\"hi\")")
            ]
        )

        let attributed = renderer.render(document: document)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment

        XCTAssertNotNil(attachment)
        XCTAssertNotNil(attachment?.image)
        XCTAssertGreaterThan(attachment?.bounds.width ?? 0, 0)
        XCTAssertGreaterThan(attachment?.bounds.height ?? 0, 0)
    }

    func testAsyncImageRendererProducesAttachmentAndCallsLoader() {
        let loader = MockImageLoader()
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                imageRenderer: STMarkdownAsyncImageRenderer(loader: loader)
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .image(url: "https://example.com/image.png", altText: "示意图", title: "图片标题")
            ]
        )

        let attributed = renderer.render(document: document)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment

        XCTAssertEqual(loader.lastURL?.absoluteString, "https://example.com/image.png")
        XCTAssertNotNil(attachment)
        XCTAssertNotNil(attachment?.image)
        XCTAssertTrue(attributed.string.contains("图片标题"))
    }

    func testTableAttachmentRendererProducesAttachment() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                tableRenderer: STMarkdownTableAttachmentRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .table(
                    STMarkdownTableModel(
                        header: [
                            [.text("列1")],
                            [.text("列2")],
                        ],
                        rows: [
                            [
                                [.text("A")],
                                [.text("B")],
                            ]
                        ]
                    )
                )
            ]
        )

        let attributed = renderer.render(document: document)
        // STMarkdownTableViewAttachment 使用 overlay 机制（不走 TextKit 绘制），
        // image 始终为 nil，尺寸通过 attachmentBounds 在 layout 时计算。
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? STMarkdownTableViewAttachment

        XCTAssertNotNil(attachment)
        XCTAssertNil(attachment?.image)
        XCTAssertNotNil(attachment?.tableViewModel)
        XCTAssertGreaterThan(attachment?.containerWidth ?? 0, 0)
    }

    // MARK: - Multi-table Tests

    func testTableBlankLineRuleInsertsBlankLineBeforeTableAfterText() {
        let rule = STTableBlankLineNormalizationRule()
        var context = STMarkdownPreprocessContext()

        let input = "Some text\n| A | B |\n|---|---|"

        let result = rule.apply(to: input, context: &context)

        XCTAssertTrue(result.contains("Some text\n\n| A | B |"))
    }

    func testTableBlankLineRuleInsertsBlankLineAfterTableBeforeText() {
        let rule = STTableBlankLineNormalizationRule()
        var context = STMarkdownPreprocessContext()

        let input = "| A | B |\n|---|---|\nSome text"

        let result = rule.apply(to: input, context: &context)

        XCTAssertTrue(result.contains("|---|---|\n\nSome text"))
    }

    func testTableBlankLineRuleSkipsContentInsideCodeFence() {
        let rule = STTableBlankLineNormalizationRule()
        var context = STMarkdownPreprocessContext()

        let input = "```\nSome text\n| A | B |\n```"

        let result = rule.apply(to: input, context: &context)

        XCTAssertEqual(result, input)
    }

    func testTableDelimiterRuleInsertsDelimiterForHeaderWithoutOne() {
        let rule = STTableDelimiterNormalizationRule()
        var context = STMarkdownPreprocessContext()

        // Second table starts after blank line but has no delimiter row
        let input = "| A | B |\n|---|---|\n| 1 | 2 |\n\n| C | D |\n| 3 | 4 |"

        let result = rule.apply(to: input, context: &context)

        XCTAssertTrue(result.contains("| C | D |\n| --- | --- |\n| 3 | 4 |"))
    }

    func testTableDelimiterRuleDoesNotDuplicateExistingDelimiter() {
        let rule = STTableDelimiterNormalizationRule()
        var context = STMarkdownPreprocessContext()

        let input = "| A | B |\n|---|---|\n| 1 | 2 |"

        let result = rule.apply(to: input, context: &context)

        // No extra delimiter should be inserted
        let delimiterCount = result.components(separatedBy: "|---|---|").count - 1
        XCTAssertEqual(delimiterCount, 1)
    }

    func testTableDelimiterRuleSkipsContentInsideCodeFence() {
        let rule = STTableDelimiterNormalizationRule()
        var context = STMarkdownPreprocessContext()

        let input = "```\n| A | B |\n| 1 | 2 |\n```"

        let result = rule.apply(to: input, context: &context)

        XCTAssertEqual(result, input)
    }

    func testEngineRecognizesSecondTableMissingDelimiter() {
        let engine = STMarkdownEngine()
        // Second table lacks delimiter row — should be repaired by STTableDelimiterNormalizationRule
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |\n\n| C | D |\n| 3 | 4 |"

        let result = engine.process(markdown)
        let tableBlocks = result.renderDocument.blocks.compactMap { block -> STMarkdownTableModel? in
            if case .table(let m) = block { return m }
            return nil
        }

        XCTAssertEqual(tableBlocks.count, 2, "两个表格都应被识别，即使第二个缺少分隔行")
    }

    func testEngineRecognizesTwoWellFormedTables() {
        let engine = STMarkdownEngine()
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |\n\n| C | D |\n|---|---|\n| 3 | 4 |"

        let result = engine.process(markdown)
        let tableBlocks = result.renderDocument.blocks.compactMap { block -> STMarkdownTableModel? in
            if case .table(let m) = block { return m }
            return nil
        }

        XCTAssertEqual(tableBlocks.count, 2)
    }

    func testHighFidelityMathRendererProducesInlineAttachment() {
        let renderer = STMarkdownAttributedStringRenderer(
            style: STMarkdownStyle.default,
            advancedRenderers: STMarkdownAdvancedRenderers(
                inlineMathRenderer: STMarkdownHighFidelityMathRenderer()
            )
        )
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .inlineMath(#"\frac{1}{2}"#, isDisplayMode: false)
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment

        XCTAssertNotNil(attachment)
        XCTAssertNotNil(attachment?.image)
        XCTAssertGreaterThan(attachment?.bounds.width ?? 0, 0)
    }

    // MARK: - Strikethrough Tests

    func testStructureParserParsesStrikethrough() {
        let parser = STMarkdownStructureParser()
        let document = parser.parse("~~删除文本~~")

        guard case .paragraph(let inlines)? = document.blocks.first else {
            return XCTFail("Expected paragraph block")
        }

        XCTAssertTrue(inlines.contains { node in
            if case .strikethrough(let children) = node {
                return children.contains(.text("删除文本"))
            }
            return false
        })
    }

    func testAttributedStringRendererAppliesStrikethroughStyle() {
        let renderer = STMarkdownAttributedStringRenderer()
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .strikethrough([.text("已删除")])
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let style = attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int

        XCTAssertEqual(attributed.string, "已删除")
        XCTAssertNotNil(style)
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testStrikethroughWithCustomColor() {
        let markdownStyle = STMarkdownStyle(
            font: .systemFont(ofSize: 16),
            textColor: .label,
            lineHeight: 24,
            kern: 0.12,
            strikethroughColor: .red
        )
        let renderer = STMarkdownAttributedStringRenderer(style: markdownStyle)
        let document = STMarkdownRenderDocument(
            blocks: [
                .paragraph([
                    .strikethrough([.text("红色删除线")])
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let color = attributed.attribute(.strikethroughColor, at: 0, effectiveRange: nil) as? UIColor

        XCTAssertEqual(color, .red)
    }

    // MARK: - Task List / Checkbox Tests

    func testStructureParserParsesTaskListCheckbox() {
        let parser = STMarkdownStructureParser()
        let document = parser.parse("- [x] 已完成\n- [ ] 未完成")

        guard case .list(_, let items)? = document.blocks.first else {
            return XCTFail("Expected list block")
        }

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].checkbox, .checked)
        XCTAssertEqual(items[1].checkbox, .unchecked)
    }

    func testRenderAdapterPreservesCheckbox() {
        let parser = STMarkdownStructureParser()
        let adapter = STMarkdownRenderAdapter()
        let document = parser.parse("- [x] 已完成\n- [ ] 未完成")

        let renderDocument = adapter.adapt(document)

        guard case .list(let items)? = renderDocument.blocks.first else {
            return XCTFail("Expected list render block")
        }

        XCTAssertEqual(items[0].checkbox, .checked)
        XCTAssertEqual(items[1].checkbox, .unchecked)
    }

    func testAttributedStringRendererRendersCheckboxMarkers() {
        let renderer = STMarkdownAttributedStringRenderer()
        let document = STMarkdownRenderDocument(
            blocks: [
                .list([
                    STMarkdownRenderListItem(
                        content: [.text("已完成")],
                        ordered: false,
                        level: 0,
                        orderedIndex: nil,
                        childBlocks: [],
                        checkbox: .checked
                    ),
                    STMarkdownRenderListItem(
                        content: [.text("未完成")],
                        ordered: false,
                        level: 0,
                        orderedIndex: nil,
                        childBlocks: [],
                        checkbox: .unchecked
                    ),
                ])
            ]
        )

        let attributed = renderer.render(document: document)
        let text = attributed.string

        XCTAssertTrue(text.contains("☑"))
        XCTAssertTrue(text.contains("☐"))
        XCTAssertTrue(text.contains("已完成"))
        XCTAssertTrue(text.contains("未完成"))
    }

    // MARK: - Sanitizer Rule Tests

    func testHtmlNormalizeRuleUnescapesCRLF() {
        let rule = STHtmlNormalizeRule()
        var context = STMarkdownPreprocessContext()

        let result = rule.apply(to: "第一行\\n第二行", context: &context)

        XCTAssertEqual(result, "第一行\n第二行")
    }

    func testAnchorCleanupRuleRemovesFragmentAnchors() {
        let rule = STAnchorCleanupRule()
        var context = STMarkdownPreprocessContext()

        let input = ##"参考<a href="#ref1">文献1</a>内容"##
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(result.contains("<a"))
        XCTAssertTrue(result.contains("参考"))
        XCTAssertTrue(result.contains("内容"))
    }

    func testPageReferenceCleanupRuleRemovesWebpageReferences() {
        let rule = STPageReferenceCleanupRule()
        var context = STMarkdownPreprocessContext()

        let input = "一些内容[webpage 1]后续文本"
        let result = rule.apply(to: input, context: &context)

        XCTAssertEqual(result, "一些内容后续文本")
    }

    func testDoubleNewlineRuleCollapsesTripleNewlines() {
        let rule = STDoubleNewlineRule()
        var context = STMarkdownPreprocessContext()

        let result = rule.apply(to: "A\n\n\n\nB", context: &context)

        XCTAssertEqual(result, "A\n\nB")
    }

    // MARK: - Math Normalizer Tests

    func testMathNormalizerHandlesEmptyInput() {
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: "")

        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.blockMap.isEmpty)
    }

    func testMathNormalizerExtractsBlockMath() {
        let input = "文本\n\n$$\nx^2 + y^2 = z^2\n$$\n\n后续"
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertFalse(result.blockMap.isEmpty)
        XCTAssertTrue(result.text.contains("{{ST_MATH_BLOCK:"))
        XCTAssertTrue(result.blockMap.values.contains { $0.contains("x^2 + y^2 = z^2") })
    }

    func testMathNormalizerPreservesCodeBlocks() {
        let input = "```\n$$\nnot math\n$$\n```"
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertTrue(result.blockMap.isEmpty)
        XCTAssertTrue(result.text.contains("not math"))
    }

    func testMathNormalizerExtractsBracketAndEnvironmentBlocks() {
        let input = """
        前文
        \\[
        a+b
        \\]

        \\begin{align}
        x &= y + z
        \\end{align}
        """
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertEqual(result.blockMap.count, 2)
        XCTAssertTrue(result.text.contains("{{ST_MATH_BLOCK:0}}"))
        XCTAssertTrue(result.text.contains("{{ST_MATH_BLOCK:1}}"))
        XCTAssertEqual(result.blockMap[0], "a+b")
        XCTAssertTrue(result.blockMap[1]?.contains("\\begin{align}") == true)
        XCTAssertTrue(result.blockMap[1]?.contains("\\end{align}") == true)
    }

    func testInlineMathSplitProducesCorrectNodes() {
        let nodes = STMarkdownMathNormalizer.splitInlineMath(in: #"结果 \(x+y\) 结束"#)

        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0], .text("结果 "))
        XCTAssertEqual(nodes[1], .inlineMath("x+y", isDisplayMode: false))
        XCTAssertEqual(nodes[2], .text(" 结束"))
    }

    // MARK: - Deep Nested List Tests

    func testRenderAdapterHandlesThreeLevelNestedList() {
        let parser = STMarkdownStructureParser()
        let adapter = STMarkdownRenderAdapter()
        let document = parser.parse(
            """
            - 第一层
              - 第二层
                - 第三层
            """
        )

        let renderDocument = adapter.adapt(document)

        guard case .list(let items)? = renderDocument.blocks.first else {
            return XCTFail("Expected list block")
        }

        XCTAssertEqual(items.first?.level, 0)

        guard case .list(let level1Items)? = items.first?.childBlocks.first else {
            return XCTFail("Expected nested list at level 1")
        }
        XCTAssertEqual(level1Items.first?.level, 1)

        guard case .list(let level2Items)? = level1Items.first?.childBlocks.first else {
            return XCTFail("Expected nested list at level 2")
        }
        XCTAssertEqual(level2Items.first?.level, 2)
    }

    func testStructureParserSplitsMixedTextAndMathBlockIntoSeparateBlocks() {
        let parser = STMarkdownStructureParser()
        let document = parser.parse(
            """
            开头

            $$
            x^2 + y^2 = z^2
            $$

            结尾
            """
        )

        XCTAssertEqual(document.blocks.count, 3)
        XCTAssertEqual(document.blocks[0], .paragraph([.text("开头")]))
        XCTAssertEqual(document.blocks[1], .mathBlock("x^2 + y^2 = z^2"))
        XCTAssertEqual(document.blocks[2], .paragraph([.text("结尾")]))
    }

    func testInputSanitizerDoesNotInjectTableDelimiterInsideCodeFence() {
        let sanitizer = STMarkdownInputSanitizer(rules: [STTableDelimiterNormalizationRule()])
        let input = """
        ```markdown
        | A | B |
        | 1 | 2 |
        ```
        """

        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitizedText, input)
        XCTAssertFalse(result.appliedRules.contains("STTableDelimiterNormalizationRule"))
    }

    // MARK: - Streaming View Tests

    func testStreamingTextViewAppendFragment() {
        let view = STMarkdownStreamingTextView()

        view.setMarkdown("Hello", animated: false)
        view.appendMarkdownFragment(" World", animated: false)

        XCTAssertTrue(view.attributedText.string.contains("Hello"))
        XCTAssertTrue(view.attributedText.string.contains("World"))
        XCTAssertEqual(view.rawMarkdown, "Hello World")
    }

    func testStreamingTextViewResetClearsContent() {
        let view = STMarkdownStreamingTextView()
        view.setMarkdown("一些内容", animated: false)

        view.reset()

        XCTAssertTrue(view.rawMarkdown.isEmpty)
    }

    func testStaticTextViewAddsTableOverlayForViewBasedAttachment() {
        let style = STMarkdownStyle(
            font: .systemFont(ofSize: 16),
            textColor: .label,
            lineHeight: 24,
            kern: 0,
            renderWidth: 320
        )
        let view = STMarkdownTextView(
            style: style,
            advancedRenderers: STMarkdownPresets.makeDefaultAdvancedRenderers()
        )
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 240)

        view.setMarkdown(
            """
            | A | B |
            |---|---|
            | 1 | 2 |
            """
        )
        view.layoutIfNeeded()

        let tableOverlayCount = view.contentTextView.subviews
            .compactMap { $0 as? STMarkdownTableView }
            .count
        XCTAssertEqual(tableOverlayCount, 1)
    }

    func testStreamingTextViewAddsTableOverlayForViewBasedAttachment() {
        let style = STMarkdownStyle(
            font: .systemFont(ofSize: 16),
            textColor: .label,
            lineHeight: 24,
            kern: 0,
            renderWidth: 320
        )
        let view = STMarkdownStreamingTextView(
            style: style,
            advancedRenderers: STMarkdownPresets.makeDefaultAdvancedRenderers()
        )
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 240)

        view.setMarkdown(
            """
            | A | B |
            |---|---|
            | 1 | 2 |
            """,
            animated: false
        )
        view.layoutIfNeeded()

        let tableOverlayCount = view.contentTextView.subviews
            .compactMap { $0 as? STMarkdownTableView }
            .count
        XCTAssertEqual(tableOverlayCount, 1)
    }

    func testAsyncImageAttachmentCancelsLoaderWhenReleased() {
        let loader = CancellableMockImageLoader()

        autoreleasepool {
            let attributed = STMarkdownAsyncImageRenderer(loader: loader).renderImage(
                url: "https://example.com/image.png",
                altText: "",
                title: nil,
                style: .default,
                inline: true
            )

            XCTAssertEqual(loader.requestedURL?.absoluteString, "https://example.com/image.png")
            XCTAssertNotNil(attributed)
            XCTAssertFalse(loader.cancellable.didCancel)
        }

        XCTAssertTrue(loader.cancellable.didCancel)
    }

    // MARK: - Sendable Conformance Tests

    func testPipelineResultIsSendable() {
        let result = STMarkdownPipelineResult(
            rawMarkdown: "test",
            sanitizedMarkdown: "test",
            appliedRules: [],
            sourceDocument: STMarkdownDocument(blocks: []),
            normalizedDocument: STMarkdownDocument(blocks: []),
            renderDocument: STMarkdownRenderDocument(blocks: [])
        )
        let sendableCheck: any Sendable = result
        XCTAssertNotNil(sendableCheck)
    }

    func testSanitizationResultIsSendable() {
        let result = STMarkdownSanitizationResult(
            originalText: "test",
            sanitizedText: "test",
            appliedRules: []
        )
        let sendableCheck: any Sendable = result
        XCTAssertNotNil(sendableCheck)
    }

    // MARK: - STHtmlNormalizeRule 补齐

    func testHtmlNormalizeRuleReplacesBrWithHardBreak() {
        let rule = STHtmlNormalizeRule()
        var context = STMarkdownPreprocessContext()

        let result = rule.apply(to: "第一行<br>第二行<br/>第三行<BR />第四行", context: &context)

        XCTAssertFalse(result.contains("<br"), "<br> 系列标签应全部被替换")
        XCTAssertFalse(result.contains("</br>"))
        // CommonMark 硬换行是行尾两空格 + \n；这里至少三处换行
        let newlineCount = result.filter { $0 == "\n" }.count
        XCTAssertEqual(newlineCount, 3, "三个 <br> 应被替换为三次换行")
    }

    func testHtmlNormalizeRuleRewritesEmptyClosingTagToAnchor() {
        let rule = STHtmlNormalizeRule()
        var context = STMarkdownPreprocessContext()

        let result = rule.apply(to: "<a href=\"https://x.com\">链接</>", context: &context)

        XCTAssertFalse(result.contains("</>"), "`</>` 应被改写")
        XCTAssertTrue(result.contains("</a>"), "`</>` 应被改写为 `</a>`")
    }

    func testHtmlNormalizeRuleUnescapesCRAndCRLF() {
        let rule = STHtmlNormalizeRule()
        var context = STMarkdownPreprocessContext()

        // 注意：escapedCR/escapedLF 都带 `(?![A-Za-z])` 负前瞻，避免误吃 `\rest` 这种 LaTeX 命令；
        // 因此构造样例时单独的 `\r` 后必须不是字母——这里用空格。
        let input = "A\\r\\nB\\r 尾"
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(result.contains("\\r"), "`\\r\\n` 与 `\\r `（非字母后续）应被消费")
        XCTAssertFalse(result.contains("\\n"))
        // `\r\n` → 换行；`\r ` → 换行（保留尾随空格）
        XCTAssertTrue(result.contains("A\nB\n"), "应把转义换行序列还原为真实换行")
    }

    func testHtmlNormalizeRuleShouldApplyGatesByCheapCheck() {
        let rule = STHtmlNormalizeRule()
        XCTAssertFalse(rule.shouldApply(to: "纯中文，无任何 HTML/转义"))
        XCTAssertTrue(rule.shouldApply(to: "含 <br> 的输入"))
        XCTAssertTrue(rule.shouldApply(to: #"含 \" 的输入"#))
        XCTAssertTrue(rule.shouldApply(to: #"含 \/ 的输入"#))
        XCTAssertTrue(rule.shouldApply(to: #"含 \n 的输入"#))
    }

    // MARK: - STHtmlLinkToMarkdownRule 补齐

    func testHtmlLinkRuleFallsBackToTitleWhenSchemeIsDangerous() {
        let rule = STHtmlLinkToMarkdownRule()
        var context = STMarkdownPreprocessContext()

        // javascript: 被拒绝 → 只保留可见 title
        let input = #"<a href="javascript:alert(1)">点我</a>"#
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(result.contains("javascript"), "dangerous scheme 不应泄漏进输出")
        XCTAssertFalse(result.contains("<a "), "原始 <a> 应被消费")
        XCTAssertFalse(result.contains("]("), "不应被转换为 markdown 链接语法")
        XCTAssertTrue(result.contains("点我"), "title 必须保留")
    }

    func testHtmlLinkRuleFallsBackToTitleWhenUrlHasNoHost() {
        let rule = STHtmlLinkToMarkdownRule()
        var context = STMarkdownPreprocessContext()

        // 无 host → parsedURL.host == nil → 仅保留 title
        let input = #"<a href="http:///path">t</a>"#
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(result.contains("<a "))
        XCTAssertFalse(result.contains("]("), "无 host 不应合成 markdown 链接")
        XCTAssertTrue(result.contains("t"))
    }

    func testHtmlLinkRuleHandlesAttributesSpacingSingleQuotesAndMultilineTitle() {
        let rule = STHtmlLinkToMarkdownRule()
        var context = STMarkdownPreprocessContext()
        let input = """
        <a class="external" title="docs" href = 'https://example.com/docs'>
        Docs
        </a>
        """

        let result = rule.apply(to: input, context: &context)

        XCTAssertEqual(result, "[\nDocs\n](https://example.com/docs)")
    }

    func testHtmlLinkRulePreservesNestedTagTitleAsMarkdownText() {
        let rule = STHtmlLinkToMarkdownRule()
        var context = STMarkdownPreprocessContext()

        let result = rule.apply(
            to: #"<a href=\"https://example.com\"><strong>Example</strong></a>"#,
            context: &context
        )

        XCTAssertEqual(result, "[<strong>Example</strong>](https://example.com)")
    }

    // MARK: - STAnchorCleanupRule 补齐

    func testAnchorCleanupRuleKeepsAnchorWhenFragmentContainsHttp() {
        let rule = STAnchorCleanupRule()
        var context = STMarkdownPreprocessContext()

        // href="#http..." 的 anchor 是真实引用，不应被清理
        let input = ##"前<a href="#https://ref">ref</a>后"##
        let result = rule.apply(to: input, context: &context)

        XCTAssertTrue(result.contains("<a"), "fragment 含 http 时，anchor 不应被删除")
        XCTAssertTrue(result.contains("ref"))
    }

    // MARK: - STPageReferenceCleanupRule 补齐

    func testPageReferenceRuleRemovesChineseBracketVariants() {
        let rule = STPageReferenceCleanupRule()
        var context = STMarkdownPreprocessContext()

        // 中文/西文括号 + Markdown 链接 `[...](#…)` 形式：整段（含括号）应被清理。
        let bracketWrapped: [(input: String, kept: String)] = [
            ("前文【[第3页](#a)】后文",      "前文后文"),
            ("前文《[页面5](#b)》后文",      "前文后文"),
            ("前文「[引用网页2](#c)」后文",   "前文后文"),
            ("前文『[参考7](#d)』后文",      "前文后文"),
            ("前文（[见5页](#e)）后文",      "前文后文"),
        ]
        for (input, expected) in bracketWrapped {
            let result = rule.apply(to: input, context: &context)
            XCTAssertEqual(
                result,
                expected,
                "输入 `\(input)` 应被清理为 `\(expected)`，实际 `\(result)`"
            )
        }

        // 裸 `[webpage N]` / 嵌套 `[[webpage N]]` 形式：仅消除内部引用，外层定界符不属于该规则的责任范围。
        let bareWebpage: [(input: String, contains: String, mustNot: String)] = [
            ("前文 [webpage 1] 后文",       "前文",   "webpage"),
            ("前文 [[webpage 3]] 后文",     "前文",   "webpage"),
        ]
        for (input, contains, mustNot) in bareWebpage {
            let result = rule.apply(to: input, context: &context)
            XCTAssertFalse(result.contains(mustNot), "输入 `\(input)` 中 `\(mustNot)` 应被清理")
            XCTAssertTrue(result.contains(contains))
        }
    }

    func testPageReferenceRuleConvergesWithinIterationCap() {
        // 嵌套包裹 → 规则内的循环应在有限迭代内收敛：`webpage` 被连根拔除；
        // 外层裸 `[]` / 括号不属于该规则责任范围，允许残留。
        let rule = STPageReferenceCleanupRule()
        var context = STMarkdownPreprocessContext()

        let input = "A （[[webpage 1]]）B"
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(result.contains("webpage"), "所有 webpage 引用应被清理")
        XCTAssertTrue(result.contains("A"))
        XCTAssertTrue(result.contains("B"))
    }

    // MARK: - STTableDelimiterNormalizationRule 补齐：列数不匹配不合成

    func testTableDelimiterRuleDoesNotSynthesizeWhenColumnCountMismatch() {
        let rule = STTableDelimiterNormalizationRule()
        var context = STMarkdownPreprocessContext()

        // 前一行 2 列，后一行 3 列 → 按照注释里的安全阀，不应误合成 delimiter
        let input = "| A | B |\n| 1 | 2 | 3 |"
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(
            result.contains("| --- |"),
            "列数不匹配时不应插入 delimiter，实际：\(result)"
        )
    }

    func testTableDelimiterRuleDoesNotSynthesizeForSingleColumnRows() {
        let rule = STTableDelimiterNormalizationRule()
        var context = STMarkdownPreprocessContext()

        // 两行都只有 1 列 → columnCount >= 2 guard 阻止合成
        let input = "| A |\n| 1 |"
        let result = rule.apply(to: input, context: &context)

        XCTAssertFalse(
            result.contains("---"),
            "单列行不应被改写为表格"
        )
    }

    // MARK: - STMarkdownInputSanitizer 短路 / 空输入

    func testInputSanitizerShortCircuitsOnEmptyInput() {
        let sanitizer = STMarkdownInputSanitizer(rules: [STHtmlNormalizeRule()])
        let result = sanitizer.sanitize("")

        XCTAssertEqual(result.originalText, "")
        XCTAssertEqual(result.sanitizedText, "")
        XCTAssertTrue(result.appliedRules.isEmpty, "空输入应跳过所有规则")
    }

    func testInputSanitizerDoesNotRecordRuleWhenApplyIsNoOp() {
        // shouldApply 返回 true 但 apply 没有实质修改时，不应记入 appliedRules
        let sanitizer = STMarkdownInputSanitizer(
            rules: [STDoubleNewlineRule()]
        )
        // 输入不含 3 个以上连续换行，规则的 shouldApply 就会 false → appliedRules 为空
        let result = sanitizer.sanitize("A\n\nB")
        XCTAssertFalse(result.appliedRules.contains("STDoubleNewlineRule"))
        XCTAssertEqual(result.sanitizedText, "A\n\nB")
    }

    func testPipelineReusesSanitizerAndProducesStableResultsAcrossCalls() {
        let pipeline = STMarkdownPipeline()
        let input = """
        <a href="https://example.com">Example</a>



        Tail
        """

        let first = pipeline.process(input)
        let second = pipeline.process(input)

        XCTAssertEqual(first.sanitizedMarkdown, second.sanitizedMarkdown)
        XCTAssertEqual(first.appliedRules, second.appliedRules)
        XCTAssertEqual(first.renderDocument, second.renderDocument)
        XCTAssertEqual(first.sanitizedMarkdown, "[Example](https://example.com)\n\nTail")
        XCTAssertTrue(first.appliedRules.contains("STHtmlLinkToMarkdownRule"))
        XCTAssertTrue(first.appliedRules.contains("STDoubleNewlineRule"))
    }

    // MARK: - STMarkdownMathNormalizer 补齐

    func testMathNormalizerHandlesSameLineDollarBlock() {
        // $$formula$$ 同行开闭
        let input = "前文\n\n$$a+b$$\n\n后文"
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertEqual(result.blockMap.count, 1, "同行 $$...$$ 应被识别为块公式")
        XCTAssertEqual(result.blockMap[0], "a+b")
        XCTAssertTrue(result.text.contains("{{ST_MATH_BLOCK:0}}"))
    }

    func testMathNormalizerHandlesSameLineBracketBlock() {
        // \[formula\] 同行开闭
        let input = #"前文\n\n\[x=1\]\n\n后文"#
            .replacingOccurrences(of: "\\n", with: "\n")
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertEqual(result.blockMap.count, 1, "同行 \\[...\\] 应被识别为块公式")
        XCTAssertEqual(result.blockMap[0], "x=1")
    }

    func testMathNormalizerHandlesUnterminatedDollarBlockAsEof() {
        // $$ 未闭合 → 到 EOF 也应完成收集，不崩溃
        let input = "前文\n\n$$\nE = mc^2\n继续一行"
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)

        XCTAssertEqual(result.blockMap.count, 1, "未闭合块应兜底产出一条")
        XCTAssertTrue(result.blockMap[0]?.contains("E = mc^2") == true)
    }

    func testMathNormalizerRecognizesMultipleMathEnvironments() {
        let environments = ["equation", "gather", "cases", "pmatrix"]
        for env in environments {
            let input = """
            前文

            \\begin{\(env)}
            x
            \\end{\(env)}

            后文
            """
            let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)
            XCTAssertEqual(result.blockMap.count, 1, "环境 \(env) 应被识别")
            XCTAssertTrue(
                result.blockMap[0]?.contains("\\begin{\(env)}") == true,
                "应保留 \\begin{\(env)}"
            )
            XCTAssertTrue(
                result.blockMap[0]?.contains("\\end{\(env)}") == true,
                "应保留 \\end{\(env)}"
            )
        }
    }

    func testMathNormalizerIgnoresUnsupportedEnvironment() {
        // 未注册的环境不应被当作 math block，应当作普通文本保留
        let input = """
        前文

        \\begin{foo}
        x
        \\end{foo}

        后文
        """
        let result = STMarkdownMathNormalizer.normalizeBlocks(in: input)
        XCTAssertTrue(result.blockMap.isEmpty, "未支持的环境不应被抽成 math block")
        XCTAssertTrue(result.text.contains("\\begin{foo}"))
        XCTAssertTrue(result.text.contains("\\end{foo}"))
    }

    func testSplitInlineMathRecognizesBracketDisplayModeInline() {
        // 行内 \[x\] 应被识别为 isDisplayMode == true
        let nodes = STMarkdownMathNormalizer.splitInlineMath(in: #"前 \[a+b\] 后"#)

        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0], .text("前 "))
        XCTAssertEqual(nodes[1], .inlineMath("a+b", isDisplayMode: true))
        XCTAssertEqual(nodes[2], .text(" 后"))
    }

    func testSplitInlineMathReturnsEmptyForEmptyInput() {
        let nodes = STMarkdownMathNormalizer.splitInlineMath(in: "")
        XCTAssertTrue(nodes.isEmpty, "空输入应返回空数组")
    }

    func testSplitInlineMathReturnsSingleTextWhenNoFormula() {
        let nodes = STMarkdownMathNormalizer.splitInlineMath(in: "纯文本")
        XCTAssertEqual(nodes, [.text("纯文本")])
    }

    // MARK: - STMarkdownSoftBreakCollapsingNormalizer 补齐

    func testSoftBreakNormalizerCollapsesInsideHeading() {
        let document = STMarkdownDocument(
            blocks: [
                .heading(level: 2, content: [
                    .text("A"),
                    .softBreak,
                    .softBreak,
                    .text("B"),
                ])
            ]
        )
        let normalized = STMarkdownSoftBreakCollapsingNormalizer().normalize(document)

        guard case .heading(let level, let content)? = normalized.blocks.first else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(content, [.text("A"), .softBreak, .text("B")])
    }

    func testSoftBreakNormalizerRecursesIntoEmphasisStrongLinkStrikethrough() {
        let document = STMarkdownDocument(
            blocks: [
                .paragraph([
                    .emphasis([.text("a"), .softBreak, .softBreak, .text("b")]),
                    .strong([.text("c"), .softBreak, .softBreak, .text("d")]),
                    .link(destination: "https://x.com", children: [
                        .text("e"), .softBreak, .softBreak, .text("f")
                    ]),
                    .strikethrough([.text("g"), .softBreak, .softBreak, .text("h")]),
                ])
            ]
        )
        let normalized = STMarkdownSoftBreakCollapsingNormalizer().normalize(document)

        guard case .paragraph(let inlines)? = normalized.blocks.first else {
            return XCTFail("Expected paragraph")
        }

        func softBreakCount(_ nodes: [STMarkdownInlineNode]) -> Int {
            nodes.reduce(into: 0) { acc, node in
                if case .softBreak = node { acc += 1 }
            }
        }

        for node in inlines {
            switch node {
            case .emphasis(let c), .strong(let c), .strikethrough(let c):
                XCTAssertEqual(softBreakCount(c), 1, "子节点相邻 softBreak 应被折叠")
            case .link(_, let c):
                XCTAssertEqual(softBreakCount(c), 1, "link 子节点相邻 softBreak 应被折叠")
            default:
                break
            }
        }
    }

    func testSemanticNormalizerPassthroughKeepsDocumentIntact() {
        let document = STMarkdownDocument(
            blocks: [
                .paragraph([.text("A"), .softBreak, .softBreak, .text("B")])
            ]
        )
        let normalized = STMarkdownSemanticNormalizer.passthrough.normalize(document)
        // passthrough 应原样返回，不折叠相邻 softBreak
        XCTAssertEqual(normalized, document)
    }

    func testSemanticNormalizerChainsMultipleNormalizersInOrder() {
        struct TagNormalizer: STMarkdownSemanticNormalizing {
            let tag: String
            func normalize(_ document: STMarkdownDocument) -> STMarkdownDocument {
                let blocks = document.blocks.map { block -> STMarkdownBlockNode in
                    if case .paragraph(let inlines) = block {
                        return .paragraph(inlines + [.text(self.tag)])
                    }
                    return block
                }
                return STMarkdownDocument(blocks: blocks)
            }
        }

        let composite = STMarkdownSemanticNormalizer(
            normalizers: [TagNormalizer(tag: "_1"), TagNormalizer(tag: "_2")]
        )
        let normalized = composite.normalize(
            STMarkdownDocument(blocks: [.paragraph([.text("X")])])
        )

        guard case .paragraph(let inlines)? = normalized.blocks.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertEqual(inlines, [.text("X"), .text("_1"), .text("_2")],
                       "normalizer 应按注册顺序依次应用")
    }

    // MARK: - STMarkdownRenderListItem 契约

    func testRenderListItemContentAndChildBlocksWhenFirstBlockIsNotParagraph() {
        // 以 codeBlock 开头 → content 返回 []，childBlocks 返回全部 blocks
        let codeFirst = STMarkdownRenderListItem(
            blocks: [
                .codeBlock(language: "swift", code: "x"),
                .paragraph([.text("尾段")]),
            ],
            ordered: false,
            level: 0,
            orderedIndex: nil
        )
        XCTAssertTrue(codeFirst.content.isEmpty, "首块非 paragraph 时 content 应为空")
        XCTAssertEqual(codeFirst.childBlocks.count, 2,
                       "首块非 paragraph 时 childBlocks 应返回完整 blocks")
    }

    func testRenderListItemContentAndChildBlocksWhenFirstBlockIsParagraph() {
        let paraFirst = STMarkdownRenderListItem(
            blocks: [
                .paragraph([.text("首段")]),
                .codeBlock(language: nil, code: "x"),
            ],
            ordered: false,
            level: 0,
            orderedIndex: nil
        )
        XCTAssertEqual(paraFirst.content, [.text("首段")])
        XCTAssertEqual(paraFirst.childBlocks.count, 1, "应剥掉首段后仅剩子块")
        if case .codeBlock = paraFirst.childBlocks.first {} else {
            XCTFail("剩余子块应为 codeBlock")
        }
    }

    // MARK: - STMarkdownStructureParser 补齐

    func testParserNormalizesLinkDestinationTrimsWhitespace() {
        let parser = STMarkdownStructureParser()
        // swift-markdown 不允许 destination 里有未转义空白，这里用 `<…>` 形式构造可解析的空白 destination
        let doc = parser.parse("[t](<  https://example.com  >)")

        guard case .paragraph(let inlines)? = doc.blocks.first else {
            return XCTFail("Expected paragraph")
        }
        var destination: String?
        for node in inlines {
            if case .link(let d, _) = node { destination = d; break }
        }
        XCTAssertEqual(destination, "https://example.com",
                       "normalizeLinkDestination 应去除首尾空白")
    }
}
