' expect: FL_C0=0 FL_C1=1065353216 FL_C2=3212836864 FL_C3=1073741824 FL_C4=1132396544 FL_C5=1132462080 FL_C6=1199570688 FL_C7=1199570944 FL_C8=1266679807 FL_C9=1266679808 FL_C10=1266679808 FL_C11=1266679810 FL_C12=1325400064 FL_C13=3472883712 FL_C14=3472883712 FL_C15=1290500515 FL_C16=3437984163 FL_C17=1315859240 FL_C18=3467822054 FL_C19=1310363281 FL_C20=1293089027 FL_C21=1274259322 FL_C22=3471625566 FL_C23=3448235205 FL_C24=3470539753 FL_C25=3449460143 FL_C26=1323645467 FL_C27=3453196591 FL_C28=1324603318 FL_C29=1320651054 FL_C30=3461836970 FL_C31=3466819541 FL_C32=1309556565 FL_C33=3456281144 FL_C34=3465972884 FL_C35=3460190260 FL_C36=3443507645 FL_C37=3461155297 FL_C38=1318500584 FL_C39=3464693192 FL_C40=1301834613 FL_C41=1288595684 FL_C42=1321210374 FL_U0=0 FL_U1=1065353216 FL_U2=1333788672 FL_U3=1325400064 FL_U4=1333788671 FL_U5=1266679808 FL_U6=1328730206 FL_U7=1329249517 FL_U8=1323683224 FL_U9=1318284436 FL_U10=1327228093 FL_U11=1333456061 FL_U12=1301670486 FL_U13=1307692152 FL_U14=1325600264 FL_U15=1322652722 FL_U16=1311304659 FL_T0=0 FL_T1=0 FL_T2=0 FL_T3=0 FL_T4=1 FL_T5=4294967295 FL_T6=1 FL_T7=4294967295 FL_T8=2 FL_T9=4294967294 FL_T10=255 FL_T11=65535 FL_T12=16777216 FL_T13=2147483520 FL_T14=2147483647 FL_T15=2147483648 FL_T16=2147483648 FL_T17=2147483647 FL_T18=2147483648 FL_T19=0 FL_T20=123456 FL_T21=4294868531 FL_T22=2147483647 FL_T23=2147483648 FL_T24=514281856 FL_T25=3598936384 FL_T26=4272893496 FL_T27=3373381824 FL_T28=336431712 FL_T29=529141728 FL_T30=146051888 FL_T31=750955648 FL_T32=3922462336 FL_T33=390590720 FL_T34=188739760 FL_T35=159790416 FL_TN=0 FL_Q0=1 FL_Q1=0 FL_Q2=0 FL_Q3=1 FL_Q4=0 FL_Q5=1 FL_Q6=1 FL_Q7=0 FL_Q8=0 FL_Q9=1 FL_Q10=0 FL_Q11=1 FL_Q12=0 FL_Q13=1 FL_Q14=1 FL_Q15=1 FL_Q16=0 FL_Q17=0 FL_Q18=0 FL_Q19=1 FL_Q20=0 FL_Q21=0 FL_Q22=1 FL_Q23=1 FL_Q24=0 FL_Q25=1 FL_Q26=1 FL_Q27=1 FL_Q28=0 FL_Q29=0 FL_Q30=0 FL_Q31=1 FL_Q32=0 FL_Q33=0 FL_Q34=1 FL_Q35=1 FL_Q36=0 FL_Q37=1 FL_Q38=1 FL_Q39=1 FL_Q40=0 FL_Q41=0 FL_Q42=0
Program Fl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "floatlib"
Dim c0 As LongWord
Dim c1 As LongWord
Dim c2 As LongWord
Dim c3 As LongWord
Dim c4 As LongWord
Dim c5 As LongWord
Dim c6 As LongWord
Dim c7 As LongWord
Dim c8 As LongWord
Dim c9 As LongWord
Dim c10 As LongWord
Dim c11 As LongWord
Dim c12 As LongWord
Dim c13 As LongWord
Dim c14 As LongWord
Dim c15 As LongWord
Dim c16 As LongWord
Dim c17 As LongWord
Dim c18 As LongWord
Dim c19 As LongWord
Dim c20 As LongWord
Dim c21 As LongWord
Dim c22 As LongWord
Dim c23 As LongWord
Dim c24 As LongWord
Dim c25 As LongWord
Dim c26 As LongWord
Dim c27 As LongWord
Dim c28 As LongWord
Dim c29 As LongWord
Dim c30 As LongWord
Dim c31 As LongWord
Dim c32 As LongWord
Dim c33 As LongWord
Dim c34 As LongWord
Dim c35 As LongWord
Dim c36 As LongWord
Dim c37 As LongWord
Dim c38 As LongWord
Dim c39 As LongWord
Dim c40 As LongWord
Dim c41 As LongWord
Dim c42 As LongWord
Dim u0 As LongWord
Dim u1 As LongWord
Dim u2 As LongWord
Dim u3 As LongWord
Dim u4 As LongWord
Dim u5 As LongWord
Dim u6 As LongWord
Dim u7 As LongWord
Dim u8 As LongWord
Dim u9 As LongWord
Dim u10 As LongWord
Dim u11 As LongWord
Dim u12 As LongWord
Dim u13 As LongWord
Dim u14 As LongWord
Dim u15 As LongWord
Dim u16 As LongWord
Dim t0 As LongInt
Dim t1 As LongInt
Dim t2 As LongInt
Dim t3 As LongInt
Dim t4 As LongInt
Dim t5 As LongInt
Dim t6 As LongInt
Dim t7 As LongInt
Dim t8 As LongInt
Dim t9 As LongInt
Dim t10 As LongInt
Dim t11 As LongInt
Dim t12 As LongInt
Dim t13 As LongInt
Dim t14 As LongInt
Dim t15 As LongInt
Dim t16 As LongInt
Dim t17 As LongInt
Dim t18 As LongInt
Dim t19 As LongInt
Dim t20 As LongInt
Dim t21 As LongInt
Dim t22 As LongInt
Dim t23 As LongInt
Dim t24 As LongInt
Dim t25 As LongInt
Dim t26 As LongInt
Dim t27 As LongInt
Dim t28 As LongInt
Dim t29 As LongInt
Dim t30 As LongInt
Dim t31 As LongInt
Dim t32 As LongInt
Dim t33 As LongInt
Dim t34 As LongInt
Dim t35 As LongInt
Dim tn As LongInt
Dim q0 As Boolean
Dim q1 As Boolean
Dim q2 As Boolean
Dim q3 As Boolean
Dim q4 As Boolean
Dim q5 As Boolean
Dim q6 As Boolean
Dim q7 As Boolean
Dim q8 As Boolean
Dim q9 As Boolean
Dim q10 As Boolean
Dim q11 As Boolean
Dim q12 As Boolean
Dim q13 As Boolean
Dim q14 As Boolean
Dim q15 As Boolean
Dim q16 As Boolean
Dim q17 As Boolean
Dim q18 As Boolean
Dim q19 As Boolean
Dim q20 As Boolean
Dim q21 As Boolean
Dim q22 As Boolean
Dim q23 As Boolean
Dim q24 As Boolean
Dim q25 As Boolean
Dim q26 As Boolean
Dim q27 As Boolean
Dim q28 As Boolean
Dim q29 As Boolean
Dim q30 As Boolean
Dim q31 As Boolean
Dim q32 As Boolean
Dim q33 As Boolean
Dim q34 As Boolean
Dim q35 As Boolean
Dim q36 As Boolean
Dim q37 As Boolean
Dim q38 As Boolean
Dim q39 As Boolean
Dim q40 As Boolean
Dim q41 As Boolean
Dim q42 As Boolean
c0 = FloatLib.FFromLong(0)
c1 = FloatLib.FFromLong(1)
c2 = FloatLib.FFromLong(-1)
c3 = FloatLib.FFromLong(2)
c4 = FloatLib.FFromLong(255)
c5 = FloatLib.FFromLong(256)
c6 = FloatLib.FFromLong(65535)
c7 = FloatLib.FFromLong(65536)
c8 = FloatLib.FFromLong(16777215)
c9 = FloatLib.FFromLong(16777216)
c10 = FloatLib.FFromLong(16777217)
c11 = FloatLib.FFromLong(16777219)
c12 = FloatLib.FFromLong(2147483647)
c13 = FloatLib.FFromLong(-2147483647 - 1)
c14 = FloatLib.FFromLong(-2147483647)
c15 = FloatLib.FFromLong(123456789)
c16 = FloatLib.FFromLong(-123456789)
c17 = FloatLib.FFromLong(1000000007)
c18 = FloatLib.FFromLong(-1499591369)
c19 = FloatLib.FFromLong(648258640)
c20 = FloatLib.FFromLong(154112043)
c21 = FloatLib.FFromLong(31936245)
c22 = FloatLib.FFromLong(-1986441000)
c23 = FloatLib.FFromLong(-284989606)
c24 = FloatLib.FFromLong(-1847456881)
c25 = FloatLib.FFromLong(-324187610)
c26 = FloatLib.FFromLong(1922895273)
c27 = FloatLib.FFromLong(-443753964)
c28 = FloatLib.FFromLong(2045500108)
c29 = FloatLib.FFromLong(1539610315)
c30 = FloatLib.FFromLong(-903621226)
c31 = FloatLib.FFromLong(-1371269749)
c32 = FloatLib.FFromLong(596628807)
c33 = FloatLib.FFromLong(-548048381)
c34 = FloatLib.FFromLong(-1262897697)
c35 = FloatLib.FFromLong(-798231825)
c36 = FloatLib.FFromLong(-201071568)
c37 = FloatLib.FFromLong(-859994195)
c38 = FloatLib.FFromLong(1264350247)
c39 = FloatLib.FFromLong(-1099097093)
c40 = FloatLib.FFromLong(319647407)
c41 = FloatLib.FFromLong(108218145)
c42 = FloatLib.FFromLong(1611203271)
u0 = FloatLib.FFromULong(0)
u1 = FloatLib.FFromULong(1)
u2 = FloatLib.FFromULong(4294967295)
u3 = FloatLib.FFromULong(2147483648)
u4 = FloatLib.FFromULong(4294967040)
u5 = FloatLib.FFromULong(16777217)
u6 = FloatLib.FFromULong(3000000000)
u7 = FloatLib.FFromULong(3132943648)
u8 = FloatLib.FFromULong(1927728186)
u9 = FloatLib.FFromULong(1236683272)
u10 = FloatLib.FFromULong(2615459068)
u11 = FloatLib.FFromULong(4209818936)
u12 = FloatLib.FFromULong(314395342)
u13 = FloatLib.FFromULong(507088656)
u14 = FloatLib.FFromULong(2198734780)
u15 = FloatLib.FFromULong(1795823848)
u16 = FloatLib.FFromULong(708506836)
t0 = FloatLib.FToLong(0)
t1 = FloatLib.FToLong(2147483648)
t2 = FloatLib.FToLong(1056964608)
t3 = FloatLib.FToLong(1065353215)
t4 = FloatLib.FToLong(1065353216)
t5 = FloatLib.FToLong(3212836864)
t6 = FloatLib.FToLong(1069547520)
t7 = FloatLib.FToLong(3217031168)
t8 = FloatLib.FToLong(1077516698)
t9 = FloatLib.FToLong(3225000346)
t10 = FloatLib.FToLong(1132455526)
t11 = FloatLib.FToLong(1199570816)
t12 = FloatLib.FToLong(1266679808)
t13 = FloatLib.FToLong(1325400063)
t14 = FloatLib.FToLong(1325400064)
t15 = FloatLib.FToLong(3472883712)
t16 = FloatLib.FToLong(3472883713)
t17 = FloatLib.FToLong(1328730206)
t18 = FloatLib.FToLong(3476213854)
t19 = FloatLib.FToLong(925353388)
t20 = FloatLib.FToLong(1206984804)
t21 = FloatLib.FToLong(3351307955)
t22 = FloatLib.FToLong(2139095040)
t23 = FloatLib.FToLong(4286578688)
t24 = FloatLib.FToLong(1307916940)
t25 = FloatLib.FToLong(3458593371)
t26 = FloatLib.FToLong(3416811748)
t27 = FloatLib.FToLong(3462117661)
t28 = FloatLib.FToLong(1302359123)
t29 = FloatLib.FToLong(1308381311)
t30 = FloatLib.FToLong(1292585267)
t31 = FloatLib.FToLong(1311967922)
t32 = FloatLib.FToLong(3450970060)
t33 = FloatLib.FToLong(1304051592)
t34 = FloatLib.FToLong(1295253259)
t35 = FloatLib.FToLong(1293443925)
tn = FloatLib.FToLong(2143289344)
q0 = FloatLib.FEq(0, 0)
q1 = FloatLib.FNe(0, 0)
q2 = FloatLib.FLt(0, 0)
q3 = FloatLib.FLe(0, 0)
q4 = FloatLib.FGt(0, 0)
q5 = FloatLib.FGe(0, 0)
q6 = FloatLib.FEq(0, 2147483648)
q7 = FloatLib.FNe(0, 2147483648)
q8 = FloatLib.FLt(0, 2147483648)
q9 = FloatLib.FLe(0, 2147483648)
q10 = FloatLib.FGt(0, 2147483648)
q11 = FloatLib.FGe(0, 2147483648)
q12 = FloatLib.FEq(0, 1065353216)
q13 = FloatLib.FNe(0, 1065353216)
q14 = FloatLib.FLt(0, 1065353216)
q15 = FloatLib.FLe(0, 1065353216)
q16 = FloatLib.FGt(0, 1065353216)
q17 = FloatLib.FGe(0, 1065353216)
q18 = FloatLib.FEq(0, 3212836864)
q19 = FloatLib.FNe(0, 3212836864)
q20 = FloatLib.FLt(0, 3212836864)
q21 = FloatLib.FLe(0, 3212836864)
q22 = FloatLib.FGt(0, 3212836864)
q23 = FloatLib.FGe(0, 3212836864)
q24 = FloatLib.FEq(0, 1073741824)
q25 = FloatLib.FNe(0, 1073741824)
q26 = FloatLib.FLt(0, 1073741824)
q27 = FloatLib.FLe(0, 1073741824)
q28 = FloatLib.FGt(0, 1073741824)
q29 = FloatLib.FGe(0, 1073741824)
q30 = FloatLib.FEq(0, 3221225472)
q31 = FloatLib.FNe(0, 3221225472)
q32 = FloatLib.FLt(0, 3221225472)
q33 = FloatLib.FLe(0, 3221225472)
q34 = FloatLib.FGt(0, 3221225472)
q35 = FloatLib.FGe(0, 3221225472)
q36 = FloatLib.FEq(0, 1056964608)
q37 = FloatLib.FNe(0, 1056964608)
q38 = FloatLib.FLt(0, 1056964608)
q39 = FloatLib.FLe(0, 1056964608)
q40 = FloatLib.FGt(0, 1056964608)
q41 = FloatLib.FGe(0, 1056964608)
q42 = FloatLib.FEq(0, 1900671690)
