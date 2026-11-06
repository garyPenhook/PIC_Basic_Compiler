' expect: PP_PP_R=1 PP_PP_V=3
' devices: 18F27Q10
' Predefined preprocessor names and #variable (18F27Q10: 2 MSSP, 2 RCnSTA, 2 CCP, 2 comparators, 3 ports).
Program Pp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#variable N = 1
#variable N = N + 2
#if N = 3 and _mssp = 2 and _ccp = 2 and _comparator = 2 and _ports = 3 and _adc = 1 and _usart = 2 and _flash_write and _core = "pic18" and _maxrom = 131072 and _usb = 0 and _eccp = 0 and _adres = 10
Const Ok = 1
#else
Const Ok = 0
#endif
Dim pp_r As Byte
Dim pp_v As Byte
pp_r = Ok
pp_v = 3
