' expect: EP_BAD1=0 EP_BAD2=0 EP_BAD3=0 EP_BAD4=0 EP_C0=0 EP_OK=1 EP_W=128 EP_H=296 EP_DRV0=39 EP_DRV1=1 EP_DRV2=1 EP_ENTRY=1 EP_XS0=0 EP_XE0=15 EP_YSL0=39 EP_YSH0=1 EP_YEL0=0 EP_YEH0=0 EP_BRD=5 EP_DUC0=0 EP_DUC1=128 EP_TMP=128 EP_SW0=1 EP_HW0=1 EP_C1=8 EP_CLRN=4736 EP_CLRB=255 EP_CLRR=0 EP_CLRB2=255 EP_CLRR2=0 EP_RB=255 EP_RR=255 EP_RBN=256 EP_RRN=256 EP_R1=255 EP_R2=255 EP_R3=255 EP_R4=255 EP_R5=0 EP_R6=0 EP_R7=0 EP_XS1=1 EP_XE1=8 EP_YSL1=31 EP_YSH1=1 EP_YEL1=0 EP_YEH1=1 EP_BLK0=0 EP_BLK1=0 EP_T1B=207 EP_T1R=0 EP_T2B=183 EP_T4B=135 EP_T7B=255 EP_T0B=255 EP_TX=2 EP_RT1B=255 EP_RT1R=48 EP_RT4R=120 EP_WRAP=207 EP_WRAPD=0 EP_BADWIN=0 EP_GOODWIN=4 EP_TOP=0 EP_UPD=1 EP_UPDN=1 EP_UPDC=247 EP_UPDCMD=2 EP_SLP=1 EP_WAKE=1 EP_SW1=2 EP_HW1=2 EP_B_OK=1 EP_B_W=122 EP_B_H=250 EP_B_BLK=0 EP_B_BLKR=0 EP_B_WHT=255 EP_B_WHTR=255 EP_B_RED=0 EP_B_REDR=0 EP_B_TB=207 EP_B_TR=207 EP_B_WRAP=207 EP_B_LASTROW=0 EP_B_WIN=0 EP_N_OK=1 EP_N_HW=0 EP_N_CS=0
' Runs the `Epaper` module (WeAct SSD1680 e-paper) against a model of the controller (the `pinio.bas` and `spi.bas` next to this file).
Program Ep
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Include "spi"
Include "epaper"
Dim bad1 As Byte
Dim bad2 As Byte
Dim bad3 As Byte
Dim bad4 As Byte
Dim c0 As Byte
Dim ok As Byte
Dim w As Word
Dim h As Word
Dim drv0 As Byte
Dim drv1 As Byte
Dim drv2 As Byte
Dim entry As Byte
Dim xs0 As Byte
Dim xe0 As Byte
Dim ysl0 As Byte
Dim ysh0 As Byte
Dim yel0 As Byte
Dim yeh0 As Byte
Dim brd As Byte
Dim duc0 As Byte
Dim duc1 As Byte
Dim tmp As Byte
Dim sw0 As Byte
Dim hw0 As Byte
Dim c1 As Byte
Dim clrn As Word
Dim clrb As Byte
Dim clrr As Byte
Dim clrb2 As Byte
Dim clrr2 As Byte
Dim rb As Byte
Dim rr As Byte
Dim rbn As Word
Dim rrn As Word
Dim r1 As Byte
Dim r2 As Byte
Dim r3 As Byte
Dim r4 As Byte
Dim r5 As Byte
Dim r6 As Byte
Dim r7 As Byte
Dim xs1 As Byte
Dim xe1 As Byte
Dim ysl1 As Byte
Dim ysh1 As Byte
Dim yel1 As Byte
Dim yeh1 As Byte
Dim blk0 As Byte
Dim blk1 As Byte
Dim t1b As Byte
Dim t1r As Byte
Dim t2b As Byte
Dim t4b As Byte
Dim t7b As Byte
Dim t0b As Byte
Dim tx As Byte
Dim rt1b As Byte
Dim rt1r As Byte
Dim rt4r As Byte
Dim wrap As Byte
Dim wrapd As Byte
Dim badwin As Byte
Dim goodwin As Byte
Dim top As Byte
Dim upd As Byte
Dim updn As Byte
Dim updc As Byte
Dim updcmd As Byte
Dim slp As Byte
Dim wake As Byte
Dim sw1 As Byte
Dim hw1 As Byte
Dim b_ok As Byte
Dim b_w As Word
Dim b_h As Word
Dim b_blk As Byte
Dim b_blkr As Byte
Dim b_wht As Byte
Dim b_whtr As Byte
Dim b_red As Byte
Dim b_redr As Byte
Dim b_tb As Byte
Dim b_tr As Byte
Dim b_wrap As Byte
Dim b_lastrow As Byte
Dim b_win As Byte
Dim n_ok As Byte
Dim n_hw As Byte
Dim n_cs As Byte
Dim before As Word
Dim beforeR As Word
Dim cb As Byte

