#!/usr/bin/env python3
from __future__ import annotations

import io
import re
import tokenize
from pathlib import Path

path = Path(__file__).resolve().parent / "refine-source-runtime.py"
source = path.read_text(encoding="utf-8")
tokens = []
changed = 0

for token in tokenize.generate_tokens(io.StringIO(source).readline):
    if token.type == tokenize.STRING:
        match = re.match(r"(?is)^([rubf]*)(?:'''|\"\"\")", token.string)
        if match and "r" not in match.group(1).lower() and "\\\n" in token.string:
            fixed = token.string.replace("\\\r\n", "\\\\\r\n").replace("\\\n", "\\\\\n")
            if fixed != token.string:
                token = tokenize.TokenInfo(token.type, fixed, token.start, token.end, token.line)
                changed += 1
    tokens.append(token)

if changed == 0:
    raise SystemExit("no non-raw triple-quoted shell continuations found")

path.write_text(tokenize.untokenize(tokens), encoding="utf-8")
print(f"preserved shell continuations in {changed} refiner literal(s)")
