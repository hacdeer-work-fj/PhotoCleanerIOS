# 照片快清 PhotoCleaner

照片快清是一个原生 SwiftUI iPhone App，用来更快地浏览、筛选和清理相册内容。项目可以在 Windows 上维护源码，并通过 GitHub Actions 免费 macOS runner 自动构建 unsigned IPA。

## 主要功能

- 请求系统相册权限，读取照片、实况照片和视频。
- 主界面左右滑动浏览上一张 / 下一张。
- 底部保留两个主要操作：`删除` 和 `回收站`。
- 点击 `删除` 只会把当前项目放入 App 内部回收站，不会立刻删除系统相册内容。
- 回收站支持选择、全选、恢复和永久删除。
- 永久删除时调用 iOS 系统相册删除流程，系统可能弹出确认，照片或视频通常还会进入系统“最近删除”。
- 底部缩略图条支持快速跳转，视频和实况照片会显示小标识。
- 实况照片支持长按预览。
- 视频支持自动播放、点击暂停 / 继续，以及拖动进度条。
- 上划大图可查看文件信息、格式、大小、尺寸、时间和 EXIF。
- 如果照片包含位置信息，信息页会显示小地图；点击地图可跳转到 Apple 系统地图对应位置。

## 下载 unsigned IPA

每次推送版本标签后，GitHub Actions 会自动创建 GitHub Release，并上传：

- `PhotoCleaner-unsigned.ipa`

下载入口：

- [GitHub Releases](https://github.com/hacdeer-work-fj/PhotoCleanerIOS/releases)

注意：这个 IPA 是未签名的，不能直接安装到普通 iPhone。你可以用 AltStore、Sideloadly、企业签名、越狱环境或其他重签工具处理后安装。

## GitHub Actions 构建

workflow 位于 `.github/workflows/ios-build.yml`，会执行：

- 安装 XcodeGen。
- 生成 Xcode 工程。
- 无签名模拟器构建。
- 运行测试。
- 构建设备版 unsigned app。
- 打包 `PhotoCleaner-unsigned.ipa`。
- 上传 Actions artifact。
- 当推送 `v*` 标签时，自动创建 GitHub Release 并上传 unsigned IPA。

如果后续需要导出已签名 IPA，可以配置这些 GitHub Secrets：

- `APPLE_TEAM_ID`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `PROVISION_PROFILE_BASE64`
- `KEYCHAIN_PASSWORD`

没有这些 Secrets 时，项目仍会产出 unsigned IPA。

## 本地项目结构

- `project.yml`：XcodeGen 项目配置。
- `PhotoCleaner/`：App 源码。
- `PhotoCleanerTests/`：单元测试。
- `.github/workflows/ios-build.yml`：GitHub Actions 构建和 Release 配置。

## 技术栈

- SwiftUI
- PhotoKit
- PhotosUI
- AVFoundation
- MapKit
- XcodeGen
- GitHub Actions

## 版本规则

- `MARKETING_VERSION`：用户看到的版本号，例如 `1.9`。
- `CURRENT_PROJECT_VERSION`：构建号，每次准备发布新包时递增。
- 推送 `v*` 标签会触发 Release，例如 `v1.9`。

## 许可证

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
