# SlideRev 动效优化与文档架构整理计划 (v12.1)

## 问题分析
1. **反馈增强**：用户不仅需要进度提示，还需要“处理中的动画”，以增强 AI 处理的沉浸感。
2. **文档管理**：随着迭代增多，当前的实施计划和任务文档较多且分散，需要统一归档到项目中的 `docs/dev_process/` 目录。

## 拟执行的变更

### 1. 批量重构动效 (RefinementView.swift)
- **[NEW] `ScanningPageView`**：创建一个独立的动效组件，模拟扫描效果。
- **[MODIFY] `exportingOverlay`**：
    - 集成 `ScanningPageView`。
    - 绑定 `processor.batchStatus`，显示“正在识别 OCR...”、“正在重构第 N 页...”等详细信息。

### 2. 状态机增强 (AdvancedSlideProcessor.swift)
- **[MODIFY]** 新增 `@Published var batchStatus: String`。
- **[MODIFY]** 在异步处理逻辑中（`processSilently` 等）实时更新 `batchStatus`。

### 3. 目录结构优化 (Reorganization)
- **[NEW] `docs/dev_process/`**：创建此目录。
- **[MOVE/COPY]**：
    - 将 `implementation_plan.md` 存入 `docs/dev_process/implementation_plan_v12.md`。
    - 将 `task.md` 同步到 `docs/dev_process/task_v12.md`。
    - 后续所有重大的方案说明都将按此规范在项目中留存。

## 验证方案
1. **视觉验证**：在批量重构时看到扫描线动画。
2. **文件审计**：确认 `docs/dev_process/` 目录下已生成对应的归档文档。
