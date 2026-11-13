' expect: NF_B0=3279945728 NF_L0=4294967040 NF_B1=3347054592 NF_L1=4294901760 NF_B2=3414163456 NF_L2=4278190080 NF_B3=3472883712 NF_L3=2147483648 NF_B4=3212836864 NF_L4=4294967295 NF_B5=3281387520 NF_L5=4294966996 NF_B6=3355443200 NF_L6=4294836224 NF_B7=3405774848 NF_L7=4286578688
' Negative LongInt to Float and back where the low bytes are zero (the carry of the two's-complement negate runs through every byte), built at run time.
Program Nf
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "floatlib"
Dim x As Byte
Dim b0 As LongWord
Dim l0 As LongInt
Dim v0 As LongInt
Dim b1 As LongWord
Dim l1 As LongInt
Dim v1 As LongInt
Dim b2 As LongWord
Dim l2 As LongInt
Dim v2 As LongInt
Dim b3 As LongWord
Dim l3 As LongInt
Dim v3 As LongInt
Dim b4 As LongWord
Dim l4 As LongInt
Dim v4 As LongInt
Dim b5 As LongWord
Dim l5 As LongInt
Dim v5 As LongInt
Dim b6 As LongWord
Dim l6 As LongInt
Dim v6 As LongInt
Dim b7 As LongWord
Dim l7 As LongInt
Dim v7 As LongInt
x = PORTA Xor PORTA
v0 = x
v0 = v0 - 256
b0 = FloatLib.FFromLong(v0)
l0 = FloatLib.FToLong(b0)
v1 = x
v1 = v1 - 65536
b1 = FloatLib.FFromLong(v1)
l1 = FloatLib.FToLong(b1)
v2 = x
v2 = v2 - 16777216
b2 = FloatLib.FFromLong(v2)
l2 = FloatLib.FToLong(b2)
v3 = x
v3 = v3 - 2147483647
v3 = v3 - 1
b3 = FloatLib.FFromLong(v3)
l3 = FloatLib.FToLong(b3)
v4 = x
v4 = v4 - 1
b4 = FloatLib.FFromLong(v4)
l4 = FloatLib.FToLong(b4)
v5 = x
v5 = v5 - 300
b5 = FloatLib.FFromLong(v5)
l5 = FloatLib.FToLong(b5)
v6 = x
v6 = v6 - 131072
b6 = FloatLib.FFromLong(v6)
l6 = FloatLib.FToLong(b6)
v7 = x
v7 = v7 - 8388608
b7 = FloatLib.FFromLong(v7)
l7 = FloatLib.FToLong(b7)
