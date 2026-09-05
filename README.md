# 放牛班的春天 iPad App

一个离线、原生 SwiftUI iPad App。家长通过“文件”App 管理严格配对的中英文 MP4，App 按自然日生成连续观看计划；儿童首页只显示今天的一组视频。

## 从 GitHub 免费安装到 iPad

前提：一台 Mac、Xcode，以及运行 iPadOS 17.0 或更高版本的 iPad。普通 Apple Account 可以用于真机测试，不需要购买 Apple Developer Program。

1. 克隆项目并打开工程：

   ```sh
   git clone https://github.com/jax-ho/BilingualVideo.git
   cd BilingualVideo
   open BilingualVideo.xcodeproj
   ```

2. 在 Xcode → Settings → Apple Accounts 中登录自己的 Apple Account。免费账号会显示为“姓名 (Personal Team)”。

3. 用数据线连接并解锁 iPad；如果询问是否信任此电脑，请轻点“信任”。

4. 在 Xcode 左侧选择项目 `BilingualVideo`，再选择 TARGETS 下的 `BilingualVideo`，打开 Signing & Capabilities：

   - 保持 `Automatically manage signing` 开启。
   - Team 选择自己的 Personal Team。
   - 将 Bundle Identifier `com.jax.BilingualVideo` 改为自己的唯一标识，例如 `com.yourname.BilingualVideo`。

5. 在 Xcode 顶部选择 `BilingualVideo` scheme 和已连接的 iPad，点击 Run（▶）或按 `Command-R`。

6. 如果提示开启 Developer Mode，在 iPad 上打开“设置”→“隐私与安全性”→“开发者模式”，按提示重启并确认，然后回到 Xcode 再运行一次。

7. 首次启动后，到“文件”App →“我的 iPad”→“放牛班的春天”，把 MP4 分别放入 `Chinese/` 和 `English/`。

8. 回到 App，从“家长入口”创建 PIN、检查资源、生成并保存计划。

### 免费账号限制

Personal Team 仅适合在自己的设备上测试，不能用于 App Store、TestFlight 或长期分发 IPA。免费描述文件签发后 7 天到期，届时需要重新连接 iPad，在同一工程中再次 Run。

请保持同一个 Apple Account、Team 和 Bundle Identifier，并直接覆盖安装。不要先删除 App，否则 App 内的本地视频和计划也会被删除。

### 常见签名问题

- `Signing ... requires a development team`：在主 Target 的 Signing & Capabilities 中选择自己的 Personal Team。
- `Bundle Identifier is unavailable`：将 `com.jax.BilingualVideo` 改成自己的唯一 Bundle Identifier。
- `No profiles for ... were found`：确认 Apple Account 已登录、自动签名已开启、iPad 已解锁并信任 Mac、网络可用，然后重新 Run。
- `Developer Mode disabled`：在 iPad 的“设置”→“隐私与安全性”中开启开发者模式，重启并确认。
- iPad 没有出现在设备列表：重新连接并信任 Mac；确认 iPadOS 不低于 17.0，且 Xcode 已安装对应的平台支持。

工程已包含生成后的 `.xcodeproj`，安装 App 不需要运行 XcodeGen。修改 `project.yml` 后才需要运行 `xcodegen generate`；重新生成工程会覆盖直接在 Xcode 中修改的 Team 和 Bundle Identifier，因此应先同步修改 `project.yml`。

## 文件命名

- 文件名必须是纯数字加 `.mp4`，扩展名大小写均可。
- 同一数字编号的中英文文件组成一组；两边可使用不同的前导零，例如 `Chinese/005.mp4` 与 `English/5.mp4`。
- 同一目录中的 `5.mp4` 与 `005.mp4` 会被判定为重复编号。

## 测试

在 Xcode 中运行 `BilingualVideo` scheme 的测试，或使用：

```sh
xcodebuild -project BilingualVideo.xcodeproj \
  -scheme BilingualVideo \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test
```

命令行测试需要先在 Xcode → Settings → Components 安装 iOS Simulator runtime。可用 `xcodebuild -project BilingualVideo.xcodeproj -scheme BilingualVideo -showdestinations` 查看本机设备；若名称不同，请替换上面的 destination。

生成独立的正常和异常 Mock 视频目录：

```sh
./Tools/generate_mock_videos.sh
```

默认输出到带时间戳的新目录；也可传入一个不存在或为空的目标目录。脚本会拒绝写入非空目录，避免旧文件污染测试场景。脚本依赖开发机上的 `ffmpeg`，不会被打包进 App。

## 真机验收

发布前请在启用设备密码的 iPad 上完成以下检查：

- “文件”App 能看到 `Chinese/`、`English/`，添加或删除视频后资源页能准确刷新。
- 首次设置 PIN、错误 PIN、忘记 PIN 后的 Face ID/Touch ID/设备密码重设都符合预期。
- 中英文视频可播放、关闭、从头重播；文件损坏或播放期间被移除时只显示错误，不自动补位。
- 横竖屏、后台返回、跨午夜后，“今日观看”仍只对应本地自然日的一组视频。
