# SlideRev App Store 上架常见问题解答 (FAQ)

本文档旨在帮助您解决在将 SlideRev 打包并提交至 macOS App Store 过程中可能遇到的技术问题。

---

## 1. 证书与签名相关

### Q: 我需要哪些证书才能上架？
您需要在 [Apple Developer Member Center](https://developer.apple.com/account/) 申请以下两份证书：
1. **Apple Distribution**: 用于签署 App Bundle（`.app`），确保其符合 App Store 运行规范。
2. **3rd Party Mac Developer Installer**: 用于签署安装包（`.pkg`），这是提交至 Transporter 的必要格式。

### Q: 脚本中的 APP_CERT 和 INSTALLER_CERT 是什么？
这些是证书在您 Mac“钥匙串”中的完整显示名称。脚本已为您自动配置为：
- `Apple Distribution: Xinyu Liu (J4RT98GF7B)`
- `3rd Party Mac Developer Installer: Xinyu Liu (J4RT98GF7B)`

---

## 2. 编译与打包报错

### Q: 报错 "A timestamp was expected but was not found" 怎么办？
**原因**：在执行 `codesign` 签名时，系统无法连接到苹果的安全时间戳服务器。这通常是由于网络环境不稳定或代理拦截导致的。
**解决方法**：
1. **检查网络**：确保您的 Mac 可以正常访问苹果官网。
2. **显式指定服务器**：最新的 `appstore_package.sh` 已显式指定了 `http://timestamp.apple.com`。如果依然报错，请尝试切换网络环境（如使用手机热点）。
3. **什么是 Timestamp (时间戳)**：它是一种证明，证明您的应用是在证书有效期内签署的。即使未来证书到期，已上架的应用依然可以被系统信任。这是 App Store 的**强制要求**。

### Q: 为什么不能直接提交 `.app` 文件？
App Store Connect 仅接受通过 `productbuild` 封装并带有 `installer` 签名的 `.pkg` 文件。手动压缩 `.app` 为 `.zip` 上传通常会被拒绝。

---

## 3. 提交与审核

### Q: 如何上传打包好的 `.pkg`？
1. 从 Mac App Store 下载 **Transporter** 应用。
2. 登录您的 Apple ID。
3. 将 `dist_archive/SlideRev.pkg` 拖入。
4. 点击“交付 (Deliver)”。

### Q: 遇到“沙盒权限 (Sandbox)”相关的审核打回？
SlideRev 已经配置了必要的沙盒权限（`SlideRev.entitlements`），包括：
- `com.apple.security.app-sandbox`: 强制开启沙盒。
- `com.apple.security.files.user-selected.read-write`: 允许访问用户选中的 PDF/PPTX。
- `com.apple.security.files.bookmarks.app-scope`: 允许持久化保存文件访问令牌。

如果审核中提到文件无法保存，请检查是否在代码中正确使用了 `startAccessingSecurityScopedResource()`（目前我们的 native 逻辑已处理）。

---

## 4. 版本管理

### Q: 我想更新版本号怎么下载？
直接修改 `appstore_package.sh` 顶部的 `VERSION="0.9.8"` 变量即可。请确保此版本号与您在 App Store Connect 中创建的版本一致。
