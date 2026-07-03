# 照片快清

一个 SwiftUI + PhotoKit 的 iPhone 照片快捷清理 App。

## 功能

- 首次打开请求相册权限。
- 主界面左右滑动浏览照片。
- 点“删除”时只加入 App 内部回收站，不立即删除系统相册照片。
- 回收站支持全选、恢复和永久删除。
- 永久删除会调用 iOS 系统相册删除流程，系统可能弹出确认，照片也可能先进入系统“最近删除”。

## 项目结构

- `project.yml`：XcodeGen 项目配置。
- `PhotoCleaner/`：App 源码。
- `PhotoCleanerTests/`：单元测试。
- `.github/workflows/ios-build.yml`：GitHub 免费 macOS runner 构建配置。

## 在 GitHub 构建

这个项目不需要在 Windows 上安装 Xcode。上传到 GitHub 后，Actions 会在 macOS runner 上安装 XcodeGen、生成 Xcode 工程，并执行无签名编译和测试。

如果要导出可安装的 IPA，需要在 GitHub Secrets 配置：

- `APPLE_TEAM_ID`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `PROVISION_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`

没有这些 Secrets 时，workflow 仍会验证项目能编译，但不会产出 IPA。