TRISC = 255
ANSELC = 255
Pinio.Wire(16, 17, 18, 19)
Pinio.Fill()
' Refused: bad size, D/C# above 23, BUSY = D/C#, RES# = CS#. Nothing is sent.
bad1 = Epaper.EpdInit(2, True, 16, 17, 18, 19)
bad2 = Epaper.EpdInit(1, True, 24, 17, 18, 19)
bad3 = Epaper.EpdInit(1, True, 16, 17, 18, 16)
bad4 = Epaper.EpdInit(1, True, 16, 17, 17, 19)
c0 = Pinio.State(23)
' 2.9" black / white / red.
ok = Epaper.EpdInit(1, True, 16, 17, 18, 19)
w = Epaper.EpdWidth()
h = Epaper.EpdHeight()
drv0 = Pinio.State(0)
drv1 = Pinio.State(1)
drv2 = Pinio.State(2)
entry = Pinio.State(3)
xs0 = Pinio.State(4)
xe0 = Pinio.State(5)
ysl0 = Pinio.State(6)
ysh0 = Pinio.State(7)
yel0 = Pinio.State(8)
yeh0 = Pinio.State(9)
brd = Pinio.State(10)
duc0 = Pinio.State(11)
duc1 = Pinio.State(12)
tmp = Pinio.State(13)
sw0 = Pinio.State(17)
hw0 = Pinio.State(18)
c1 = Pinio.State(23)
' Clear to white: every byte of both planes (128 / 8 * 296 = 4736).
Epaper.EpdClear(0)
clrn = Word(Pinio.State(25)) * 256 + Pinio.State(19)
clrb = Pinio.Ram(0, 295, 0)
clrr = Pinio.Ram(1, 295, 0)
clrb2 = Pinio.Ram(0, 256, 15)
clrr2 = Pinio.Ram(1, 256, 15)
' Red rectangle x 8..71, y 8..39: RAM Y 287..256, X bytes 1..8, 256 bytes per plane.
before = Word(Pinio.State(25)) * 256 + Pinio.State(19)
beforeR = Word(Pinio.State(26)) * 256 + Pinio.State(20)
Epaper.EpdFillRect(8, 8, 64, 32, 2)
rbn = Word(Pinio.State(25)) * 256 + Pinio.State(19) - before
rrn = Word(Pinio.State(26)) * 256 + Pinio.State(20) - beforeR
rb = Pinio.Ram(0, 287, 1)
rr = Pinio.Ram(1, 287, 1)
r1 = Pinio.Ram(1, 287, 8)
r2 = Pinio.Ram(1, 256, 8)
r3 = Pinio.Ram(1, 256, 1)
r4 = Pinio.Ram(1, 271, 5)
r5 = Pinio.Ram(1, 287, 0)
r6 = Pinio.Ram(1, 287, 9)
r7 = Pinio.Ram(1, 288, 1)
xs1 = Pinio.State(4)
xe1 = Pinio.State(5)
ysl1 = Pinio.State(6)
ysh1 = Pinio.State(7)
yel1 = Pinio.State(8)
yeh1 = Pinio.State(9)
' Black 8 x 8 at the top left.
Epaper.EpdFillRect(0, 0, 8, 8, 1)
blk0 = Pinio.Ram(0, 295, 0)
blk1 = Pinio.Ram(1, 295, 0)
' Text 'A' (5 x 7 font, one blank column left) black in cell (2, 1): rows y 8..15 = RAM Y 287..280, X byte 2.
Epaper.EpdTextColour(1)
Epaper.EpdTextAt(2, 1)
Epaper.EpdWriteChar(65)
t0b = Pinio.Ram(0, 287, 2)
t1b = Pinio.Ram(0, 286, 2)
t1r = Pinio.Ram(1, 286, 2)
t2b = Pinio.Ram(0, 285, 2)
t4b = Pinio.Ram(0, 283, 2)
t7b = Pinio.Ram(0, 280, 2)
tx = Pinio.State(4)
' Red text in cell (4, 1): black / white plane stays white, the red plane holds the glyph.
Epaper.EpdTextColour(2)
Epaper.EpdTextAt(4, 1)
Epaper.EpdWriteChar(65)
rt1b = Pinio.Ram(0, 286, 4)
rt1r = Pinio.Ram(1, 286, 4)
rt4r = Pinio.Ram(1, 283, 4)
' At the right edge the text goes to the next row: cell 16 -> column 0 of row 2 (RAM Y 279..272), glyph row 1 at 278.
Epaper.EpdTextColour(1)
Epaper.EpdTextAt(16, 1)
Epaper.EpdWriteChar(65)
wrap = Pinio.Ram(0, 278, 0)
wrapd = Pinio.Ram(1, 278, 0)
' A row below the display, and windows that are refused, send nothing; a good window is four commands (44h 45h 4Eh 4Fh).
cb = Pinio.State(23)
Epaper.EpdTextAt(0, 37)
Epaper.EpdWriteChar(65)
top = Pinio.State(23) - cb
Epaper.EpdWindow(3, 0, 8, 8)
Epaper.EpdWindow(0, 0, 136, 8)
Epaper.EpdWindow(0, 290, 8, 10)
Epaper.EpdWindow(0, 0, 0, 8)
badwin = Pinio.State(23) - cb
cb = Pinio.State(23)
Epaper.EpdWindow(0, 0, 8, 8)
goodwin = Pinio.State(23) - cb
' Refresh: 22h = F7h, 20h, then BUSY falls.
cb = Pinio.State(23)
upd = Epaper.EpdUpdate()
updn = Pinio.State(14)
updc = Pinio.State(15)
updcmd = Pinio.State(23) - cb
Epaper.EpdSleep()
slp = Pinio.State(16)
wake = Epaper.EpdWake()
sw1 = Pinio.State(17)
hw1 = Pinio.State(18)
' 2.13" black / white: 122 x 250, the red plane mirrors the black / white plane.
b_ok = Epaper.EpdInit(0, False, 16, 17, 18, 19)
b_w = Epaper.EpdWidth()
b_h = Epaper.EpdHeight()
Epaper.EpdFillRect(0, 0, 8, 8, 1)
b_blk = Pinio.Ram(0, 295, 0)
b_blkr = Pinio.Ram(1, 295, 0)
Epaper.EpdFillRect(0, 0, 8, 8, 0)
b_wht = Pinio.Ram(0, 295, 0)
b_whtr = Pinio.Ram(1, 295, 0)
Epaper.EpdFillRect(0, 0, 8, 8, 2)
b_red = Pinio.Ram(0, 295, 0)
b_redr = Pinio.Ram(1, 295, 0)
Epaper.EpdTextColour(1)
Epaper.EpdTextAt(0, 0)
Epaper.EpdWriteChar(65)
b_tb = Pinio.Ram(0, 294, 0)
b_tr = Pinio.Ram(1, 294, 0)
' 15 cells a row: cell 15 wraps to column 0 of row 1 (RAM Y 287..280, glyph row 1 at 286).
Epaper.EpdTextAt(15, 0)
Epaper.EpdWriteChar(65)
b_wrap = Pinio.Ram(0, 286, 0)
' Row 31 would end at line 256 > 250: refused. A window past line 250 is refused.
cb = Pinio.State(23)
Epaper.EpdTextAt(0, 31)
Epaper.EpdWriteChar(65)
b_lastrow = Pinio.State(23) - cb
Epaper.EpdWindow(0, 245, 8, 6)
b_win = Pinio.State(23) - cb
' CS# and RES# not wired: the init still works, no hardware reset, nothing seen with CS# high.
Pinio.Wire(16, 255, 255, 19)
n_ok = Epaper.EpdInit(1, False, 16, 255, 255, 19)
Epaper.EpdClear(0)
n_hw = Pinio.State(18)
n_cs = Pinio.State(22)
