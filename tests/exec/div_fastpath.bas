' expect: T_Q1=65535 T_R1=1234 T_Q2=123 T_R2=4 T_Q3=0 T_R3=1234 T_Q4=4294967295 T_R4=77 T_Q5=1000 T_R5=7 T_Q6=-100 T_R6=-3
' Word and LongWord divides whose operands fit the lower half run the shorter routine in Speed mode; a zero divisor and
' a divisor wider than the dividend must still give the full-width results.
#option Optimize = Speed
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim a, b, q1, r1, q2, r2, q3, r3 As Word
Dim la, lb, q4, r4, q5, r5 As LongWord
Dim sa, sb, q6, r6 As Integer
a = 1234
b = 0
q1 = a / b
r1 = a Mod b
a = 1234
b = 10
q2 = a / b
r2 = a Mod b
a = 1234
b = 5000
q3 = a / b
r3 = a Mod b
la = 77
lb = 0
q4 = la / lb
r4 = la Mod lb
la = 100007
lb = 100
q5 = la / lb
r5 = la Mod lb
sa = -10003
sb = 100
q6 = sa / sb
r6 = sa Mod sb
