#!/usr/bin/env bash
# scripts/antigravity-sync.sh
# 
# 自动备份与恢复 Antigravity IDE 局部的 planning artifacts。
# 支持全自动自适应寻址（缺省参数时自动匹配最新会话及最新 Session）。
#
# 用法:
#   bash scripts/antigravity-sync.sh backup [session_ulid] [app_data_dir] [conversation_id]
#   bash scripts/antigravity-sync.sh restore [session_ulid] [app_data_dir] [conversation_id]

set -euo pipefail

MODE="${1:-}"
ULID="${2:-}"
APP_DATA_DIR="${3:-}"
CONV_ID="${4:-}"

if [[ -z "$MODE" ]]; then
  echo "错误: 必须指定运行模式 backup 或 restore。"
  echo "用法: $0 <backup|restore> [session_ulid] [app_data_dir] [conversation_id]"
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. 自动探测 APP_DATA_DIR
if [[ -z "$APP_DATA_DIR" ]]; then
  DEFAULT_PATH="${HOME}/.gemini/antigravity-ide"
  if [[ -d "$DEFAULT_PATH" ]]; then
    APP_DATA_DIR="$DEFAULT_PATH"
  else
    # 尝试在 ~/.gemini 下模糊寻找包含 antigravity 的目录
    FOUND=$(find "${HOME}/.gemini" -maxdepth 2 -type d -name "*antigravity*" 2>/dev/null | head -n 1 || true)
    if [[ -n "$FOUND" ]]; then
      APP_DATA_DIR="$FOUND"
    else
      echo "错误: 自动探测 App Data 目录失败。请显式提供第二个参数。"
      exit 1
    fi
  fi
  echo "[antigravity-sync] 自动探测到 App Data 目录: $APP_DATA_DIR"
fi

# 2. 自动探测 CONV_ID
if [[ -z "$CONV_ID" ]]; then
  BRAIN_DIR="${APP_DATA_DIR}/brain"
  if [[ ! -d "$BRAIN_DIR" ]]; then
    echo "错误: 自动探测会话 ID 失败，脑数据目录不存在: $BRAIN_DIR"
    exit 1
  fi
  # 寻找最新修改的会话目录（ls -td 按修改时间由新到旧排序）
  LATEST_CONV=$(ls -td "${BRAIN_DIR}"/*/ 2>/dev/null | head -n 1 || true)
  if [[ -n "$LATEST_CONV" ]]; then
    CONV_ID=$(basename "$LATEST_CONV")
    echo "[antigravity-sync] 自动探测到最新的 Conversation ID: $CONV_ID"
  else
    echo "错误: 脑数据目录为空，自动探测会话 ID 失败。"
    exit 1
  fi
fi

# 3. 自动探测 ULID
if [[ -z "$ULID" || "$ULID" == "latest" ]]; then
  SESSIONS_DIR="${PROJECT_ROOT}/.agent/sessions"
  if [[ -d "$SESSIONS_DIR" ]]; then
    # 寻找修改时间最新的子目录，并排除 _archive 目录
    LATEST_DIR=$(ls -td "${SESSIONS_DIR}"/*/ 2>/dev/null | grep -v "_archive" | head -n 1 || true)
    if [[ -n "$LATEST_DIR" ]]; then
      ULID=$(basename "$LATEST_DIR")
      echo "[antigravity-sync] 自动探测到最新的 Session ULID: $ULID"
    fi
  fi
  if [[ -z "$ULID" ]]; then
    echo "错误: 未检测到任何已有的 Session，自动探测 ULID 失败。请显式提供第一个参数。"
    exit 1
  fi
fi

LOCAL_BRAIN_DIR="${APP_DATA_DIR}/brain/${CONV_ID}"
REPO_SESSION_DIR="${PROJECT_ROOT}/.agent/sessions/${ULID}/antigravity"

backup_files() {
  echo "[antigravity-sync] 开始备份局部规划文件至仓库..."
  if [[ ! -d "$LOCAL_BRAIN_DIR" ]]; then
    echo "警告: 本地会话目录不存在: $LOCAL_BRAIN_DIR，跳过备份。"
    exit 0
  fi

  mkdir -p "$REPO_SESSION_DIR"
  
  local count=0
  for f in "implementation_plan.md" "task.md" "walkthrough.md"; do
    if [[ -f "${LOCAL_BRAIN_DIR}/${f}" ]]; then
      cp "${LOCAL_BRAIN_DIR}/${f}" "${REPO_SESSION_DIR}/${f}"
      echo "  备份: ${f} -> .agent/sessions/${ULID}/antigravity/${f}"
      count=$((count+1))
    fi
  done
  echo "[antigravity-sync] 备份完成，共备份了 ${count} 个文件。"
}

restore_files() {
  echo "[antigravity-sync] 开始从仓库恢复规划文件至本地会话..."
  if [[ ! -d "$REPO_SESSION_DIR" ]]; then
    echo "警告: 仓库中无该会话的 Antigravity 备份目录: .agent/sessions/${ULID}/antigravity"
    exit 0
  fi

  mkdir -p "$LOCAL_BRAIN_DIR"

  local count=0
  for f in "implementation_plan.md" "task.md" "walkthrough.md"; do
    if [[ -f "${REPO_SESSION_DIR}/${f}" ]]; then
      # 如果本地已存在，先做个备份，防止意外覆盖用户在新会话里写的重要内容
      if [[ -f "${LOCAL_BRAIN_DIR}/${f}" ]]; then
        mv "${LOCAL_BRAIN_DIR}/${f}" "${LOCAL_BRAIN_DIR}/${f}.bak"
        echo "  本地已有 ${f}，已重命名为 ${f}.bak"
      fi
      cp "${REPO_SESSION_DIR}/${f}" "${LOCAL_BRAIN_DIR}/${f}"
      echo "  恢复: .agent/sessions/${ULID}/antigravity/${f} -> ${LOCAL_BRAIN_DIR}/${f}"
      count=$((count+1))
    fi
  done
  echo "[antigravity-sync] 恢复完成，共恢复了 ${count} 个文件。"
}

case "$MODE" in
  backup)
    backup_files
    ;;
  restore)
    restore_files
    ;;
  *)
    echo "错误: 未知模式: $MODE (必须 be backup 或者是 restore)"
    exit 1
    ;;
esac
