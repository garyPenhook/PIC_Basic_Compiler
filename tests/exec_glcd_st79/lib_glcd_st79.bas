' expect: GS_BAD1=0 GS_BAD2=0 GS_OK=1 GS_RE=1 GS_G=1 GS_FN=54 GS_FC=4 GS_CLR=0 GS_R1=16 GS_R2=32 GS_R3=1 GS_P1=1 GS_P2=0 GS_P3=1 GS_P4=0 GS_KEEP=8 GS_LINE=101 GS_LINETO=81 GS_BOX=36 GS_CIRC=112 GS_CLIP=25 GS_ERASE=0 GS_B0=60 GS_B1=165 GS_RB0=60 GS_RB1=165 GS_B2=240 GS_RB2=240 GS_TXT=14 GS_TP1=1 GS_TP2=0 GS_TOP=0 GS_DONE=1
' Runs the `Glcd` ST7920 backend (128 x 64, folded) against a model of the controller (the `pinio.bas` next to this file).
Program Gs
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Include "glcd"
Dim bad1 As Byte
Dim bad2 As Byte
Dim ok As Byte
Dim re As Byte
Dim g As Byte
Dim fn As Byte
Dim fc As Byte
Dim clr As Word
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim p1 As Byte
Dim p2 As Byte
Dim p3 As Byte
Dim p4 As Byte
Dim keep As Byte
Dim line As Word
Dim lineto As Word
Dim box As Word
Dim circ As Word
Dim clip As Word
Dim erase As Word
Dim b0 As Byte
Dim b1 As Byte
Dim rb0 As Byte
Dim rb1 As Byte
Dim b2 As Byte
Dim rb2 As Byte
Dim txt As Word
Dim tp1 As Byte
Dim tp2 As Byte
Dim top As Byte
Dim done As Byte
Pinio.Wire(0, 1, 2)
Pinio.Fill(255)
bad1 = Glcd.GlcdInitSt7920(16, 0, 1, 24, 3, True)
bad2 = Glcd.GlcdInitSt7920(16, 0, 1, 1, 3, True)
ok = Glcd.GlcdInitSt7920(16, 0, 1, 2, 3, True)
re = Pinio.State(0)
g = Pinio.State(1)
fn = Pinio.State(2)
fc = Pinio.State(3)
clr = Pinio.Ones()
Glcd.GlcdPlot(3, 2)
Glcd.GlcdPlot(10, 40)
Glcd.GlcdPlot(127, 63)
r1 = Pinio.Ram(64)
r2 = Pinio.Ram(273)
r3 = Pinio.Ram(1023)
p1 = Glcd.GlcdPixel(3, 2)
p2 = Glcd.GlcdPixel(4, 2)
p3 = Glcd.GlcdPixel(10, 40)
p4 = Glcd.GlcdPixel(256, 5)
Glcd.GlcdPlot(4, 2)
Glcd.GlcdUnplot(3, 2)
keep = Pinio.Ram(64)
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
Glcd.GlcdWriteByte(5, 2, 60)
Glcd.GlcdWriteByte(5, 3, 165)
b0 = Pinio.Ram(162)
b1 = Pinio.Ram(163)
rb0 = Glcd.GlcdReadByte(5, 2)
rb1 = Glcd.GlcdReadByte(5, 3)
Glcd.GlcdWriteByte(40, 9, 240)
b2 = Pinio.Ram(281)
rb2 = Glcd.GlcdReadByte(40, 9)
Glcd.GlcdClear()
Glcd.GlcdTextAt(0, 0)
Glcd.GlcdWriteChar(65)
txt = Pinio.Ones()
tp1 = Glcd.GlcdPixel(0, 2)
tp2 = Glcd.GlcdPixel(0, 1)
top = Glcd.GlcdPixel(5, 3)
done = 1
