#!/usr/bin/env python3
"""Generate an AXI4 checker set with ANY LLM behind an OpenAI-compatible chat API.

    export LLM_API_KEY=...
    python3 tools/gen_checker.py --name my_deepseek \\
        --base-url https://api.deepseek.com/v1 --model deepseek-chat \\
        --spec IHI0022L.txt

Works with any endpoint that speaks POST {base-url}/chat/completions, e.g. DeepSeek,
Qwen (DashScope compatible mode), Kimi, GLM, OpenAI, or a local Ollama/vLLM server
(--base-url http://localhost:11434/v1, no key needed). Nothing here is tied to one vendor.

The model gets exactly what every reference run got: checkers/llm_prompt/PROMPT.md, the
port list, and the spec text (chapters A1-A6 of IHI 0022 Issue L; download the PDF from
Arm and convert it with `pdftotext -layout`, it is not redistributed here). If its file
fails lint, the lint errors are sent back, up to --repairs times. Nothing else is fed back:
not the catalog, not the harness, not any result.

Output: checkers/<name>/axi_checker_set.sv plus PROVENANCE.md recording the model,
endpoint, prompt hash, lint rounds and output hash.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT_DIR = ROOT / "checkers" / "llm_prompt"
STALL_S = 600  # seconds without a single streamed byte before giving up

SYSTEM = ("You are writing SystemVerilog for a hardware verification task. Reply with the "
          "complete file in one ```systemverilog fenced block, then a short summary.")


def chat(base_url, model, key, messages, temperature):
    """One streamed chat completion. Streaming keeps the connection alive while a
    reasoning model thinks, so a slow model is never mistaken for a dead one."""
    req = urllib.request.Request(
        base_url.rstrip("/") + "/chat/completions",
        data=json.dumps({"model": model, "messages": messages, "temperature": temperature,
                         "stream": True}).encode(),
        headers={"Content-Type": "application/json", "Accept": "text/event-stream",
                 **({"Authorization": f"Bearer {key}"} if key else {})})
    parts, started = [], time.time()
    try:
        with urllib.request.urlopen(req, timeout=STALL_S) as r:
            for raw in r:
                line = raw.decode(errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                delta = json.loads(data)["choices"][0].get("delta", {})
                if delta.get("content"):
                    parts.append(delta["content"])
    except urllib.error.HTTPError as e:
        sys.exit(f"{base_url} answered HTTP {e.code}: {e.read().decode(errors='replace')[:800]}")
    except TimeoutError:
        sys.exit(f"{base_url} sent nothing for {STALL_S} s; try again or pick a faster model")
    print(f"  reply: {sum(map(len, parts))} characters in {time.time() - started:.0f} s")
    return "".join(parts)


def extract_sv(text):
    blocks = re.findall(r"```(?:systemverilog|verilog|sv)?\s*\n(.*?)```", text, re.S)
    code = max(blocks, key=len) if blocks else text
    if "module axi_checker_set" not in code:
        return None
    return code.strip() + "\n"


def lint(sv_text):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "axi_checker_set.sv"
        f.write_text(sv_text)
        p = subprocess.run(["verilator", "--lint-only", "--assert", "-Wno-fatal", "-Wno-lint",
                            "-Wno-style", "--top-module", "axi_checker_set", str(f)],
                           capture_output=True, text=True)
        errs = [l for l in (p.stdout + p.stderr).splitlines() if "%Error" in l]
        return errs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True, help="checker set name, e.g. my_qwen")
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--spec", required=True, help="spec chapters A1-A6 as plain text")
    ap.add_argument("--api-key-env", default="LLM_API_KEY")
    ap.add_argument("--repairs", type=int, default=3, help="lint-repair rounds")
    ap.add_argument("--temperature", type=float, default=0.2)
    args = ap.parse_args()

    out_dir = ROOT / "checkers" / args.name
    if out_dir.exists():
        sys.exit(f"{out_dir} already exists; pick another --name")
    prompt = (PROMPT_DIR / "PROMPT.md").read_text()
    ports = (PROMPT_DIR / "port_list.sv").read_text()
    spec = Path(args.spec).read_text(errors="replace")
    user = (f"{prompt}\n\n=== port_list.sv ===\n{ports}\n\n"
            f"=== spec/IHI0022L_partA_ch1-6.txt ===\n{spec}\n\n"
            "You cannot run lint.sh yourself; I will run it and send you any errors.")
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]
    key = os.environ.get(args.api_key_env, "")

    sv, rounds = None, 0
    for rounds in range(args.repairs + 1):
        reply = chat(args.base_url, args.model, key, messages, args.temperature)
        messages.append({"role": "assistant", "content": reply})
        sv = extract_sv(reply)
        if sv is None:
            issue = "Your reply has no module axi_checker_set. Send the complete file."
        else:
            errs = lint(sv)
            if not errs:
                break
            issue = "lint.sh reported:\n" + "\n".join(errs[:40]) + "\nSend the complete corrected file."
        print(f"round {rounds}: {issue.splitlines()[0]}")
        messages.append({"role": "user", "content": issue})
    else:
        print("still failing lint after all repair rounds; saving the last attempt anyway")

    out_dir.mkdir(parents=True)
    (out_dir / "axi_checker_set.sv").write_text(sv or "")
    (out_dir / "transcript.json").write_text(json.dumps(messages[2:], indent=1, ensure_ascii=False))
    h = hashlib.sha256((sv or "").encode()).hexdigest()[:16]
    ph = hashlib.sha256(prompt.encode()).hexdigest()[:16]
    (out_dir / "PROVENANCE.md").write_text(
        f"# Provenance\n\n| | |\n|---|---|\n| Model | `{args.model}` via `{args.base_url}` |\n"
        f"| Generated | {datetime.date.today()}, temperature {args.temperature} |\n"
        f"| Prompt | `checkers/llm_prompt/PROMPT.md` (sha256 `{ph}…`) |\n"
        f"| Lint-repair rounds | {rounds} |\n| Output | sha256 `{h}…`, unedited |\n")
    print(f"wrote {out_dir}/axi_checker_set.sv; next: python3 tools/new_checker_set.py {args.name}")


if __name__ == "__main__":
    main()
