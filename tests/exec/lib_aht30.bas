' expect: LA_START=4 LA_FETCH=4 LA_MEAS=4 LA_T=1234 LA_RH=4321 LA_OK=1 LA_T2=1234
Program La
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Include "aht30"
Dim start As Byte
Dim fetch As Byte
Dim meas As Byte
Dim t As Integer
Dim rh As Word
Dim ok As Byte
Dim st2 As Byte
Dim ft2 As Byte
Dim t2 As Integer
t = 1234
rh = 4321
' I2c not initialised: every routine answers 4 and leaves the outputs alone.
Aht30.Aht30Init()
start = Aht30.Aht30Start()
fetch = Aht30.Aht30Fetch(t, rh)
meas = Aht30.Aht30Measure(t, rh)
' Bus set up, nothing on it (the simulator has no pull-ups, so no acknowledge or a timeout, in
' bounded time): outputs untouched.
ok = I2c.I2cInit(100000, 19, 20)
st2 = Aht30.Aht30Start()
t2 = t
ft2 = Aht30.Aht30Fetch(t, rh)
