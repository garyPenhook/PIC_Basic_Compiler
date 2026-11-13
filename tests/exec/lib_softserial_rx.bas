' expect: SSR_SSR_A=85 SSR_SSR_B=195 SSR_SSR_C=65534 SSR_SSR_D=1 SSR_SSR_E=65535 SSR_SSR_G=1
' stim: lib_softserial_rx.stim.toml
' devices: 18F27Q10
' Software serial receive (9600 baud on RB1, 64 MHz): three characters sent as the stimulus file says (0x55 and 0xC3,
' then 0x0F with a low stop bit, made by `scripts/softserial_rx_sweep.py --print-stim --bad-stop`): the first two are
' returned, the third is -2 (framing error), then a read that times out (-1). Global interrupts, set before, are
' still set after the reads (`SoftHoldIrq` default: held off during a byte and put back). The baud-rate window and the
' transmit timing of every part are checked by `scripts/test_softserial.py`.
Program Ssr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "softserial"
Dim ssr_a As Integer
Dim ssr_b As Integer
Dim ssr_c As Integer
Dim ssr_d As Boolean
Dim ssr_e As Integer
Dim ssr_g As Boolean
Dim gie As INTCON.7
Dim ok As Boolean
ok = SoftInit(255, 9, 9600, False)
gie = 1
ssr_a = SoftReadByte(50)
ssr_b = SoftReadByte(50)
ssr_c = SoftReadByte(50)
ssr_e = SoftReadByte(1)
ssr_g = gie = 1
ssr_d = ok
