# 盲盒派对小助手

由 create-maa-project 生成的 MaaFW 项目。

## 运行

直接运行：

```text
.create-maa-project/runtime/mfaa/win-x64/MFAAvalonia.exe
```

通用界面只认自己旁边的 `interface.json`。运行目录里那份已经指回项目根的 `tasks/bpa.json` 和 `resource/base`，改任务不用再复制。

控制器选「安卓模拟器」。模拟器保持 16:9 横屏即可，当前这台是 1920×1080，框架会把短边缩放到 720 再识别。游戏包名是 `com.palmpi.matrix.yofun.mumu`。

默认勾选「启动MuMu」和「开始唤醒」。其余任务是占位，勾选后只会提示尚未实现，不会点击游戏。

## 开发

项目入口配置为 `interface.json`，任务定义在 `tasks/`，资源位于 `resource/`。

如果根目录存在 `package.json`，说明已启用开发工具，可运行：

```bash
pnpm install
pnpm check
```

在 VS Code 中打开项目时，`.vscode/tasks.json` 会自动执行 `pnpm install --frozen-lockfile`。

未启用时，可按需运行 `create-maa-project --add dev-tools` 添加格式化、校验和编辑器配置。

## 发布

如果存在 `.github/workflows/release.yml`，推送 `v0.1.0` 这样的 tag 会触发发布。
未启用时，可运行 `create-maa-project --add github` 添加 CI 和 Release 自动化。

English documentation: [README.en.md](./README.en.md)
