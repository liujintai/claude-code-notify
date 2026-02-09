#!/usr/bin/env python3
"""
Claude Code Stop Hook - 智能通知摘要
当 Claude Code 完成回复时，提取用户问题和 AI 回答，
调用 Haiku 生成简短摘要，通过桌面通知展示。
"""

import json
import os
import subprocess
import sys
import time
import traceback
import urllib.request

# ============================================================
# 配置
# ============================================================
DEBUG = os.environ.get("NOTIFY_DEBUG", "0") == "1"
LOG_PATH = os.path.expanduser("~/.claude/notify_debug.log")
LOG_MAX_SIZE = 50 * 1024  # 50KB
HAIKU_MODEL = "claude-haiku-4-5-20251001"
HAIKU_TIMEOUT = 10
HAIKU_MAX_RETRIES = 3
CONTENT_MAX_CHARS = 1500  # 发送给 Haiku 的最大字符数


# ============================================================
# 日志
# ============================================================
def log(msg: str):
    """调试日志（仅 NOTIFY_DEBUG=1 时启用）"""
    if not DEBUG:
        return
    try:
        if os.path.isfile(LOG_PATH) and os.path.getsize(LOG_PATH) > LOG_MAX_SIZE:
            with open(LOG_PATH, "r") as f:
                lines = f.readlines()
            with open(LOG_PATH, "w") as f:
                f.writelines(lines[-100:])
    except Exception:
        pass
    with open(LOG_PATH, "a") as f:
        f.write(msg + "\n")


# ============================================================
# 通知
# ============================================================
NOTIFY_APP = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "ClaudeNotify.app", "Contents", "MacOS", "ClaudeNotify",
)


def send_notification(title: str, message: str):
    """发送 macOS / Linux 桌面通知"""
    message = message.replace("\n", " ")
    if sys.platform == "darwin" and os.path.isfile(NOTIFY_APP):
        subprocess.run(
            [NOTIFY_APP, "-title", title, "-message", message],
            capture_output=True,
            timeout=10,
        )
    elif sys.platform == "darwin":
        # 回退到 osascript
        msg = message.replace('"', '\\"')
        ttl = title.replace('"', '\\"')
        subprocess.run(
            ["osascript", "-e",
             f'display notification "{msg}" with title "{ttl}"'],
            capture_output=True,
        )
    else:
        subprocess.run(
            ["notify-send", title, message],
            capture_output=True,
        )


# ============================================================
# Transcript 内容提取
# ============================================================
def _extract_text_from_entry(data: dict) -> str:
    """从单条 transcript 记录中提取纯文本"""
    msg = data.get("message", {})
    content = msg.get("content", [])
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        texts = []
        for c in content:
            if c.get("type") == "text":
                t = c.get("text")
                if isinstance(t, str) and t.strip():
                    texts.append(t)
        return "\n".join(texts)
    return ""


def _parse_entries(lines: list[str]) -> list[dict]:
    """将 JSONL 行解析为条目列表，跳过无效行"""
    entries = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return entries


