#!/usr/bin/env python3
"""Fails when a localization key used in Swift is missing from the String Catalogs (or has no Turkish),
so no screen ever shows a raw key. Runs in CI on Linux."""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
import l10n_keys  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
os.chdir(ROOT)

# SF Symbol names and other dotted literals that are not localization keys.
IGNORE = re.compile(r'^(arrow\.[\w.]+|checkmark(\.[\w.]+)?|circle\.[\w.]+|exclamationmark\.[\w.]+|hand\.[\w.]+|'
                    r'pause\.fill|play\.fill|speaker\.[\w.]+|star\.fill|lock\.fill|figure\.[\w.]+|rectangle\.[\w.]+|'
                    r'info\.circle|wifi\.slash|keystone\.network)$')


def norm_catalog_key(k):
    return re.sub(r'%(\d+\$)?(lld|ld|d|@|lf|f)', '%', k)


def load(path):
    data = json.load(open(path, encoding="utf-8"))["strings"]
    return {norm_catalog_key(k): v for k, v in data.items()}


def main():
    ok = True
    for roots, catalog in [(["App"], "App/Resources/Localizable.xcstrings"), (["Widget"], "Widget/Localizable.xcstrings")]:
        l10n_keys.ROOTS = roots
        used = {k for k in l10n_keys.keys() if not IGNORE.match(k) and "\\(" not in k}
        cat = load(catalog)
        missing = sorted(k for k in used if k not in cat)
        no_tr = sorted(k for k, v in cat.items() if "tr" not in v.get("localizations", {}))
        if missing:
            ok = False
            print(f"{catalog}: missing keys:\n  " + "\n  ".join(missing))
        if no_tr:
            ok = False
            print(f"{catalog}: missing Turkish:\n  " + "\n  ".join(no_tr))
        unused = sorted(k for k in cat if k not in used)
        if unused:
            print(f"{catalog}: unused keys (ok, but check): {', '.join(unused)}")
        print(f"{catalog}: {len(used)} keys used, {len(cat)} in catalog")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
