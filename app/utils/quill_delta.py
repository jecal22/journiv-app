"""
Utilities for working with Quill Delta payloads.
"""
from __future__ import annotations

from typing import Any, Dict, Iterable, Optional


def extract_plain_text(delta: Optional[Dict[str, Any]]) -> str:
    """Extract plain text from a Quill Delta structure."""
    if not isinstance(delta, dict):
        return ""
    ops = delta.get("ops")
    if not isinstance(ops, list):
        return ""
    parts: list[str] = []
    for op in ops:
        if not isinstance(op, dict):
            continue
        insert = op.get("insert")
        if isinstance(insert, str):
            parts.append(insert)
    return "".join(parts)


def wrap_plain_text(text: Optional[str]) -> Dict[str, Any]:
    """Wrap plain text into a minimal Quill Delta structure."""
    safe_text = text or ""
    return {"ops": [{"insert": safe_text}]} if safe_text else {"ops": []}


def replace_media_ids(
    delta: Optional[Dict[str, Any]],
    id_map: Dict[str, str],
) -> Dict[str, Any]:
    """Replace media IDs inside image/video embeds."""
    if not isinstance(delta, dict):
        return {"ops": []}
    ops = delta.get("ops")
    if not isinstance(ops, list):
        return {"ops": []}

    updated_ops: list[Dict[str, Any]] = []
    for op in ops:
        if not isinstance(op, dict):
            updated_ops.append(op)
            continue
        insert = op.get("insert")
        if isinstance(insert, dict):
            updated_insert = dict(insert)
            # Replace IDs
            for key in ("image", "video", "audio"):
                value = updated_insert.get(key)
                if isinstance(value, str) and value in id_map:
                    updated_insert[key] = id_map[value]

            # Sanitize: ensure only one key remains to satisfy Quill strictness
            if len(updated_insert) > 1:
                # Priority: image > video > audio
                sanitized = {}
                found = False
                for key in ("image", "video", "audio"):
                    if key in updated_insert:
                        sanitized[key] = updated_insert[key]
                        found = True
                        break

                if found:
                    updated_insert = sanitized
                # If no media key found but multiple keys exist, leave as is
                # (or could pick first, but safer to leave non-media embeds alone for now)

            updated_op = dict(op)
            updated_op["insert"] = updated_insert
            updated_ops.append(updated_op)
        else:
            updated_ops.append(op)

    return {"ops": updated_ops}

