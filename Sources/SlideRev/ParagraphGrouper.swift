import Foundation
import CoreGraphics

// MARK: - ParagraphGroup 数据结构

/// 合并后的段落组，由 ParagraphGrouper 生成，内部用于构建合并后的 RecognizedItem
struct ParagraphGroup: Identifiable {
    var id: UUID
    var items: [AdvancedSlideProcessor.RecognizedItem]
    var mergedRect: CGRect
    var mergedPixelRect: CGRect
    var representativeFontSize: CGFloat
    var representativeColor: CGColor
    var representativeFontName: String
    var representativeIsBold: Bool

    /// 合并后的多行文本（各行以 \n 连接）
    var mergedText: String {
        items.map { $0.editedText.isEmpty ? $0.text : $0.editedText }
              .joined(separator: "\n")
    }
}

// MARK: - ParagraphGrouper

/// 段落合并器：将 OCR 结果中零散的单行文本块按空间位置和视觉属性合并
///
/// 合并条件（同时满足）：
///   1. Y 轴行间距 < itemHeight × yGapMultiplier
///   2. X 轴左边距偏差 < itemHeight × xAlignTolerance
///   3. 字号偏差 < fontSizeTolerance (pt)
///   4. 颜色 RGB 欧氏距离 < colorDistanceThreshold (0~255 空间)
class ParagraphGrouper {

    // MARK: - 配置参数

    struct Config {
        var yGapMultiplier: CGFloat = 0.5        // 收紧：行距（两行上下沿留白）约束为小于半个字高
        var xAlignTolerance: CGFloat = 1.5       // 允许 1.5 个字符左右水平位置偏移
        var fontSizeToleranceRatio: CGFloat = 0.1// 放宽字号判断：使用相对比例（两行字号差异不能超过 10%）
        /// 颜色欧氏距离上限（0–255 空间）
        var colorDistanceThreshold: CGFloat = 60.0

        static let `default` = Config()
    }

    // MARK: - 辅助：将 groupId 写回原始 items（供单元测试验证）

    /// 对 `items` 进行分组，并将各组的 `groupId` 写回对应的 item，
    /// 返回带有 `groupId` 的原始 item 列表（不做合并，保留数量）。
    /// 手动橡皮擦 item 的 `groupId` 保持为 nil。
    @discardableResult
    static func assignGroupIds(
        to items: [AdvancedSlideProcessor.RecognizedItem],
        config: Config = .default
    ) -> [AdvancedSlideProcessor.RecognizedItem] {
        let groups = group(items: items, config: config)

        // 建立 item.id → groupId 映射
        var idToGroupId: [UUID: UUID] = [:]
        for group in groups {
            for item in group.items {
                idToGroupId[item.id] = group.id
            }
        }

        // 写回
        return items.map { item in
            var copy = item
            copy.groupId = idToGroupId[item.id]
            return copy
        }
    }

    // MARK: - 主入口：group + merge，直接返回合并后的 items

    /// 对 OCR 结果执行分组并合并，返回合并后的 `[RecognizedItem]`
    /// 同段的多行合并为一个 item，editedText 以 `\n` 分隔
    static func groupAndMerge(
        items: [AdvancedSlideProcessor.RecognizedItem],
        config: Config = .default
    ) -> [AdvancedSlideProcessor.RecognizedItem] {
        let groups = group(items: items, config: config)
        let merged = mergeGroups(groups)
        // 手动橡皮擦项不参与分组，原样追加在最后
        let erasers = items.filter { $0.isManualEraser }
        return merged + erasers
    }

    // MARK: - 分组算法

    static func group(
        items: [AdvancedSlideProcessor.RecognizedItem],
        config: Config = .default
    ) -> [ParagraphGroup] {
        let textItems = items.filter { !$0.isManualEraser && !$0.text.isEmpty }
        let sorted = textItems.sorted { $0.rect.minY < $1.rect.minY }
        guard !sorted.isEmpty else { return [] }

        var openGroups: [[AdvancedSlideProcessor.RecognizedItem]] = []

        for curr in sorted {
            var merged = false
            for i in 0..<openGroups.count {
                let prev = openGroups[i].last!
                if canMerge(prev: prev, curr: curr, config: config) {
                    openGroups[i].append(curr)
                    merged = true
                    break
                }
            }
            if !merged {
                openGroups.append([curr])
            }
        }
        
        return openGroups.map { buildGroup(from: $0) }
    }

    // MARK: - 合并组 → 单个 RecognizedItem