def extract_conversation(hook_input: dict) -> tuple[str, str]:
    """
    从 transcript 文件中提取最后一轮对话。
    返回 (用户问题, AI回答)

    策略：先找最后一条真实用户消息，再向后查找对应的 assistant 回复。
    如果 assistant 回复尚未写入文件（竞态条件），会等待并重试。
    """
    transcript_path = hook_input.get("transcript_path", "")
    log(f"[提取] transcript_path={transcript_path}")

    if not transcript_path or not os.path.isfile(transcript_path):
        log("[提取] 文件不存在")
        return "", ""

    max_retries = 5
    retry_delay = 0.15  # 秒

    for attempt in range(max_retries):
        try:
            with open(transcript_path, "r") as f:
                lines = f.readlines()
            log(f"[提取] 总行数={len(lines)} (尝试 {attempt + 1}/{max_retries})")
        except Exception as e:
            log(f"[提取] 读取文件异常: {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
                continue
            return "", ""

        entries = _parse_entries(lines)

        # 1) 反向查找最后一条有文本的真实用户消息（跳过 tool_result）
        last_user_idx = -1
        user_text = ""
        for i in range(len(entries) - 1, -1, -1):
            if entries[i].get("type") == "user":
                text = _extract_text_from_entry(entries[i])
                if text:
                    last_user_idx = i
                    user_text = text
                    break

        if last_user_idx < 0:
            log("[提取] 未找到用户消息")
            return "", ""

        # 2) 从该用户消息之后，正向查找 assistant 回复（取最后一条有文本的）
        assistant_text = ""
        for i in range(last_user_idx + 1, len(entries)):
            if entries[i].get("type") == "assistant":
                text = _extract_text_from_entry(entries[i])
                if text:
                    assistant_text = text

        if assistant_text:
            log(f"[提取] user长度={len(user_text)}, assistant长度={len(assistant_text)}")
            return user_text, assistant_text

        # 未找到 assistant 回复 → 文件可能尚未写入完成，等待后重试
        log(f"[提取] 找到用户消息但未找到助手回复，等待重试 (尝试 {attempt + 1}/{max_retries})")
        if attempt < max_retries - 1:
            time.sleep(retry_delay)

    # 所有重试都失败，返回用户消息但助手回复为空
    # （不回退到反向扫描，避免错误匹配到上一轮对话）
    log(f"[提取] 重试耗尽，未找到助手回复 user长度={len(user_text)}")
    return user_text, ""


# ============================================================
# Haiku 摘要
# ============================================================
SUMMARY_PROMPT = """你是一个通知摘要生成器。根据用户的问题和AI助手的回答，用10个中文字以内概括本次交互的结果状态。

规则：
1. 只输出概括文字，不要任何其他内容
2. 要体现"做了什么"和"结果如何"
3. 参考示例：代码编写完成、Bug已修复、技术方案已完成、等待您的确认、文件修改完成、问题分析完成、部署脚本已更新

用户问题：
{user}

AI回答：
{assistant}"""


def summarize_with_haiku(user_text: str, assistant_text: str) -> str:
    """调用 Haiku 生成摘要，带重试"""
    base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
    api_key = (
        os.environ.get("ANTHROPIC_AUTH_TOKEN")
        or os.environ.get("ANTHROPIC_API_KEY", "")
    )

    if not api_key:
        log("[API] 未找到 API Key")
        return "任务已完成"

    # 构造上下文，控制总长度
    user_part = user_text[:500] if user_text else "(无)"
    assistant_part = assistant_text[: CONTENT_MAX_CHARS - len(user_part)]
    prompt_text = SUMMARY_PROMPT.format(user=user_part, assistant=assistant_part)

    log(f"[输入] 用户问题: {user_part}")
    log(f"[输入] AI回答: {assistant_part}")

    url = f"{base_url}/v1/messages"
    payload_dict = {
        "model": HAIKU_MODEL,
        "max_tokens": 60,
        "messages": [{"role": "user", "content": prompt_text}],
    }
    payload = json.dumps(payload_dict).encode("utf-8")

    for attempt in range(HAIKU_MAX_RETRIES):
        try:
            req = urllib.request.Request(
                url,
                data=payload,
                headers={
                    "x-api-key": api_key,
                    "content-type": "application/json",
                    "anthropic-version": "2023-06-01",
                },
            )
            with urllib.request.urlopen(req, timeout=HAIKU_TIMEOUT) as resp:
                raw_body = resp.read().decode("utf-8")
                result = json.loads(raw_body)
                summary = result["content"][0]["text"].strip()
                log(f"[输出] Haiku返回: {summary}")
                return summary
        except urllib.error.HTTPError as e:
            err_body = ""
            try:
                err_body = e.read().decode("utf-8")
            except Exception:
                pass
            log(f"[错误] HTTP {e.code}: {err_body[:200]}" if err_body else f"[错误] HTTP {e.code}: {e.reason}")
            if attempt < HAIKU_MAX_RETRIES - 1:
                time.sleep(1)
        except Exception as e:
            log(f"[错误] {type(e).__name__}: {e}")
            if attempt < HAIKU_MAX_RETRIES - 1:
                time.sleep(1)

    return "任务已完成"


# ============================================================
# 主入口
# ============================================================
def main():
    log("=" * 50)
    log("[开始] Stop hook 触发")

    # 读取 stdin
    try:
        raw = sys.stdin.read()
        hook_input = json.loads(raw) if raw.strip() else {}
        log(f"[stdin] 键: {list(hook_input.keys())}")
    except Exception as e:
        log(f"[stdin] 解析失败: {e}")
        hook_input = {}

    # 提取最后一轮对话
    user_text, assistant_text = extract_conversation(hook_input)

    # 生成摘要
    if assistant_text:
        summary = summarize_with_haiku(user_text, assistant_text)
    else:
        summary = "任务已完成"

    log(f"[通知] {summary}")
    send_notification("Claude Code", summary)
    log("[完成]")


if __name__ == "__main__":
    main()
