' LongWord division by word constants, including the seventeenth remainder bit.
' expect: T_Q0=329048312 T_R0=6182 T_Q1=327767971 T_R1=5507 T_Q2=82342482 T_R2=14968 T_Q3=2570755 T_R3=444969 T_Q4=2570670 T_R4=659494 T_Q5=2570592 T_R5=644806 T_Q6=1285347 T_R6=1158409
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const VT(44) As LongWord = (0, 1, 255, 256, 1022, 1023, 1024, 5115000, 65535, 65536, 2147483647, 2147483648, 4294967294, 4294967295, 1940583131, 4276392250, 1812551274, 1802196164, 3383784344, 1578355050, 1781537002, 1144582655, 4095552346, 3931487308, 2945890708, 441039952, 1129658564, 3751067208, 3356626425, 3212033443, 2221047638, 498415891, 4065461239, 1482908858, 1768644254, 3769187246, 3732524549, 4284759689, 81889983, 2365132351, 955867087, 1698505322, 2251816444, 1586724143)
Dim v, q, r As LongWord
Dim i As Byte
Dim Q0, R0, Q1, R1, Q2, R2, Q3, R3, Q4, R4, Q5, R5, Q6, R6 As LongWord
For i = 0 To 43
    v = VT(i)
    q = v / 256
    r = v Mod 256
    Q0 = Q0 + q
    R0 = R0 + r
    r = v Mod 257
    q = v / 257
    Q1 = Q1 + q
    R1 = R1 + r
    q = v / 1023
    r = v Mod 1023
    Q2 = Q2 + q
    R2 = R2 + r
    r = v Mod 32767
    q = v / 32767
    Q3 = Q3 + q
    R3 = R3 + r
    q = v / 32768
    r = v Mod 32768
    Q4 = Q4 + q
    R4 = R4 + r
    r = v Mod 32769
    q = v / 32769
    Q5 = Q5 + q
    R5 = R5 + r
    q = v / 65535
    r = v Mod 65535
    Q6 = Q6 + q
    R6 = R6 + r
Next
