# LinkSwift + AB Download Manager 一键安装包

把「网盘直链 → AB Download Manager 多线程下载」这套环境，一键搬到任意一台 Windows 10/11。
不需要 Python、不需要 Node、不需要管理员权限。

## 它是怎么工作的

```
网盘页面（LinkSwift 用户脚本）  --HTTP POST-->  AB Download Manager (127.0.0.1:15151)
        抓直链 / 带 Cookie UA              多线程下载到本地目录
```

本仓库提供的是**把两边接起来的那一层**：

1. `setup.bat` 静默安装 AB Download Manager，并写好配置（端口 15151、API 密钥、下载目录）
2. 起一个**只监听 127.0.0.1** 的迷你安装向导（纯 PowerShell，用 TcpListener 手写 HTTP），
   把 `.user.js` 用 `text/javascript` 托管出去，脚本管理器（脚本猫 / 篡改猴）会自动弹安装框
3. 向导页面实时显示四盏状态灯：下载器是否安装、服务是否监听、配置是否就绪、脚本是否就位，
   并自动检测 Edge / Chrome 各 profile 里有没有装脚本管理器

## 快速开始

```
双击 setup.bat
```

然后照浏览器里弹出的向导页点两下即可。详细步骤、参数、常见问题见 `先看我_安装说明.txt`。

## 目录

| 路径 | 作用 |
| --- | --- |
| `setup.bat` | 唯一入口：装下载器 → 起向导 → 开网页 |
| `install.ps1` | ABDM 安装与配置（支持 `-SelfTest` 只检查不改动） |
| `tools/guide-server.ps1` | 本地安装向导服务（127.0.0.1:18080） |
| `tools/appSettings.template.json` | ABDM 1.11.4 配置模板（首次运行兜底） |
| `tools/categories.template.json` | 分类目录模板 |
| `script/linkswift-abdm-v3.user.js` | LinkSwift 的 ABDM 密钥补丁版用户脚本 |
| `installer/` | ABDM 安装包（仓库里不含，`install.ps1` 会按需下载） |

## 为什么要本地 HTTP 服务

浏览器扩展没法从命令行静默安装，`.user.js` 也只能由脚本管理器在**网页响应**里拦截——
`file://` 打开本地文件通常不触发安装 UI。所以最省事的做法就是本地起一个 HTTP 服务，
把脚本以正确的 MIME 类型吐出去，点一下就走完官方安装流程。

服务只绑回环地址，页面里点「关闭向导服务」即可退出。

## 已知限制

- 只在 Windows 上验证过（Windows PowerShell 5.1 / Win11）
- ABDM 的 `autoStartOnBoot` 配置项在 1.11.4 上不会真正注册自启，`install.ps1` 会补写
  `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`
- 端口 15151 被占用时需要同步改配置与脚本设置

## 来源

- [LinkSwift](https://github.com/hmjz100/LinkSwift) — hmjz100 / 油小猴，AGPL-3.0
- [AB Download Manager](https://github.com/amir1376/ab-download-manager) — amir1376

本仓库只是把两者接起来的自用整合脚本，不含上述项目的源码修改。
