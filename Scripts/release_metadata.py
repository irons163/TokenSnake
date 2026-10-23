#!/usr/bin/env python3
"""Validate release tags against the generated Xcode project without extra dependencies."""
import argparse
import json
import re
from pathlib import Path

VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
TAG = re.compile(rf"[vV]?({VERSION})(-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?")


def resolve(project_text, tag="", prerelease=False):
    def setting(name):
        values = {value.strip().strip('"') for value in re.findall(
            rf"^\s*{name}\s*=\s*([^;\n]+);", project_text, re.MULTILINE)}
        if len(values) != 1:
            raise ValueError(f"Expected one consistent {name} across build configurations")
        return values.pop()

    marketing = setting("MARKETING_VERSION")
    build = setting("CURRENT_PROJECT_VERSION")
    if not re.fullmatch(VERSION, marketing) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", build):
        raise ValueError("Invalid marketing version or build number")
    version = marketing
    if tag:
        match = TAG.fullmatch(tag)
        if not match or match[1] != marketing:
            raise ValueError("Release tag must match MARKETING_VERSION (for example v1.3.0)")
        if match[2] and not prerelease:
            raise ValueError("A prerelease tag requires the GitHub Release prerelease flag")
        version = match[1] + (match[2] or "")
    return {"version": version, "marketing_version": marketing, "build_number": build}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path("TokenSnake.xcodeproj/project.pbxproj"))
    parser.add_argument("--tag", default="")
    parser.add_argument("--prerelease", choices=["true", "false"], default="false")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--field", choices=["version", "marketing_version", "build_number"])
    args = parser.parse_args()
    try:
        result = resolve(args.project.read_text(), args.tag, args.prerelease == "true")
    except (ValueError, OSError) as error:
        parser.exit(1, f"Release validation failed: {error}\n")
    if args.github_output:
        with args.github_output.open("a") as output:
            for key, value in result.items():
                output.write(f"{key}={value}\n")
    print(result[args.field] if args.field else json.dumps(result))


if __name__ == "__main__":
    main()
