# Agent Execution Guidelines & Constraints

## 1. 严格禁止本地编译与构建 (Strict No-Build Rule)
- **禁止在本地终端执行任何形式的编译、镜像构建或高负载打包命令**。
  - 禁止命令包括但不限于：`go build`、`go install`、`docker build`、`mvn package`、`cargo build`、`npm run build` 等。
- 本地机器硬件配置极低（1 vCPU / <1GB RAM），本地编译会导致主机 OOM 崩溃及服务中断。

## 2. 规范工作流：远程 CI/CD 驱动 (Remote CI/CD Workflow)
- **代码交付**：本地环境仅用于源码编写、阅读、静态语法检查（Linter）与轻量单元修改。
- **触发构建**：若需要验证构建结果或生成制品，必须：
  1. 提交代码变更并推送到远端仓库分支（`git push origin `）。
  2. 触发远程流水线（如 GitHub Actions、GitLab CI）。
  3. 通过 CLI（如 `gh run view`）或 Webhook 检查远程构建状态。
  4. 所有编译在github上完成
  5. 请注意代码规范，使用工业化的方案解决，不要投机取消
  6. 请记住以下的全局变量，使用相同的脚本名打包你要执行的命令不要使用传参执行脚本，我不想一直授权，另外我不在中国大陆，没有网络问题。
  7. 各种功能不要配一些很low的说明文字，全站不能有任何中文。
  8. 做项目汇报和交流的时候使用中文
- **二进制分发**：需要本地运行时，直接从 CI 制品库（Artifacts/Releases）拉取预编译产物，严禁就地重新构建。

