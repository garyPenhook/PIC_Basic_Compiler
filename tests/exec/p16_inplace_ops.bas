' expect: PO_R1=305419984 PO_R2=868 PO_R3=0 PO_R4=16909311 PO_R5=420 PO_R6=10500 PO_R7=1116
' Operations the enhanced mid-range code generator and peepholes handle in place: a LongWord combined with a Byte array element (the element is not widened into
' four bytes), an array element updated with a computed value, a product accumulated into a LongWord, a Word sum of Byte products (temporaries dead across loops and
' skips), all built from values read at run time so nothing folds.
Program Po
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim data(8) As Byte
Dim buf(8) As Byte
Dim ma(8) As Byte
Dim mb(8) As Byte
Dim i As Byte
Dim x As Byte
Dim z As Byte
Dim r1, r2, r3, r4, r6 As LongWord
Dim r5, r7 As Word
Dim wa, wb As Word
Dim s As Word
z = PORTA Xor PORTA
x = z + 5
For i = 0 To 7
    data(i) = i * 37 + 11 + z
    ma(i) = i * 3 + 1 + z
    mb(i) = 17 - i
Next
r1 = $12345678 + z
For i = 0 To 7
    r1 = r1 Xor data(i)
Next
r2 = z
For i = 0 To 7
    r2 = r2 + data(i)
Next
r3 = $0F0F0F0F + z
For i = 0 To 7
    r3 = r3 And data(i)
Next
r4 = $01020300 + z
For i = 0 To 7
    r4 = r4 Or data(i)
Next
For i = 0 To 7
    buf(i) = z
Next
For i = 0 To 7
    buf(i) = buf(i) + i * x
Next
For i = 0 To 7
    buf(i) = buf(i) + i * x
Next
For i = 0 To 7
    buf(i) = buf(i) + i * x
Next
r5 = z
For i = 0 To 7
    r5 = r5 + buf(i)
Next
wa = 300 + z
wb = 7 + z
r6 = z
For i = 1 To 5
    r6 = r6 + LongWord(wa) * wb
Next
s = z
For i = 0 To 7
    s = s + ma(i) * mb(i)
Next
r7 = s
