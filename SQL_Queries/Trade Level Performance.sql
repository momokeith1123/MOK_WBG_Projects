SELECT thd.as_of_date, thd.run_dt, thd.version_nbr, thd.security_id, thd.trade_id, sm.asset_type_code, sm.NOTIONAL_CURRENCY_CODE, sm.maturity_dt,
t.book_currency_code, t.book_code, t_def.account_code, t.portfolio_type_code, 
-- sdr_bal.CURRENCYCODE AS SDR_CURRENCYCODE, sdr_bal.OUTSTANDINGAMT AS SDR_OUTSTANDINGAMT, sdr_bal.OUTSTANDINGUSDAMT AS SDR_OUTSTANDINGUSDAMT, 
thd.NOTIONAL_BEG_BOOK_CCY_AMT, thd.notional_chg_book_ccy_amt, thd.notional_beg_book_ccy_amt + thd.notional_chg_book_ccy_amt curr_ntl_book_ccy_amt,
thd.MARKET_VALUE_AMT, thd.MARKET_VALUE_BOOK_CCY_AMT, thd.RECV_MKT_VAL_AMT, thd.RECV_MKT_VAL_BOOK_CCY_AMT, 
thd.pending_cf_book_ccy_amt, thd.pending_cf_adj_amt, thd.pending_cf_adj_bk_ccy_amt,
tp1.ACCRUAL_BOOK_CCY_AMT, tp1.CAPITAL_GL_BOOK_CCY_AMT, tp1.CUM_CAPITAL_GL_AMT,
tp1.CURRENCY_GL_AMT, tp1.DAILY_CF_BOOK_CCY_AMT, tp1.FEE_BOOK_CCY_AMT, tp1.INCOME_AMT, tp1.INCOME_BOOK_CCY_AMT,
tp1.INCOME_DISCREPANCY_AMT, tp1.RECEIVABLE_INT_BOOK_CCY_AMT
FROM treasperf.trade_holding_detail thd

JOIN (SELECT DISTINCT tp.security_id, tp.trade_id, tp.as_of_date,
MAX(tp.run_dt) OVER (PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_run_dt,
MAX(tp.version_nbr) KEEP (DENSE_RANK FIRST ORDER BY tp.run_dt DESC NULLS LAST) OVER (PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_version_nbr
FROM treasperf.trade_holding_detail tp
WHERE trade_status_code IN ('P', 'S')) max_run
ON thd.security_id = max_run.security_id AND thd.trade_id = max_run.trade_id
AND thd.as_of_date = max_run.as_of_date AND thd.run_dt = max_run.max_run_dt
AND thd.version_nbr = max_run.max_version_nbr

LEFT JOIN (SELECT SECURITY_ID, MATURITY_DT, asset_type_code, NOTIONAL_CURRENCY_CODE FROM treasperf.security_master) sm
ON thd.security_id = sm.SECURITY_ID

LEFT JOIN (SELECT SECURITY_ID, TRADE_ID, book_currency_code, book_code, portfolio_type_code, ACTIVE_IND FROM treasperf.trade) t
ON thd.security_id = t.SECURITY_ID AND thd.trade_id = t.trade_id

INNER JOIN (SELECT SECURITY_ID, TRADE_ID, as_of_date, run_dt, version_nbr, ACCRUAL_BOOK_CCY_AMT,
CAPITAL_GL_BOOK_CCY_AMT, CUM_CAPITAL_GL_AMT, CURRENCY_GL_AMT, DAILY_CF_BOOK_CCY_AMT, FEE_BOOK_CCY_AMT,
INCOME_AMT, INCOME_BOOK_CCY_AMT, INCOME_DISCREPANCY_AMT, RECEIVABLE_INT_BOOK_CCY_AMT
FROM treasperf.trade_perf) tp1
ON thd.security_id = tp1.security_id AND thd.trade_id = tp1.trade_id
AND thd.as_of_date = tp1.as_of_date AND thd.run_dt = tp1.run_dt
AND thd.version_nbr = tp1.version_nbr

--LEFT JOIN (SELECT TRADEID, ASOFDATE, CURRENCYCODE, OUTSTANDINGAMT, OUTSTANDINGUSDAMT FROM DATAREP.SDR_OUTSTANDINGBALANCE
--WHERE TRADETYPECODE = 'BOND' AND ASOFMONTH = '  ') sdr_bal
--ON thd.trade_id = sdr_bal.tradeid AND thd.as_of_date = sdr_bal.asofdate

LEFT JOIN (SELECT distinct security_id, trade_id, account_code from treasperf.portfolio_defn_mv
WHERE (account_end_dt is null or account_end_dt>=:edate) AND (account_eff_dt is null or account_eff_dt<=:edate)) t_def
ON thd.security_id = t_def.security_id AND thd.trade_id = t_def.trade_id

WHERE t.ACTIVE_IND = 'Y'
AND thd.AS_OF_DATE BETWEEN :sdate AND :edate
AND t.portfolio_type_code = 'A'
--AND BOOK_CODE = 'P1' AND t_def.ACCOUNT_CODE = 'GRE'
--AND thd.trade_id = '278502I'
--AND thd.RECV_MKT_VAL_BOOK_CCY_AMT <> 0 AND thd.MARKET_VALUE_BOOK_CCY_AMT <> 0 AND thd.AS_OF_DATE = '01-Jul-2025'
-- AND thd.AS_OF_DATE = '31-Jan-2026' AND ACCOUNT_CODE = 'E_ALTAFL' AND BOOK_CODE = 'P1'
--AND thd.pending_cf_adj_bk_ccy_amt <> 0
ORDER BY thd.AS_OF_DATE
