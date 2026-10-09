#!/usr/bin/env python3
"""Lists localization keys used in Swift sources (keys look like `area.name`, possibly with interpolations).

Interpolations `\\(expr)` become `%@`/`%lld` placeholders in String Catalog keys; this script normalizes them
to `%` so keys can be compared regardless of argument types.
"""
import os, re, sys

ROOTS = sys.argv[1:] or ["App", "Widget"]
PATTERNS = [
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'Text\(\s*"((?:[^"\\]|\\.)*)"',
    r'LocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"',
    r'(?:Label|Button|Section|Toggle|Picker|navigationTitle)\(\s*"((?:[^"\\]|\\.)*)"',
    r'(?:title|tag|text|label):\s*"((?:[^"\\]|\\.)*)"',
    r'return\s+"((?:[^"\\]|\\.)*)"',
    r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"',
]
KEY = re.compile(r'^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+( .*)?$')

def normalize(k):
    k = re.sub(r'\\\((?:[^()]|\([^()]*\))*\)', '%', k)
    return k

def keys():
    out = {}
    for root in ROOTS:
        for dirpath, _, files in os.walk(root):
            for f in files:
                if not f.endswith(".swift"): continue
                p = os.path.join(dirpath, f)
                src = open(p, encoding="utf-8").read()
                for pat in PATTERNS:
                    for m in re.finditer(pat, src):
                        for g in m.groups():
                            if g and KEY.match(g) and "verbatim" not in src[max(0, m.start()-12):m.start()]:
                                out.setdefault(normalize(g), set()).add(p)
    return out

if __name__ == "__main__":
    for k in sorted(keys()):
        print(k)
