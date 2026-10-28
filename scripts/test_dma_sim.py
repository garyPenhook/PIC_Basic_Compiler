#!/usr/bin/env python3
"""Checks of the DMA engine model in dma_sim.py against DS40002214G chapter 16, with no MDB involved.

Run: python3 scripts/test_dma_sim.py
"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
from dma_sim import Engine

NO_STOP, SSTP, DSTP = 0, 1, 32


class Bus:
    def __init__(self):
        self.mem = {"r": {}, "p": {}, "e": {}}
        self.out = {}
        self.flags = []

    def read(self, space, addr):
        return self.mem[space].get(addr, 0)

    def write(self, addr, val):
        self.out.setdefault(addr, []).append(val)

    def flag(self, name):
        self.flags.append(name)


def config(e, n=0, ssa=0x100, ssz=1, dsa=0x200, dsz=1, con1=0x42, sirq=0, airq=0):
    e.load_config(n, dict(ssa=ssa, ssz=ssz, dsa=dsa, dsz=dsz, con1=con1, sirq=sirq, airq=airq))


def dest(bus, base, n):
    return [bus.out.get(base + i, [None])[-1] for i in range(n)]


class DmaModel(unittest.TestCase):
    def setUp(self):
        self.bus = Bus()
        self.e = Engine(self.bus)

    def test_software_copy(self):
        for i in range(8):
            self.bus.mem["r"][0x100 + i] = 10 + i
        config(self.e, ssz=8, dsz=8)
        self.e.write_con0(0, 0x80)
        self.e.write_con0(0, 0xA0)
        self.assertEqual(dest(self.bus, 0x200, 8), list(range(10, 18)))
        c = self.e.ch[0]
        self.assertEqual((c.dgo, c.en), (0, 1))
        # both counters reloaded: the pointers are back at the start addresses [Table 16-4/16-5]
        self.assertEqual((c.sptr, c.dptr, c.scnt, c.dcnt), (0x100, 0x200, 8, 8))
        self.assertEqual(self.bus.flags, ["DMA1SCNTIF", "DMA1DCNTIF"])

    def test_two_sizes_make_messages(self):
        # [16.3.3] destination size 6, source size 2: three messages of two transactions
        self.bus.mem["r"].update({0x100: 1, 0x101: 2})
        e = self.e
        config(e, ssz=2, dsz=6, con1=0x42 | 0x00, sirq=33)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xC0)  # SIRQEN
        e.request(0)
        self.assertEqual(dest(self.bus, 0x200, 6), [1, 2, None, None, None, None])
        self.assertEqual(e.ch[0].dgo, 0)
        e.request(0, 2)
        self.assertEqual(dest(self.bus, 0x200, 6), [1, 2, 1, 2, 1, 2])
        self.assertEqual((e.ch[0].dptr, e.ch[0].sptr), (0x200, 0x100))

    def test_unequal_sizes_skew(self):
        # a larger count that is not a multiple of the smaller one: the last message ends early, the smaller counter keeps a remainder
        self.bus.mem["r"].update({0x100: 1, 0x101: 2, 0x102: 3})
        e = self.e
        config(e, ssz=3, dsz=4)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xC0)
        e.request(0)
        self.assertEqual(dest(self.bus, 0x200, 4), [1, 2, 3, None])
        e.request(0)
        self.assertEqual(dest(self.bus, 0x200, 4), [1, 2, 3, 1])
        self.assertEqual((e.ch[0].scnt, e.ch[0].dptr), (2, 0x200))  # the source is 1 transaction in

    def test_feed_to_fixed_register_with_stop(self):
        # memory to a transmit register, source stop: SIRQEN clears after `count` bytes [16.4.2]
        self.bus.mem["r"].update({0x100 + i: 50 + i for i in range(3)})
        e = self.e
        config(e, ssz=3, dsz=1, dsa=0x3F0, con1=0x02 | SSTP, sirq=33)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xC0)
        for _ in range(5):
            e.request(0)
        self.assertEqual(self.bus.out[0x3F0], [50, 51, 52])
        self.assertEqual(e.ch[0].sirqen, 0)
        self.assertEqual(e.ch[0].con0(), 0x80)

    def test_receive_to_buffer_with_dstp(self):
        self.bus.mem["r"][0x3F1] = 7
        e = self.e
        config(e, ssa=0x3F1, ssz=1, dsz=4, con1=0x40 | DSTP, sirq=32)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xC0)
        e.level(0)
        self.assertEqual(dest(self.bus, 0x200, 5), [7, 7, 7, 7, None])
        self.assertEqual(e.ch[0].sirqen, 0)

    def test_decrementing_pointers(self):
        self.bus.mem["r"].update({0x100: 1, 0x101: 2, 0x102: 3})
        config(self.e, ssz=3, dsz=3, con1=0x80 | 0x04)  # DMODE = 10, SMODE = 10
        self.e.write_con0(0, 0x80)
        self.e.write_con0(0, 0xA0)
        self.assertEqual([self.bus.out[a][-1] for a in (0x200, 0x1FF, 0x1FE)], [1, 0, 0])
        self.assertEqual(sorted(self.bus.out), [0x1FE, 0x1FF, 0x200])

    def test_flash_and_eeprom_sources(self):
        self.bus.mem["p"].update({0x1234: 9, 0x1235: 8})
        self.bus.mem["e"].update({4: 33, 5: 44})
        config(self.e, 0, ssa=0x1234, ssz=2, dsz=2, con1=0x40 | 0x08 | 0x02)  # SMR = 01
        config(self.e, 1, ssa=4, ssz=2, dsa=0x300, dsz=2, con1=0x40 | 0x18 | 0x02)  # SMR = 11
        for n in (0, 1):
            self.e.write_con0(n, 0x80)
            self.e.write_con0(n, 0xA0)
        self.assertEqual(dest(self.bus, 0x200, 2), [9, 8])
        self.assertEqual(dest(self.bus, 0x300, 2), [33, 44])

    def test_en_clear_is_a_hard_stop(self):
        config(self.e, ssz=4, dsz=4, sirq=5, airq=6)
        self.e.write_con0(0, 0x80)
        self.e.write_con0(0, 0xC4)
        self.e.write_con0(0, 0x00)
        c = self.e.ch[0]
        self.assertEqual((c.ssz, c.dsz, c.sirq, c.airq, c.con1, c.con0()), (0, 0, 0, 0, 0, 0))

    def test_dgo_clear_is_a_soft_stop(self):
        e = self.e
        e.slow = True
        config(e, ssz=4, dsz=4)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xA0)
        e.step(0, 2)
        e.write_con0(0, 0x80)  # DGO cleared, EN stays
        self.assertEqual((e.ch[0].scnt, e.ch[0].sptr), (2, 0x102))
        e.write_con0(0, 0xA0)  # resumes where it left off [16.3.4.2.2]
        e.step(0, 2)
        self.assertEqual((e.ch[0].dgo, e.ch[0].sptr), (0, 0x100))
        self.assertEqual(len(self.bus.out), 4)

    def test_abort(self):
        e = self.e
        e.slow = True
        config(e, ssz=8, dsz=8, sirq=1, airq=2)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xE4)  # SIRQEN, DGO, AIRQEN
        e.abort(0, after=3)
        c = e.ch[0]
        self.assertEqual((c.dgo, c.sirqen, c.airqen, c.en), (0, 0, 0, 1))
        self.assertEqual(len(self.bus.out), 3)
        self.assertIn("DMA1AIF", self.bus.flags)
        # abort needs AIRQEN
        e.write_con0(0, 0xA0)
        e.abort(0)
        self.assertEqual(c.dgo, 1)

    def test_overrun(self):
        e = self.e
        e.slow = True
        config(e, ssz=4, dsz=4, sirq=1)
        e.write_con0(0, 0x80)
        e.write_con0(0, 0xC0)
        e.request(0)  # starts, stays busy
        e.request(0)  # overrun [16.8.5]
        self.assertEqual(self.bus.flags, ["DMA1ORIF"])

    def test_priority_lock_gates_the_transfers(self):
        self.e.locked = False
        config(self.e, ssz=2, dsz=2)
        self.e.write_con0(0, 0x80)
        self.e.write_con0(0, 0xA0)
        self.assertEqual((self.bus.out, self.e.ch[0].dgo), ({}, 1))
        self.e.locked = True
        self.e.run(0)
        self.assertEqual(len(self.bus.out), 2)

    def test_channels_are_independent(self):
        config(self.e, 0, ssz=1, dsz=1, dsa=0x200)
        config(self.e, 3, ssz=1, dsz=1, dsa=0x300, ssa=0x180)
        self.bus.mem["r"].update({0x100: 5, 0x180: 6})
        for n in (0, 3):
            self.e.write_con0(n, 0x80)
            self.e.write_con0(n, 0xA0)
        self.assertEqual((self.bus.out[0x200], self.bus.out[0x300]), ([5], [6]))

    def test_no_transfer_without_sirqen(self):
        config(self.e, ssz=2, dsz=2)
        self.e.write_con0(0, 0x80)
        self.e.request(0, 3)
        self.assertEqual(self.bus.out, {})

    def test_large_message_counts_to_4095(self):
        config(self.e, ssz=4095, dsz=4095, dsa=0x400)
        self.e.write_con0(0, 0x80)
        self.e.write_con0(0, 0xA0)
        self.assertEqual(len(self.bus.out), 4095)
        self.assertEqual(self.e.ch[0].dgo, 0)


if __name__ == "__main__":
    unittest.main()
