' An unsigned Word divided by a byte constant goes through `__divk2` (an 8-bit remainder) when the program has no
' other 16-bit division: quotient and remainder for each constant, over edge values and random ones.
' expect: T_Q0=521922 T_M0=63 T_Q1=313140 T_M1=129 T_Q2=260942 T_M2=177 T_Q3=223666 T_M3=167 T_Q4=156554 T_M4=289 T_Q5=15633 T_M5=2529 T_Q6=12305 T_M6=3094 T_Q7=12111 T_M7=3510 T_Q8=7801 T_M8=5629 T_Q9=6212 T_M9=6617 T_Q10=6112 T_M10=7269
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Const VT(64) As Word = (0, 1, 2, 3, 9, 10, 11, 99, 100, 127, 128, 129, 254, 255, 256, 257, 1000, 9999, 10000, 32767, 32768, 32769, 65534, 65535, 59294, 61033, 59222, 24890, 24203, 62359, 24402, 12336, 58535, 39767, 18585, 11884, 5489, 51925, 59374, 20643, 1966, 8279, 7805, 4673, 24930, 31711, 3942, 60808, 42767, 57741, 25601, 30624, 38555, 65506, 602, 11139, 59943, 36459, 53317, 10905, 33291, 41324, 30102, 37885)
Dim Q0, M0, Q1, M1, Q2, M2, Q3, M3, Q4, M4, Q5, M5, Q6, M6, Q7, M7, Q8, M8, Q9, M9, Q10, M10 As LongWord
Dim v, qw, mw As Word
Dim i As Byte

For i = 0 To 63
    v = VT(i)
    qw = v / 3
    mw = v Mod 3
    Q0 = Q0 + qw
    M0 = M0 + mw
    qw = v / 5
    mw = v Mod 5
    Q1 = Q1 + qw
    M1 = M1 + mw
    qw = v / 6
    mw = v Mod 6
    Q2 = Q2 + qw
    M2 = M2 + mw
    qw = v / 7
    mw = v Mod 7
    Q3 = Q3 + qw
    M3 = M3 + mw
    qw = v / 10
    mw = v Mod 10
    Q4 = Q4 + qw
    M4 = M4 + mw
    qw = v / 100
    mw = v Mod 100
    Q5 = Q5 + qw
    M5 = M5 + mw
    qw = v / 127
    mw = v Mod 127
    Q6 = Q6 + qw
    M6 = M6 + mw
    qw = v / 129
    mw = v Mod 129
    Q7 = Q7 + qw
    M7 = M7 + mw
    qw = v / 200
    mw = v Mod 200
    Q8 = Q8 + qw
    M8 = M8 + mw
    qw = v / 251
    mw = v Mod 251
    Q9 = Q9 + qw
    M9 = M9 + mw
    qw = v / 255
    mw = v Mod 255
    Q10 = Q10 + qw
    M10 = M10 + mw
Next
