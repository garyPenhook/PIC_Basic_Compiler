' expect: GK_BAD1=0 GK_BAD2=0 GK_BAD3=0 GK_OK=1 GK_ON0=1 GK_ON1=1 GK_CLR=0 GK_R1=4 GK_R2=128 GK_P1=1 GK_P2=0 GK_P3=1 GK_P4=0 GK_R3=0 GK_LINE=101 GK_LINETO=81 GK_BOX=36 GK_CIRC=112 GK_CLIP=25 GK_ERASE=0 GK_B1=3 GK_RB1=3 GK_B2=170 GK_RB2=170 GK_A0=124 GK_A1=18 GK_A3=124 GK_A5=0 GK_I1=72 GK_X1=64 GK_X2=128 GK_X3=122 GK_C0=0 GK_BB=126 GK_W1=68 GK_WRAP=124 GK_DONE=1
' Runs the `Glcd` KS0108 backend against a model of two KS0108 chips (the `pinio.bas` next to this file is the model).
Program Gk
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Include "glcd"
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim ok As Byte
Dim on0 As Byte
Dim on1 As Byte
Dim clr As Word
Dim r1 As Byte
Dim r2 As Byte
Dim p1 As Byte
Dim p2 As Byte
Dim p3 As Byte
Dim p4 As Byte
Dim r3 As Byte
Dim line As Word
Dim lineto As Word
Dim box As Word
Dim circ As Word
Dim clip As Word
Dim erase As Word
Dim b1 As Byte
Dim rb1 As Byte
Dim b2 As Byte
Dim rb2 As Byte
Dim a0 As Byte
Dim a1 As Byte
Dim a3 As Byte
Dim a5 As Byte
Dim i1 As Byte
Dim x1 As Byte
Dim x2 As Byte
Dim x3 As Byte
Dim c0 As Byte
Dim bb As Byte
Dim w1 As Byte
Dim wrap As Byte
Dim done As Byte
Pinio.Wire(0, 1, 2, 3, 4, 1)
Pinio.Fill(255)
bad1 = Glcd.GlcdInitKs0108(16, 0, 1, 2, 3, 24, 5, True)
bad2 = Glcd.GlcdInitKs0108(16, 0, 1, 2, 3, 3, 5, True)
bad3 = Glcd.GlcdInitKs0108(4, 0, 1, 2, 3, 4, 5, True)
ok = Glcd.GlcdInitKs0108(16, 0, 1, 2, 3, 4, 5, True)
on0 = Pinio.DispOn(0)
on1 = Pinio.DispOn(1)
clr = Pinio.Ones()
Glcd.GlcdPlot(10, 10)
Glcd.GlcdPlot(70, 63)
r1 = Pinio.Ram(74)
r2 = Pinio.Ram(966)
p1 = Glcd.GlcdPixel(10, 10)
p2 = Glcd.GlcdPixel(11, 10)
p3 = Glcd.GlcdPixel(70, 63)
p4 = Glcd.GlcdPixel(200, 5)
Glcd.GlcdUnplot(10, 10)
r3 = Pinio.Ram(74)
Glcd.GlcdClear()
Glcd.GlcdLine(True, 0, 0, 100, 50)
line = Pinio.Ones()
Glcd.GlcdClear()
Glcd.GlcdLineTo(True, 20, 60)
lineto = Pinio.Ones()
Glcd.GlcdClear()
Glcd.GlcdBox(True, 20, 20, 10)
box = Pinio.Ones()
Glcd.GlcdClear()
Glcd.GlcdCircle(True, 63, 32, 20)
circ = Pinio.Ones()
Glcd.GlcdCircle(False, 63, 32, 20)
erase = Pinio.Ones()
Glcd.GlcdClear()
Glcd.GlcdCircle(True, 5, 5, 10)
clip = Pinio.Ones()
Glcd.GlcdClear()
Glcd.GlcdWriteByte(1, 2, 3)
b1 = Pinio.Ram(66)
rb1 = Glcd.GlcdReadByte(1, 2)
Glcd.GlcdWriteByte(7, 100, 170)
b2 = Pinio.Ram(996)
rb2 = Glcd.GlcdReadByte(7, 100)
Glcd.GlcdClear()
Glcd.GlcdTextAt(0, 0)
Glcd.GlcdWriteChar(65)
Glcd.GlcdWriteChar(105)
a0 = Pinio.Ram(0)
a1 = Pinio.Ram(1)
a3 = Pinio.Ram(3)
a5 = Pinio.Ram(5)
i1 = Pinio.Ram(7)
Glcd.GlcdTextAt(10, 0)
Glcd.GlcdWriteChar(106)
x1 = Pinio.Ram(61)
x2 = Pinio.Ram(62)
x3 = Pinio.Ram(63)
c0 = Pinio.Ram(512)
Glcd.GlcdWriteChar(66)
bb = Pinio.Ram(514)
Glcd.GlcdTextAt(0, 2)
Glcd.GlcdWriteWord(1)
w1 = Pinio.Ram(129)
Glcd.GlcdClear()
Glcd.GlcdTextAt(20, 0)
Glcd.GlcdWriteChar(65)
Glcd.GlcdWriteChar(65)
wrap = Pinio.Ram(64)
done = 1
