select CURRENCY_CODE, AS_OF_DATE, RATE as FX_RATE
from treasperf.exchange_rate
WHERE AS_OF_DATE =:asofDate