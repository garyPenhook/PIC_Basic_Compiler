' expect: LC_LC_IN0=1 LC_LC_IN1=1 LC_LC_BADIN0=0 LC_LC_BADIN1=0 LC_LC_A0=0 LC_LC_A1=1 LC_LC_A2=1 LC_LC_A3=1 LC_LC_A4=0 LC_LC_A5=0 LC_LC_B0=1 LC_LC_B1=1 LC_LC_B2=0 LC_LC_B3=0 LC_LC_B4=0 LC_LC_B5=1 LC_LC_OP=1 LC_LC_O2=1 LC_LC_BADO=0 LC_LC_O3=1 LC_LC_BADN=0 LC_LC_CLC8SEL3=33 LC_LC_CLC8GLS2=24 LC_LC_CLC8POL=136 LC_LC_CLC8CON=179 LC_LC_CLC8CON_OFF=19 LC_LC_RA0PPS=25 LC_LC_RB1PPS=26 LC_LC_RC2PPS=24 LC_LC_INB=1 LC_LC_CLCIN2PPS=14 LC_LC_C7CON=8 LC_LC_OUTS=129 LC_LC_O5=0
' stim: lib_clc.stim.toml
' devices: 18F27Q10
' The clc module in basil-sim (which models the logic cells, picsim/tests/clc.rs). CLCIN0 = RC0 (high from cycle 1) and
' CLCIN1 = RC1 (low, then high from cycle 60000). ClcCombine(1, CLCIN0, CLCIN1, op) for AND, OR, XOR, NAND, NOR, XNOR is
' read first with A = 1, B = 0 (LC_A*) and again with A = 1, B = 1 (LC_B*). Cell 8 is set up register by register to check
' the 10-register stride (CLC8SEL3, CLC8GLS2, CLC8POL, CLC8CON), then disabled (LC_CLC8CON_OFF keeps the mode and INTP).
' LC_CLC8CON = 179 = EN + OUT (the cell idles high: ClcInvOut) + INTP + mode 3. Pins: a pin or cell the part cannot route is refused and changes nothing.
Program Lc
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "clc"
Dim lc_in0 As Boolean
Dim lc_in1 As Boolean
Dim lc_badin0 As Boolean
Dim lc_badin1 As Boolean
Dim lc_a0 As Boolean
Dim lc_a1 As Boolean
Dim lc_a2 As Boolean
Dim lc_a3 As Boolean
Dim lc_a4 As Boolean
Dim lc_a5 As Boolean
Dim lc_b0 As Boolean
Dim lc_b1 As Boolean
Dim lc_b2 As Boolean
Dim lc_b3 As Boolean
Dim lc_b4 As Boolean
Dim lc_b5 As Boolean
Dim lc_op As Boolean
Dim lc_o2 As Boolean
Dim lc_bado As Boolean
Dim lc_o3 As Boolean
Dim lc_badn As Boolean
Dim lc_clc8con_off As Byte
Dim lc_inb As Boolean
Dim lc_clcin2pps As Byte
Dim lc_c7con As Byte
Dim lc_outs As Byte
Dim lc_o5 As Boolean
Dim lc_clc8sel3 As Byte
Dim lc_clc8gls2 As Byte
Dim lc_clc8pol As Byte
Dim lc_clc8con As Byte
Dim lc_ra0pps As Byte
Dim lc_rb1pps As Byte
Dim lc_rc2pps As Byte
lc_in0 = Clc.ClcInputPin(0, 16)
lc_in1 = Clc.ClcInputPin(1, 17)
lc_badin0 = Clc.ClcInputPin(0, 9)
lc_badin1 = Clc.ClcInputPin(2, 1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpAnd)
lc_a0 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpOr)
lc_a1 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpXor)
lc_a2 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpNand)
lc_a3 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpNor)
lc_a4 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpXnor)
lc_a5 = Clc.ClcOutput(1)
DelayMS(5)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpAnd)
lc_b0 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpOr)
lc_b1 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpXor)
lc_b2 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpNand)
lc_b3 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpNor)
lc_b4 = Clc.ClcOutput(1)
Clc.ClcCombine(1, Clc.ClcInCLCIN0, Clc.ClcInCLCIN1, Clc.ClcOpXnor)
lc_b5 = Clc.ClcOutput(1)
Clc.ClcMode(8, Clc.ClcModeSr)
Clc.ClcSource(8, 4, Clc.ClcInClc1)
Clc.ClcGate(8, 3, Clc.ClcD2T Or Clc.ClcD3N)
Clc.ClcPolarity(8, Clc.ClcInvOut Or Clc.ClcInvG4)
Clc.ClcEdges(8, True, False)
Clc.ClcEnable(8)
Clc.ClcDisable(8)
lc_clc8con_off = CLC8CON
lc_inb = Clc.ClcInputPin(2, 14)
lc_clcin2pps = CLCIN2PPS
Clc.ClcMode(7, Clc.ClcModeAndOr)
Clc.ClcEdges(7, False, True)
lc_c7con = CLC7CON
lc_o5 = Clc.ClcOutput(5)
Clc.ClcEnable(8)
lc_op = False
lc_o2 = Clc.ClcOutputPin(2, 0)
lc_bado = Clc.ClcOutputPin(3, 0)
lc_o3 = Clc.ClcOutputPin(3, 9)
lc_badn = Clc.ClcOutputPin(9, 16)
Clc.ClcMode(9, 1)
Clc.ClcMode(10, 1)
lc_op = Clc.ClcOutputPin(1, 18)
lc_outs = Clc.ClcOutputs()
lc_clc8sel3 = CLC8SEL3
lc_clc8gls2 = CLC8GLS2
lc_clc8pol = CLC8POL
lc_clc8con = CLC8CON
lc_ra0pps = RA0PPS
lc_rb1pps = RB1PPS
lc_rc2pps = RC2PPS
