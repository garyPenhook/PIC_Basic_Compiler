' expect: LB_LB_R1=1 LB_LB_R2=0 LB_LB_R3=1 LB_LB_R4=1 LB_LB_ST=1 LB_LB_REL=0 LB_LB_RELST=0 LB_LB_N1=1 LB_LB_N2=0 LB_LB_N3=0 LB_LB_NST=255 LB_LB_CNT=0 LB_LB_P1=0 LB_LB_P2=0 LB_LB_P3=1 LB_LB_P4=0 LB_LB_P5=1 LB_LB_P6=1 LB_LB_PST=1 LB_LB_PREL=0 LB_LB_PRELST=0 LB_LB_Z1=1 LB_LB_Z2=0 LB_LB_ZST=255
' devices: 18F27Q10
' The buttons module in the simulator, which has no pin model. RB0 reads low, so a button that is down when low is held
' and one that is down when high is not. Counter runs for 5 ms on the quiet pin and sees no edge. ButtonPoll settles on
' a count of calls instead of a wait.
Program Lb
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "buttons"
Dim st As Byte
Dim nst As Byte
Dim rst As Byte
Dim lb_r1 As Boolean
Dim lb_r2 As Boolean
Dim lb_r3 As Boolean
Dim lb_r4 As Boolean
Dim lb_st As Byte
Dim lb_rel As Boolean
Dim lb_relst As Byte
Dim lb_n1 As Boolean
Dim lb_n2 As Boolean
Dim lb_n3 As Boolean
Dim lb_nst As Byte
Dim lb_cnt As Word
Dim pst As Word
Dim prst As Word
Dim zst As Word
Dim lb_p1 As Boolean
Dim lb_p2 As Boolean
Dim lb_p3 As Boolean
Dim lb_p4 As Boolean
Dim lb_p5 As Boolean
Dim lb_p6 As Boolean
Dim lb_pst As Word
Dim lb_prel As Boolean
Dim lb_prelst As Word
Dim lb_z1 As Boolean
Dim lb_z2 As Boolean
Dim lb_zst As Word
' Held, delay 2, rate 1: True at once, nothing, True after 2 calls, True after 1 more.
lb_r1 = Buttons.Button(8, False, 2, 1, st)
lb_r2 = Buttons.Button(8, False, 2, 1, st)
lb_r3 = Buttons.Button(8, False, 2, 1, st)
lb_r4 = Buttons.Button(8, False, 2, 1, st)
lb_st = st
' Not down (it reads low, down is high): False, and the state is cleared.
rst = 77
lb_rel = Buttons.Button(8, True, 2, 1, rst)
lb_relst = rst
' Delay 0: one True, then no repeat.
lb_n1 = Buttons.Button(8, False, 0, 1, nst)
lb_n2 = Buttons.Button(8, False, 0, 1, nst)
lb_n3 = Buttons.Button(8, False, 0, 1, nst)
lb_nst = nst
lb_cnt = Buttons.Counter(8, 5)
' ButtonPoll held, settle 3, delay 2, rate 1: True on the third call, then after 2 more, then every call.
lb_p1 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_p2 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_p3 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_p4 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_p5 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_p6 = Buttons.ButtonPoll(8, False, 3, 2, 1, pst)
lb_pst = pst
' Not down: False, and both bytes of the state are cleared.
prst = $1234
lb_prel = Buttons.ButtonPoll(8, True, 3, 2, 1, prst)
lb_prelst = prst
' Settle 0 and delay 0: True on the first call, then no repeat.
lb_z1 = Buttons.ButtonPoll(8, False, 0, 0, 1, zst)
lb_z2 = Buttons.ButtonPoll(8, False, 0, 0, 1, zst)
lb_zst = zst
