import XCTest
import CoreGraphics
import AppKit
@testable import SlideRev

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Test Helpers
// ─────────────────────────────────────────────────────────────────────────

private func makeItem(
    text: String = "text",
    x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
    fontSize: CGFloat = 14.0,
    isManualEraser: Bool = false
) -> AdvancedSlideProcessor.RecognizedItem {
    let rect = CGRect(x: x, y: y, width: w, height: h)
    return AdvancedSlideProcessor.RecognizedItem(
        text: text,
        editedText: text,
        rect: rect,
        pixelRect: rect,
        charRects: [],
        fontSize: fontSize,
        color: NSColor.black.cgColor,
        viewState: .refined,
        isManualEraser: isManualEraser
    )
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - ParagraphGrouperTests
// ─────────────────────────────────────────────────────────────────────────

final class ParagraphGrouperTests: XCTestCase {

    // ── 测试 1：单个 item 独立成组 ──
    func testSingleItemFormsSingleGroup() {
        let item = makeItem(x: 0.1, y: 0.1, w: 0.3, h: 0.05)
        let groups = ParagraphGrouper.group(items: [item])
        XCTAssertEqual(groups.count, 1, "单个 item 应生成 1 个组")
        XCTAssertEqual(groups[0].items.count, 1, "组内应有 1 个 item")
    }

    // ── 测试 2：Y 轴紧密相邻的两个 item 应合并 ──
    func testTwoNearbyItemsMerge() {
        let h: CGFloat = 0.04
        let item1 = makeItem(text: "第一行", x: 0.1, y: 0.10, w: 0.6, h: h, fontSize: 14)
        // Y Gap = 0.15 - 0.14 = 0.01，远小于 h * 1.8 = 0.072 → 应合并
        let item2 = makeItem(text: "第二行", x: 0.1, y: 0.14, w: 0.6, h: h, fontSize: 14)
        let groups = ParagraphGrouper.group(items: [item1, item2])
        XCTAssertEqual(groups.count, 1, "两行相邻 item 应合并为 1 组")
        XCTAssertEqual(groups[0].items.count, 2, "合并组内应有 2 个 item")
        XCTAssertEqual(groups[0].mergedText, "第一行\n第二行", "合并文本应以换行符连接")
    }

    // ── 测试 3：Y 轴间距过大的两个 item 不应合并 ──
    func testTwoFarApartItemsDoNotMerge() {
        let h: CGFloat = 0.04
        let item1 = makeItem(x: 0.1, y: 0.10, w: 0.4, h: h, fontSize: 14)
        // Y Gap = 0.40 - 0.14 = 0.26，远大于 h * 1.8 = 0.072 → 不应合并
        let item2 = makeItem(x: 0.1, y: 0.40, w: 0.4, h: h, fontSize: 14)
        let groups = ParagraphGrouper.group(items: [item1, item2])
        XCTAssertEqual(groups.count, 2, "垂直间距过大的 item 应分为 2 组")
    }

    // ── 测试 4：X 轴左边距偏差过大，不合并 ──
    func testXMisalignmentPreventsGrouping() {
        let h: CGFloat = 0.04
        let item1 = makeItem(x: 0.10, y: 0.10, w: 0.4, h: h, fontSize: 14)
        // X 偏差 = |0.40 - 0.10| = 0.30，远大于 h * 0.5 = 0.02 → 不合并
        let item2 = makeItem(x: 0.40, y: 0.14, w: 0.4, h: h, fontSize: 14)
        let groups = ParagraphGrouper.group(items: [item1, item2])
        XCTAssertEqual(groups.count, 2, "X 轴错位的 item 应分为 2 组")
    }

    // ── 测试 5：字号差异过大，不合并（标题 vs 正文） ──
    func testFontSizeDifferencePreventsGrouping() {
        let h: CGFloat = 0.04
        let title = makeItem(x: 0.1, y: 0.10, w: 0.5, h: h, fontSize: 28.0)
        // 字号差 |14 - 28| = 14 > 默认容差 4.0 → 不合并
        let body  = makeItem(x: 0.1, y: 0.15, w: 0.5, h: h, fontSize: 14.0)
        let groups = ParagraphGrouper.group(items: [title, body])
        XCTAssertEqual(groups.count, 2, "标题与正文字号差异过大，不应合并")
    }

    // ── 测试 6：手动橡皮擦 item 被排除在分组之外 ──
    func testManualEraserItemsExcluded() {
        let eraser = makeItem(text: "", x: 0.0, y: 0.0, w: 0.2, h: 0.1, isManualEraser: true)
        let text   = makeItem(text: "正常文字", x: 0.1, y: 0.1, w: 0.4, h: 0.04)
        let groups = ParagraphGrouper.group(items: [eraser, text])
        // eraser 被过滤，只有一个 text → 1 组
        XCTAssertEqual(groups.count, 1, "手动橡皮擦应被过滤，只剩 1 组")
        XCTAssertEqual(groups[0].items.count, 1, "组内只有 1 个 text item")
    }

    // ── 测试 7：groupId 正确写回 items ──
    func testGroupIdWrittenBack() {
        let h: CGFloat = 0.04
        let item1 = makeItem(text: "行一", x: 0.1, y: 0.10, w: 0.5, h: h)
        let item2 = makeItem(text: "行二", x: 0.1, y: 0.14, w: 0.5, h: h)
        let item3 = makeItem(text: "独立标题", x: 0.1, y: 0.50, w: 0.5, h: h)
        let assigned = ParagraphGrouper.assignGroupIds(to: [item1, item2, item3])
        XCTAssertEqual(assigned.count, 3, "assignGroupIds 应保留原始 item 数量")
        XCTAssertNotNil(assigned[0].groupId, "item1 应有 groupId")
        XCTAssertNotNil(assigned[1].groupId, "item2 应有 groupId")
        XCTAssertEqual(assigned[0].groupId, assigned[1].groupId, "item1 和 item2 应共享同一 groupId")
        XCTAssertNotEqual(assigned[2].groupId, assigned[0].groupId, "item3 应有不同的 groupId")
    }

    // ── 测试 8：三行连续段落合并为一组 ──
    func testThreeLinesParagraphMerge() {
        let h: CGFloat = 0.035
        let items = [
            makeItem(text: "Line 1", x: 0.1, y: 0.100, w: 0.5, h: h, fontSize: 12),
            makeItem(text: "Line 2", x: 0.1, y: 0.135, w: 0.5, h: h, fontSize: 12),
            makeItem(text: "Line 3", x: 0.1, y: 0.170, w: 0.5, h: h, fontSize: 12),
        ]
        let groups = ParagraphGrouper.group(items: items)
        XCTAssertEqual(groups.count, 1, "三行连续文本应合并为 1 组")
        XCTAssertEqual(groups[0].items.count, 3, "组内应有 3 个 item")
        XCTAssertGreaterThan(groups[0].mergedRect.height, h, "合并后的外包框高度应大于单行高度")
    }

    // ── 测试 9：页面上不同区域的段落不互相合并 ──
    func testMixedParagraphsNotGroupedTogether() {
        let h: CGFloat = 0.04
        let para1 = [
            makeItem(text: "段落A行1", x: 0.1, y: 0.10, w: 0.5, h: h, fontSize: 14),
            makeItem(text: "段落A行2", x: 0.1, y: 0.14, w: 0.5, h: h, fontSize: 14),
        ]
        let para2 = [
            makeItem(text: "段落B行1", x: 0.1, y: 0.50, w: 0.5, h: h, fontSize: 14),
            makeItem(text: "段落B行2", x: 0.1, y: 0.54, w: 0.5, h: h, fontSize: 14),
        ]
        let groups = ParagraphGrouper.group(items: para1 + para2)
        XCTAssertEqual(groups.count, 2, "两个区域段落应分为 2 组")
        XCTAssertEqual(groups[0].items.count, 2, "段落A应有 2 行")
        XCTAssertEqual(groups[1].items.count, 2, "段落B应有 2 行")
    }
}
