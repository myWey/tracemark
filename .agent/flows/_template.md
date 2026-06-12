---
id: flow-{NNN}
slug: {kebab-slug}
status: proposed
supersedes: []
superseded-by: null
epoch: epoch-0
last-confirmed: null
related-adrs: []
related-specs: []
---

# FLOW-{NNN}: {流程名}

> 一句话：用户做什么事的什么流程。

## 入口

> 用户从哪里能进入这个流程。

- {入口 1}：例如 `/login` 页"忘记密码"链接（参见 `FLOW-{XXX}`）
- {入口 2}：邮件、push、深链、外部跳转……

## 路径（步骤）

> 步骤是**用户视角**的，不是代码视角。每步对应用户能感知到的一个画面或决策点。

1. **{页面/画面 1}**——`/路径` —— 用户看到{什么}，可以做{什么}。
   - 关键交互：…
2. **{页面/画面 2}**——…
3. …

## 交互态矩阵

> 每一行 = 一个值得被 review 的画面。`visual-reviewer` 用这张表确定要截图的范围。

| 页面/组件 | 交互态 | 视觉参考 | 状态机 |
|---|---|---|---|
| {页面} | idle / loading / submitting / success / error / empty | Storybook: `path/to/story` | `flows/{slug}.machine.ts` |

## 边界条件 / 失败模式

> 哪些事必须考虑。每一条都应该有对应的测试或 PBT。

- {场景}：{应有行为}
- 失败：{API 失败 / 超时 / 网络断开 / 重复提交 / 双标签页打开 / 返回键 …}

## 引用

- **组件**：`packages/features-{x}/...`
- **API**：`shared/api-contracts/{x}.ts`
- **事件**：`shared/events/{x}.ts`
- **Schema**：`shared/schemas/{x}.ts`
- **状态机**：`packages/features-{x}/state/{name}.machine.ts`
- **Token**：相关的 semantic token 名（`color.text.primary` 等）
- **ADR**：`ADR-{nnnn}`（如有）
- **原则**：`P{n}`（如有）
- **设计稿**：Figma / 截图 / 录屏 链接

## 不在范围内（out of scope）

- {场景 1}：归到 `FLOW-{xxx}`
- {场景 2}：归到 `FLOW-{xxx}`

## 验收

> 怎么算这条 flow 真的"做对了"。

- 视觉：{交互态矩阵中所有行的 Storybook + 视觉回归通过}
- 行为：{Playwright e2e 文件}
- 不变式：{相关 PBT 文件}
- 体验：{原则 P{n} 没被违反}

## Agent 怎么用这份 flow

1. 用户口头说"FLOW-{NNN} 第 N 步交互不对"——直接定位到本文档第 N 步与对应组件/状态机。
2. 实施前：先确保引用部分都有了；缺的必须先创建/更新。
3. 实施时：每个交互态都要在 Storybook 里有 story；缺则补；补不了的列为局限并说明。
4. 完成后：`visual-reviewer` 跑这张矩阵；任何缺失的交互态本身就是 finding。
5. 流程改动后：本 flow 里"路径"小节先改，再开 spec 实施；不要先改代码再回填 flow。
