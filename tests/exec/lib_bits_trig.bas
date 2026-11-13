' expect: TG_TG_SINCK=1664 TG_TG_COSCK=128 TG_TG_ATNCK=32530 TG_TG_HYPCK=22584 TG_TG_S64=127 TG_TG_S192=-127 TG_TG_S1=3 TG_TG_C0=127 TG_TG_C128=-127 TG_TG_A1=255 TG_TG_A2=63 TG_TG_A3=127 TG_TG_A4=193 TG_TG_A5=33 TG_TG_H1=181 TG_TG_H2=5
' devices: 18F27Q10 18F16Q41 16F17146 16F15244
' BSin, BCos, BAtn, BHyp: a checksum of the whole sine and cosine tables (every angle), of a 32 x 32 grid of
' vectors for BAtn and BHyp (the values come from a model of the same algorithm; the model's worst BAtn error is
' 1.93 steps of 1/256 turn), and the axes and extremes.
Program Tg
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "bits"
Dim tg_sinck As Word
Dim tg_cosck As Word
Dim tg_atnck As Word
Dim tg_hypck As Word
Dim tg_s64 As ShortInt
Dim tg_s192 As ShortInt
Dim tg_s1 As ShortInt
Dim tg_c0 As ShortInt
Dim tg_c128 As ShortInt
Dim tg_a1 As Byte
Dim tg_a2 As Byte
Dim tg_a3 As Byte
Dim tg_a4 As Byte
Dim tg_a5 As Byte
Dim tg_h1 As Byte
Dim tg_h2 As Byte
Dim i As Word
Dim xi As Word
Dim yi As Word
Dim v As Integer
Dim x As ShortInt
Dim y As ShortInt
Dim k As Word
tg_sinck = 0
tg_cosck = 0
For i = 0 To 255
    v = BSin(Byte(i))
    tg_sinck = tg_sinck + Word(v + 128) * (i + 1)
    v = BCos(Byte(i))
    tg_cosck = tg_cosck + Word(v + 128) * (i + 1)
Next
tg_atnck = 0
tg_hypck = 0
For xi = 0 To 31
    For yi = 0 To 31
        x = ShortInt(Integer(xi) * 8 - 127)
        y = ShortInt(Integer(yi) * 8 - 127)
        k = xi * 32 + yi + 1
        tg_atnck = tg_atnck + Word(BAtn(x, y)) * k
        tg_hypck = tg_hypck + Word(BHyp(x, y)) * k
    Next
Next
tg_s64 = BSin(64)
tg_s192 = BSin(192)
tg_s1 = BSin(1)
tg_c0 = BCos(0)
tg_c128 = BCos(128)
tg_a1 = BAtn(127, 0)
tg_a2 = BAtn(0, 127)
tg_a3 = BAtn(-128, 0)
tg_a4 = BAtn(0, -128)
tg_a5 = BAtn(100, 100)
tg_h1 = BHyp(-128, -128)
tg_h2 = BHyp(3, 4)
