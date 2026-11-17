#!/usr/bin/env python3
"""Build and execute common PIC workloads; fail on any sink mismatch."""
import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NAMES = ("sensor", "buttons", "frames", "display")
DEVICES = ("16F18346", "18F27Q10")


def run(command, cwd=None):
    result = subprocess.run([str(x) for x in command], cwd=cwd, text=True,
                            capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, command))}\n{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def simulate(args, image, listing, device, symbol, until, expected):
    output = run([args.sim, image, "--device", device, "--asm", listing,
                  "--until", until, "--dump", f"{symbol}:4", "--max-cycles", "10000000"])
    stopped = re.search(r"stop: Halt\s+cycles: (\d+)", output)
    value = re.search(rf"^{symbol} = (\d+)", output, re.M)
    if not stopped or not value or int(value[1]) != expected:
        raise RuntimeError(f"{device} {image.name}: expected sink={expected}\n{output}")
    return int(stopped[1])


def basil(args, directory, name, device, expected, unoptimized):
    text = (HERE / f"{name}.bas").read_text()
    text = text.replace("18F27Q10", device)
    if device.startswith("16"):
        text = text.replace("Clock = 64", "Clock = 32").replace("HFINTOSC_64MHZ", "HFINT32")
    source = directory / f"{name}.bas"
    source.write_text(text)
    image = source.with_suffix(".hex")
    flags = ["-O0"] if unoptimized else []
    report = run([args.basil, *flags, "--report", source, "-o", image])
    words = int(re.search(r"Program: (\d+) words", report)[1])
    ram = int(re.search(r"total (\d+) bytes", report)[1])
    cycles = simulate(args, image, source.with_suffix(".S"), device, "K_SINK", "__halt", expected)
    return words * 2, ram, cycles


def xc8(args, directory, name, device, expected, opt):
    pack = "PIC16F1xxxx_DFP" if device.startswith("16") else "PIC18F-Q_DFP"
    packs = list((Path.home() / ".mchp_packs/Microchip" / pack).glob("*/xc8"))
    if not packs:
        raise RuntimeError(f"No installed {pack} device pack")
    dfp = max(packs, key=lambda p: tuple(int(n) for n in p.parent.name.split('.')))
    image = directory / f"{name}.elf"
    flags = ["-DBENCH_PIC16"] if device.startswith("16") else []
    report = run([args.xc8_cc, f"-mcpu={device}", f"-mdfp={dfp}", opt, "-std=c99",
                  "-mno-default-config-bits", *flags, "-o", image, HERE / f"{name}.c"], cwd=directory)
    program = re.search(r"Program space\s+used\s+\w+h\s+\(\s*(\d+)\)\s+of\s+\w+h\s+(words|bytes)", report)
    if not program:
        raise RuntimeError(f"Cannot read XC8 memory summary:\n{report}")
    flash = int(program[1]) * (2 if program[2] == "words" else 1)
    ram = int(re.search(r"Data space\s+used\s+\w+h\s+\(\s*(\d+)\)", report)[1])
    # XC8's linker symbol file uses PIC16 word / PIC18 byte code addresses.
    symbols = dict(re.findall(r"^(\S+) ([0-9A-Fa-f]+) \S+ \S+ \S+", image.with_suffix(".sym").read_text(), re.M))
    listing = directory / f"{name}.S"
    listing.write_text(f";SYM bench_done 0x{symbols['bench_done']}\nC_SINK equ 0x{symbols['_sink']}\n")
    cycles = simulate(args, image.with_suffix(".hex"), listing, device, "C_SINK", "bench_done", expected)
    return flash, ram, cycles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="workload names (default: all four)")
    parser.add_argument("--device", choices=DEVICES, action="append", help="repeat for both; default: both")
    parser.add_argument("--basil", type=Path, default=ROOT / "target/release/basil")
    parser.add_argument("--sim", type=Path, default=ROOT.parent / "picsim/target/release/basil-sim")
    parser.add_argument("--cc", default="cc", help="host C compiler for the reference result")
    parser.add_argument("--o0", action="store_true", help="also verify and report BASIC -O0")
    parser.add_argument("--xc8", action="store_true", help="also build and simulate XC8 -Os and -O2")
    parser.add_argument("--xc8-cc", default="xc8-cc")
    args = parser.parse_args()
    names = args.names or list(NAMES)
    if set(names) - set(NAMES):
        parser.error(f"choose workloads from {', '.join(NAMES)}")
    args.basil = args.basil.resolve()
    args.sim = args.sim.resolve()
    for executable in [args.basil, args.sim, args.cc] + ([args.xc8_cc] if args.xc8 else []):
        if not shutil.which(str(executable)):
            parser.error(f"executable not found: {executable}")
    rows = []
    with tempfile.TemporaryDirectory(prefix="pic-embedded-bench-") as temp:
        work = Path(temp)
        for name in names:
            host = work / name
            run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-O2", "-DHOST_BENCH",
                 HERE / f"{name}.c", "-o", host])
            expected = int(run([host]).strip())
            declared = int(re.search(r"^' expect: K_SINK=(\d+)", (HERE / f"{name}.bas").read_text())[1])
            if declared != expected:
                raise RuntimeError(f"{name}: C reference={expected}, BASIC expectation={declared}")
            for device in args.device or DEVICES:
                builds = [("BASIC", False)] + ([("BASIC -O0", True)] if args.o0 else [])
                for label, unoptimized in builds:
                    directory = work / device / name / label.replace(' ', '_')
                    directory.mkdir(parents=True)
                    rows.append((device, name, label, *basil(args, directory, name, device, expected, unoptimized), expected))
                if args.xc8:
                    for opt in ("-Os", "-O2"):
                        directory = work / device / name / opt
                        directory.mkdir(parents=True)
                        rows.append((device, name, f"XC8 {opt}", *xc8(args, directory, name, device, expected, opt), expected))
    print("| Device | Workload | Build | Flash B | RAM B | Cycles | Sink |")
    print("| --- | --- | --- | ---: | ---: | ---: | ---: |")
    for row in rows:
        print("| " + " | ".join(map(str, row)) + " |")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
