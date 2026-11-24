' expect: CA_M=100009 CA_P=48 CA_S=-9 CA_L=1000000010 CA_F=7 CA_X=193013 CA_SEEN=1 CA_TICKS=6
' Calling C on the dsPIC33: the XC-DSC register convention (holes filled by later arguments, a long without an even pair on the
' stack), C calling an `Export` with a long and an int on the stack, a signed byte result, four longs, a float result, and a handler that calls C (inside Save) while the main line calls
' it as well.
Program Ca
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
CFile "c_abi.c"

Extern Function mixed(a As Byte, b As LongInt, c As Integer, d As Float, ByRef p As Integer, e As LongInt, h As Integer, i As Integer, j As Integer) As LongInt
Extern Function sbyt(v As ShortInt, w As Byte) As ShortInt
Extern Function sevenlong(a As LongWord, b As LongWord, c As LongWord, d As LongWord) As LongWord
Extern Function fmix(a As Float, n As Integer, b As Float) As Float
Extern Function tick_c(stp As Word) As Word
Extern Function call_sum7() As LongInt

Dim m As LongInt
Dim p As Integer
Dim s As ShortInt
Dim l As LongWord
Dim f As Integer
Dim seen As Byte
Dim ticks As Word
Dim hf As Float
Dim t As Word
Dim x As LongInt

Export Function Sum7(a As Integer, b As LongInt, c As LongInt, d As LongInt, e As LongInt, f As Integer, g As Integer) As LongInt
    Result = a + b + c + d + e + f + g
End Function

Interrupt T1()
    IFS0.T1IF = 0
    Save(0, tick_c)
        t = tick_c(1)
    Restore
    seen = 1
End Interrupt

m = mixed(5, 100000, 3, 2.5, p, 7, 11, 13, 16)
s = sbyt(3, 12)
l = sevenlong(1000000000, 3, 3, 4)
hf = fmix(1.5, 3, 2.5)
f = Integer(hf)
x = call_sum7()
PR1 = 100
T1CON = 0
IFS0.T1IF = 0
IEC0.T1IE = 1
T1CON.TON = 1
Enable(T1)
While seen = 0
Wend
Disable(T1)
T1CON.TON = 0
t = tick_c(5)
ticks = t
Terminate
