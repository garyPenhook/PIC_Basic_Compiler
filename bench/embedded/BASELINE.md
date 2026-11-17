# Initial embedded application baseline — 2026-11-17

Basil 0.1.259 (compiler commit `563f46e`), XC8 v4.00, basil-sim.
PIC16F1xxxx_DFP 1.32.471; PIC18F-Q_DFP 1.31.492.
Command: `python3 bench/embedded/run.py --o0 --xc8`.
All 32 runs reached their end marker with the host C reference sink.
See [README.md](README.md) for workload definitions and measurement boundaries.

| Device | Workload | Build | Flash B | RAM B | Cycles | Sink |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 16F18346 | sensor | BASIC | 602 | 31 | 103234 | 167716 |
| 16F18346 | sensor | BASIC -O0 | 658 | 31 | 107426 | 167716 |
| 16F18346 | sensor | XC8 -Os | 668 | 52 | 91339 | 167716 |
| 16F18346 | sensor | XC8 -O2 | 748 | 52 | 114261 | 167716 |
| 18F27Q10 | sensor | BASIC | 444 | 30 | 82556 | 167716 |
| 18F27Q10 | sensor | BASIC -O0 | 554 | 30 | 92067 | 167716 |
| 18F27Q10 | sensor | XC8 -Os | 558 | 46 | 86127 | 167716 |
| 18F27Q10 | sensor | XC8 -O2 | 606 | 46 | 89723 | 167716 |
| 16F18346 | buttons | BASIC | 606 | 40 | 150342 | 2652 |
| 16F18346 | buttons | BASIC -O0 | 716 | 36 | 149799 | 2652 |
| 16F18346 | buttons | XC8 -Os | 556 | 42 | 111647 | 2652 |
| 16F18346 | buttons | XC8 -O2 | 614 | 42 | 116396 | 2652 |
| 18F27Q10 | buttons | BASIC | 466 | 23 | 109018 | 2652 |
| 18F27Q10 | buttons | BASIC -O0 | 512 | 27 | 87951 | 2652 |
| 18F27Q10 | buttons | XC8 -Os | 460 | 36 | 101252 | 2652 |
| 18F27Q10 | buttons | XC8 -O2 | 534 | 36 | 90912 | 2652 |
| 16F18346 | frames | BASIC | 492 | 37 | 45905 | 22784 |
| 16F18346 | frames | BASIC -O0 | 602 | 38 | 52781 | 22784 |
| 16F18346 | frames | XC8 -Os | 502 | 42 | 47761 | 22784 |
| 16F18346 | frames | XC8 -O2 | 578 | 46 | 49102 | 22784 |
| 18F27Q10 | frames | BASIC | 338 | 24 | 41946 | 22784 |
| 18F27Q10 | frames | BASIC -O0 | 512 | 29 | 55161 | 22784 |
| 18F27Q10 | frames | XC8 -Os | 426 | 36 | 43472 | 22784 |
| 18F27Q10 | frames | XC8 -O2 | 490 | 40 | 47233 | 22784 |
| 16F18346 | display | BASIC | 722 | 50 | 909672 | 474523 |
| 16F18346 | display | BASIC -O0 | 778 | 50 | 924134 | 474523 |
| 16F18346 | display | XC8 -Os | 786 | 59 | 494022 | 474523 |
| 16F18346 | display | XC8 -O2 | 980 | 63 | 680192 | 474523 |
| 18F27Q10 | display | BASIC | 602 | 46 | 295472 | 474523 |
| 18F27Q10 | display | BASIC -O0 | 858 | 46 | 562837 | 474523 |
| 18F27Q10 | display | XC8 -Os | 716 | 63 | 429805 | 474523 |
| 18F27Q10 | display | XC8 -O2 | 794 | 63 | 443551 | 474523 |