    static func mergeGroups(_ groups: [ParagraphGroup]) -> [AdvancedSlideProcessor.RecognizedItem] {
        return groups.map { group -> AdvancedSlideProcessor.RecognizedItem in
            if group.items.count == 1 {
                // 单行：直接返回，不修改
                return group.items[0]
            }

            // 多行：合并
            let allCharRects = group.items.flatMap { $0.charRects }
            let mergedEditedText = group.items.map {
                $0.editedText.isEmpty ? $0.text : $0.editedText
            }.joined(separator: "\n")

            let alignment = determineAlignment(for: group.items)

            return AdvancedSlideProcessor.RecognizedItem(
                text: group.items.map { $0.text }.joined(separator: "\n"),
                editedText: mergedEditedText,
                rect: group.mergedRect,
                pixelRect: group.mergedPixelRect,
                charRects: allCharRects,
                fontSize: group.representativeFontSize,
                color: group.representativeColor,
                viewState: group.items[0].viewState,
                isManualEraser: false,
                isBold: group.representativeIsBold,
                groupId: group.id,
                textAlignment: alignment
            )
        }
    }

    // MARK: - 对齐推断算法

    /// 根据组合内各行的间距偏差计算对齐方式
    static func determineAlignment(for items: [AdvancedSlideProcessor.RecognizedItem]) -> String {
        guard items.count > 1 else { return "l" }
        
        let minXDiff = items.dropFirst().enumerated().map { i, item in
            abs(item.rect.minX - items[i].rect.minX)
        }.reduce(0, +)
        
        let midXDiff = items.dropFirst().enumerated().map { i, item in
            abs(item.rect.midX - items[i].rect.midX)
        }.reduce(0, +)
        
        let maxXDiff = items.dropFirst().enumerated().map { i, item in
            abs(item.rect.maxX - items[i].rect.maxX)
        }.reduce(0, +)
        
        if midXDiff <= minXDiff && midXDiff <= maxXDiff {
            return "ctr"
        } else if maxXDiff < minXDiff && maxXDiff < midXDiff {
            return "r"
        } else {
            return "l"
        }
    }

    // MARK: - 私有辅助

    private static func canMerge(
        prev: AdvancedSlideProcessor.RecognizedItem,
        curr: AdvancedSlideProcessor.RecognizedItem,
        config: Config
    ) -> Bool {
        let refHeight = min(prev.rect.height, curr.rect.height)
        guard refHeight > 0 else { return false }

        // 1. 行间距
        let yGap = curr.rect.minY - prev.rect.maxY
        guard yGap < refHeight * config.yGapMultiplier else { return false }
        guard yGap > -(refHeight * 0.5) else { return false }

        // 2. X 对齐（支持左对齐、居中对齐、右对齐）
        let xDiff = abs(curr.rect.minX - prev.rect.minX)
        let midXDiff = abs(curr.rect.midX - prev.rect.midX)
        let rightXDiff = abs(curr.rect.maxX - prev.rect.maxX)
        
        let xAligned = xDiff < refHeight * config.xAlignTolerance
        let centerAligned = midXDiff < refHeight * config.xAlignTolerance
        let rightAligned = rightXDiff < refHeight * config.xAlignTolerance
        
        guard xAligned || centerAligned || rightAligned else { return false }

        // 3. 字号相似（使用相对比例而不是绝对值，两行字高差异需小于基准字高的 Config 比例）
        let minFontSize = min(prev.fontSize, curr.fontSize)
        guard minFontSize > 0 else { return false }
        let fontDiffRatio = abs(curr.fontSize - prev.fontSize) / minFontSize
        guard fontDiffRatio < config.fontSizeToleranceRatio else { return false }

        // 4. 颜色相似（RGB 欧氏距离，0–255 空间）
        guard colorDistance(prev.color, curr.color) < config.colorDistanceThreshold else { return false }

        return true
    }

    /// 计算两个 CGColor 在 0–255 RGB 空间中的欧氏距离
    private static func colorDistance(_ a: CGColor, _ b: CGColor) -> CGFloat {
        let ca = rgbComponents(a)
        let cb = rgbComponents(b)
        let dr = (ca.r - cb.r) * 255
        let dg = (ca.g - cb.g) * 255
        let db = (ca.b - cb.b) * 255
        return sqrt(dr * dr + dg * dg + db * db)
    }

    private static func rgbComponents(_ color: CGColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        let comps = c?.components ?? [0, 0, 0, 1]
        return (
            r: comps.count > 0 ? comps[0] : 0,
            g: comps.count > 1 ? comps[1] : 0,
            b: comps.count > 2 ? comps[2] : 0
        )
    }

    private static func buildGroup(
        from items: [AdvancedSlideProcessor.RecognizedItem]
    ) -> ParagraphGroup {
        let groupId = UUID()
        let mergedRect = items.reduce(CGRect.null) { $0.union($1.rect) }
        let mergedPixelRect = items.reduce(CGRect.null) { $0.union($1.pixelRect) }
        let minFontSize = items.map { $0.fontSize }.min() ?? 12
        let firstItem = items[0]

        return ParagraphGroup(
            id: groupId,
            items: items,
            mergedRect: mergedRect,
            mergedPixelRect: mergedPixelRect,
            representativeFontSize: minFontSize,
            representativeColor: firstItem.color,
            representativeFontName: firstItem.fontName,
            representativeIsBold: firstItem.isBold
        )
    }
}
