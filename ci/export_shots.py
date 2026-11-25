"""Export named iPhone attachments from the Xcode test result."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r"^(store-(?:zh-Hans|zh-Hant|en)-\d{2}-[a-z-]+|paid-01-paywall)(?=[_.]|$)")


def copy_named(source_dir, output):
    manifest = json.loads((source_dir / "manifest.json").read_text(encoding="utf-8"))
    written = set()
    for test in manifest:
        for attachment in test["attachments"]:
            match = NAME.match(attachment.get("suggestedHumanReadableName", ""))
            source = source_dir / attachment["exportedFileName"]
            if match and source.suffix.lower() == ".png":
                stem = match[1]
                shutil.copyfile(source, output / (stem + ".png"))
                written.add(stem)
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output, prefix="xcresult-") as directory:
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", args.result,
                        "--output-path", directory], check=True)
        names = copy_named(Path(directory), output)
    config = json.loads((ROOT / "上架资料/商店截图.json").read_text(encoding="utf-8"))
    required = {"paid-01-paywall"}
    required.update(f"store-{language}-{page['shot']}"
                    for language in ("en", "zh-Hans", "zh-Hant") for page in config["pages"])
    if required - names:
        parser.exit(1, "本次测试缺少截图：" + "、".join(sorted(required - names)) + "\n")
    review = ROOT / "上架资料/截图/zh-Hans/paywall.png"
    review.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(output / "paid-01-paywall.png", review)
    print(f"已导出 {len(names)} 张命名截图；审核图已写入 {review}")


if __name__ == "__main__":
    main()
