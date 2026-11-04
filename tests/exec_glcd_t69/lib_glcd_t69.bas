' expect: GT_BAD1=0 GT_BAD2=0 GT_BAD3=0 GT_BAD4=0 GT_OK=1 GT_GH=0 GT_GA=16 GT_TH=1024 GT_TA=16 GT_OFFS=1 GT_MODE=128 GT_DISP=156 GT_CLR=0 GT_R1=32 GT_R2=1 GT_P1=1 GT_P2=0 GT_P3=1 GT_P4=0 GT_R3=0 GT_LINE=101 GT_LINETO=81 GT_BOX=36 GT_CIRC=112 GT_CLIP=25 GT_ERASE=0 GT_B1=165 GT_RB1=165 GT_T1=33 GT_T2=34 GT_WRAP=33 GT_CODE=200 GT_CX=1 GT_CY=2 GT_LAST=167 GT_UCNT=8 GT_UMIN=3088 GT_USUM=864 GT_N1=20 GT_N2=16 GT_I1=13 GT_I2=19 GT_H1=34 GT_H2=38 GT_L1=13 GT_L2=23 GT_L3=16 GT_DOK=1 GT_DGA=16 GT_DTH=512 GT_DOFFS=1 GT_DCLR=0 GT_DR1=32 GT_DR2=32 GT_DR3=32 GT_DR4=32 GT_DP1=1 GT_DP2=1 GT_DP3=0 GT_DONES=4 GT_DT1=33 GT_DT2=34 GT_DBAD=0 GT_DONE=1
' Runs the `Glcd` T6963C backend against a model of the controller (the `pinio.bas` next to this file is the model).
Program Gt
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Include "glcd"
Const Smile(8) As Byte = (60, 66, 165, 129, 165, 153, 66, 60)
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim ok As Byte
Dim gh As Word
Dim ga As Word
Dim th As Word
Dim ta As Word
Dim offs As Word
Dim mode As Word
Dim disp As Word
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
Dim t1 As Byte
Dim t2 As Byte
Dim wrap As Byte
Dim code As Byte
Dim cx As Word
Dim cy As Word
Dim last As Word
Dim ucnt As Word
Dim umin As Word
Dim usum As Word
Dim n1 As Byte
Dim n2 As Byte
Dim i1 As Byte
Dim i2 As Byte
Dim h1 As Byte
Dim h2 As Byte
Dim l1 As Byte
Dim l2 As Byte
Dim l3 As Byte
Dim dok As Byte
Dim dga As Word
Dim dth As Word
Dim doffs As Word
Dim dclr As Word
Dim dr1 As Byte
Dim dr2 As Byte
Dim dr3 As Byte
Dim dr4 As Byte
Dim dp1 As Byte
Dim dp2 As Byte
Dim dp3 As Byte
Dim dones As Word
Dim dt1 As Byte
Dim dt2 As Byte
Dim dbad As Byte
Dim done As Byte
Pinio.Wire(0, 1, 2, 3)
Pinio.Fill(255)
bad1 = Glcd.GlcdInitT6963(16, 1, 2, 3, 0, 4, 128, 64, 7)
bad2 = Glcd.GlcdInitT6963(16, 1, 2, 3, 0, 4, 100, 64, 8)
bad3 = Glcd.GlcdInitT6963(16, 1, 2, 3, 3, 4, 128, 64, 8)
bad4 = Glcd.GlcdInitT6963(16, 1, 2, 255, 0, 4, 128, 64, 8)
ok = Glcd.GlcdInitT6963(16, 1, 2, 3, 0, 4, 128, 64, 8)
gh = Pinio.Reg(0)
ga = Pinio.Reg(1)
th = Pinio.Reg(2)
ta = Pinio.Reg(3)
offs = Pinio.Reg(4)
mode = Pinio.Reg(5)
disp = Pinio.Reg(6)
clr = Pinio.Ones()
Glcd.GlcdPlot(10, 10)
Glcd.GlcdPlot(127, 63)
r1 = Pinio.Ram(161)
r2 = Pinio.Ram(1023)
p1 = Glcd.GlcdPixel(10, 10)
p2 = Glcd.GlcdPixel(11, 10)
p3 = Glcd.GlcdPixel(127, 63)
p4 = Glcd.GlcdPixel(128, 5)
Glcd.GlcdUnplot(10, 10)
r3 = Pinio.Ram(161)
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
Glcd.GlcdWriteByte(5, 3, 165)
b1 = Pinio.Ram(83)
rb1 = Glcd.GlcdReadByte(5, 3)
Glcd.GlcdTextAt(2, 1)
Glcd.GlcdWriteChar(65)
Glcd.GlcdWriteChar(66)
t1 = Pinio.Ram(1042)
t2 = Pinio.Ram(1043)
Glcd.GlcdTextAt(15, 0)
Glcd.GlcdWriteChar(65)
Glcd.GlcdWriteChar(65)
wrap = Pinio.Ram(1040)
Glcd.GlcdWriteCode(200)
code = Pinio.Ram(1041)
Glcd.GlcdCommand(33, 1, 2)
cx = Pinio.Reg(7)
cy = Pinio.Reg(8)
Glcd.GlcdCommand(167)
last = Pinio.Reg(9)
Glcd.GlcdUdg(130, Smile)
ucnt = Pinio.Reg(10)
umin = Pinio.Reg(11)
usum = Pinio.Reg(12)
Glcd.GlcdTextAt(0, 3)
Glcd.GlcdWriteLong(4000000000)
n1 = Pinio.Ram(1072)
n2 = Pinio.Ram(1081)
Glcd.GlcdTextAt(0, 4)
Glcd.GlcdWriteInt(-123)
i1 = Pinio.Ram(1088)
i2 = Pinio.Ram(1091)
Glcd.GlcdTextAt(0, 5)
Glcd.GlcdWriteHexWord(48879)
h1 = Pinio.Ram(1104)
h2 = Pinio.Ram(1107)
Glcd.GlcdTextAt(0, 6)
Glcd.GlcdWriteLongInt(-70000)
l1 = Pinio.Ram(1120)
l2 = Pinio.Ram(1121)
l3 = Pinio.Ram(1125)
Pinio.SetDual(1)
Pinio.Fill(255)
dbad = Glcd.GlcdInitT6963Dual(16, 1, 2, 3, 0, 4, 128, 70, 8)
dok = Glcd.GlcdInitT6963Dual(16, 1, 2, 3, 0, 4, 128, 64, 8)
dga = Pinio.Reg(1)
dth = Pinio.Reg(2)
doffs = Pinio.Reg(4)
dclr = Pinio.OnesDual()
Glcd.GlcdPlot(10, 10)
Glcd.GlcdPlot(10, 31)
Glcd.GlcdPlot(10, 32)
Glcd.GlcdPlot(10, 40)
dr1 = Pinio.Ram(161)
dr2 = Pinio.Ram(497)
dr3 = Pinio.Ram(577)
dr4 = Pinio.Ram(705)
dp1 = Glcd.GlcdPixel(10, 40)
dp2 = Glcd.GlcdPixel(10, 32)
dp3 = Glcd.GlcdPixel(11, 40)
dones = Pinio.OnesDual()
Glcd.GlcdTextAt(2, 1)
Glcd.GlcdWriteChar(65)
dt1 = Pinio.Ram(530)
Glcd.GlcdTextAt(2, 4)
Glcd.GlcdWriteChar(66)
dt2 = Pinio.Ram(1090)
done = 1
