(--CashBalance 
select as_of_date, 'SSB~CashBalance' SECURITY_ID, '' SEC_TRADE_ID,''  CUSIP, '' ISIN, '' OTH, '' MATURITY_DT 
, BOOK_CURRENCY_CODE, notional_currency_code CURRENCY_CODE, 'CASH' ASSET_TYPE_CODE, BOOK_CODE, ''  ACCOUNT_CODE, '' TRADE_STRATEGY_CODE 
, '' ISSUER_CNTRY, '' CNTRY_OF_RISK, '' EXT_REF, '' LEVEL_1_SECTOR_CODE, '' LEVEL_2_SECTOR_CODE, '' COLLATERAL_TYPE_CODE 
, '' QUANTITY, '' FACTOR, ACT_CASH_BAL_AMT CURR_NTL_AMT, ACT_CASH_BAL_BK_CCY_AMT CURR_NTL_BOOK_CCY_AMT, 100 PRICE, 0 ACCRUED, ACT_CASH_BAL_AMT MARKET_VALUE_AMT 
, ACT_CASH_BAL_BK_CCY_AMT MARKET_VALUE_BOOK_CCY_AMT, '' PENDING_CF_ADJ_AMT, '' PENDING_CF_ADJ_BK_CCY_AMT, '' PENDING_CF_AMT, '' PENDING_CF_BOOK_CCY_AMT 
, 0  CAPITAL_GL_AMT, 0 CAPITAL_GL_BOOK_CCY_AMT, FX_CASH CURRENCY_GL_AMT, 0 ACCRUAL_AMT, 0 ACCRUAL_BOOK_CCY_AMT, 0 INCOME_AMT, FX_CASH INCOME_BOOK_CCY_AMT 
      from 
( 
with  
dt_info 
as  
 ( 
   SELECT calc_start_date - 1 + DECODE (ROWNUM, 1, 0, ROWNUM - 1) AS perf_calc_date  
     FROM  
        (SELECT :asofdate AS calc_start_date FROM dual)  
     CONNECT BY LEVEL <= (:asofdate  - calc_start_date) + 2 
  ), 
cb_info 
as 
( 
  select dt_info.perf_calc_date as_of_date, book_currency_code,book_code,sm.notional_currency_code,SUM (daily_cash_chg_amt) daily_cash_bal  
  FROM  
    treasperf.daily_cash_account dca,  
    treasperf.security_master sm, 
    dt_info 
  where 
    dca.as_of_date<=dt_info.perf_calc_date 
    and sm.security_id=dca.security_id 
  group by dca.book_currency_code, dca.book_code, sm.notional_currency_code, dt_info.perf_calc_date 
) ,  
port_cum_cash_disc_v 
as 
(select pccd.book_currency_code, pccd.book_code, pccd.portfolio_type_code, pccd.cash_ccy_code, pccd.as_of_date, pccd.cash_disc_amt, pccd.adj_seq_nbr 
  from  
    treasperf.portfolio_cum_cash_disc pccd, 
    (select distinct book_currency_code, book_code, portfolio_type_code, pcd1.as_of_date,  
     max(run_dt) over (partition by book_currency_code, book_code, portfolio_type_code, pcd1.as_of_date) max_run_dt, 
     max(version_nbr) keep (dense_rank first order by run_dt desc nulls last) over (partition by book_currency_code, book_code, portfolio_type_code, as_of_date) max_version_nbr 
     from  
        treasperf.portfolio_cum_cash_disc pcd1, 
        dt_info 
     where 
       as_of_date=dt_info.perf_calc_date    
     ) max_dt_info 
   where 
    pccd.book_currency_code=max_dt_info.book_currency_code 
    and pccd.book_code=max_dt_info.book_code 
    and pccd.portfolio_type_code=max_dt_info.portfolio_type_code 
    and pccd.as_of_date=max_dt_info.as_of_date 
    and pccd.run_dt=max_dt_info.max_run_dt 
    and pccd.version_nbr=max_dt_info.max_version_nbr 
  )   
select * from (   
    select as_of_date, book_currency_code, book_code, notional_currency_code
 , nvl(sum(act_cash_bal_amt), 0) act_cash_bal_amt, nvl(sum(yest_cash_bal_amt), 0) yest_cash_bal_amt
, nvl(sum(cum_cash_disc_amt), 0) cum_cash_disc_amt, nvl(sum(yest_cum_cash_disc_amt),0) yest_cum_cash_disc_amt,   
      (nvl(sum(YEST_CASH_BAL_AMT),0)+nvl(sum(YEST_CUM_CASH_DISC_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_total 
      ,(nvl(sum(YEST_CASH_BAL_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_cash 
      ,(nvl(sum(YEST_CUM_CASH_DISC_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_cashDisc 
      , sum(act_cash_bal_bk_ccy_amt) act_cash_bal_bk_ccy_amt, sum(cum_cash_disc_bk_ccy_amt) cum_cash_disc_bk_ccy_amt 
    from 
    (   
        SELECT book_currency_code, book_code, cb_info.as_of_date, notional_currency_code, -1 * daily_cash_bal act_cash_bal_amt, -1 * daily_cash_bal * (er.rate/booker.rate) act_cash_bal_bk_ccy_amt, 
               -1*lag(daily_cash_bal) over (partition by book_currency_code, book_code, notional_currency_code order by cb_info.as_of_date) yest_cash_bal_amt,  
               NULL cum_cash_disc_amt, NULL cum_cash_disc_bk_ccy_amt, null yest_cum_cash_disc_amt, er.rate ntl_fx_rate, booker.rate bk_ccy_fx_rate, yer.rate yest_ntl_fx_rate, ybooker.rate yest_bk_ccy_fx_rate         
        FROM  
            treasperf.exchange_rate er,  
            treasperf.exchange_rate booker, 
            treasperf.exchange_rate yer,  
            treasperf.exchange_rate ybooker,     
            cb_info 
        where 
            booker.as_of_date=cb_info.as_of_date 
            and booker.currency_code=cb_info.book_currency_code 
            and er.as_of_date=cb_info.as_of_date 
            and er.currency_code=cb_info.notional_currency_code 
            and ybooker.as_of_date=booker.as_of_date-1 
            and ybooker.currency_code=booker.currency_code 
            and yer.as_of_date=er.as_of_date-1 
            and yer.currency_code=er.currency_code 
        union            
        SELECT pccd.book_currency_code, pccd.book_code, pccd.as_of_date,PCCD.CASH_CCY_CODE notional_currency_code,NULL act_cash_bal_amt, NULL act_cash_bal_bk_ccy_amt, NULL yest_act_cash_bal_amt,  
            -1 * cash_disc_amt cum_cash_disc_amt, -1 * (er.rate/booker.rate) * cash_disc_amt cum_cash_disc_bk_ccy_amt,  
            -1*lag(cash_disc_amt) over (partition by pccd.book_currency_code, pccd.book_code, PCCD.CASH_CCY_CODE order by pccd.as_of_date) yest_cum_cash_disc_amt, 
            er.rate ntl_fx_rate, booker.rate bk_ccy_fx_rate, yer.rate yest_ntl_fx_rate, ybooker.rate yest_bk_ccy_fx_rate      
        FROM  
            port_cum_cash_disc_v pccd,  
            treasperf.exchange_rate er,  
            treasperf.exchange_rate booker, 
            treasperf.exchange_rate yer,  
            treasperf.exchange_rate ybooker              
        WHERE  
            er.currency_code = PCCD.CASH_CCY_CODE  
            AND er.as_of_date = PCCD.AS_OF_DATE  
            AND booker.currency_code = pccd.book_currency_code  
            AND booker.as_of_date = pccd.as_of_date  
            and ybooker.as_of_date=booker.as_of_date-1 
            and ybooker.currency_code=booker.currency_code 
            and yer.as_of_date=er.as_of_date-1 
            and yer.currency_code=er.currency_code 
            and pccd.portfolio_type_code = 'A' 
    )   group by as_of_date, book_currency_code, book_code, notional_currency_code      
) where as_of_date=:asofdate and book_code not in ('P0Cash','P2INDEX') ) 
) 
UNION 
(--CashDiscrepancy 
select as_of_date, 'Cum~Cash~Discrepancy' SECURITY_ID, '' SEC_TRADE_ID,''  CUSIP, '' ISIN, '' OTH, '' MATURITY_DT 
, BOOK_CURRENCY_CODE, notional_currency_code CURRENCY_CODE, 'CASH' ASSET_TYPE_CODE, BOOK_CODE, ''  ACCOUNT_CODE, '' TRADE_STRATEGY_CODE 
, '' ISSUER_CNTRY, '' CNTRY_OF_RISK, '' EXT_REF, '' LEVEL_1_SECTOR_CODE, '' LEVEL_2_SECTOR_CODE, '' COLLATERAL_TYPE_CODE 
, '' QUANTITY, '' FACTOR, CUM_CASH_DISC_AMT CURR_NTL_AMT, CUM_CASH_DISC_BK_CCY_AMT CURR_NTL_BOOK_CCY_AMT, 100 PRICE, 0 ACCRUED, CUM_CASH_DISC_AMT MARKET_VALUE_AMT 
, CUM_CASH_DISC_BK_CCY_AMT MARKET_VALUE_BOOK_CCY_AMT, '' PENDING_CF_ADJ_AMT, '' PENDING_CF_ADJ_BK_CCY_AMT, '' PENDING_CF_AMT, '' PENDING_CF_BOOK_CCY_AMT 
, 0  CAPITAL_GL_AMT, 0 CAPITAL_GL_BOOK_CCY_AMT, FX_CASHDISC CURRENCY_GL_AMT, 0 ACCRUAL_AMT, 0 ACCRUAL_BOOK_CCY_AMT, 0 INCOME_AMT, FX_CASHDISC INCOME_BOOK_CCY_AMT 
      from 
( 
with  
dt_info 
as  
 ( 
   SELECT calc_start_date - 1 + DECODE (ROWNUM, 1, 0, ROWNUM - 1) AS perf_calc_date  
     FROM  
        (SELECT :asofdate  AS calc_start_date FROM dual)  
     CONNECT BY LEVEL <= (:asofdate - calc_start_date) + 2 
  ), 
cb_info 
as 
( 
  select dt_info.perf_calc_date as_of_date, book_currency_code,book_code,sm.notional_currency_code,SUM (daily_cash_chg_amt) daily_cash_bal  
  FROM  
    treasperf.daily_cash_account dca,  
    treasperf.security_master sm, 
    dt_info 
  where 
    dca.as_of_date<=dt_info.perf_calc_date 
    and sm.security_id=dca.security_id 
  group by dca.book_currency_code, dca.book_code, sm.notional_currency_code, dt_info.perf_calc_date 
) ,  
port_cum_cash_disc_v 
as 
(select pccd.book_currency_code, pccd.book_code, pccd.portfolio_type_code, pccd.cash_ccy_code, pccd.as_of_date, pccd.cash_disc_amt, pccd.adj_seq_nbr 
  from  
    treasperf.portfolio_cum_cash_disc pccd, 
    (select distinct book_currency_code, book_code, portfolio_type_code, pcd1.as_of_date,  
     max(run_dt) over (partition by book_currency_code, book_code, portfolio_type_code, pcd1.as_of_date) max_run_dt, 
     max(version_nbr) keep (dense_rank first order by run_dt desc nulls last) over (partition by book_currency_code, book_code, portfolio_type_code, as_of_date) max_version_nbr 
     from  
        treasperf.portfolio_cum_cash_disc pcd1, 
        dt_info 
     where 
       as_of_date=dt_info.perf_calc_date    
     ) max_dt_info 
   where 
    pccd.book_currency_code=max_dt_info.book_currency_code 
    and pccd.book_code=max_dt_info.book_code 
    and pccd.portfolio_type_code=max_dt_info.portfolio_type_code 
    and pccd.as_of_date=max_dt_info.as_of_date 
    and pccd.run_dt=max_dt_info.max_run_dt 
    and pccd.version_nbr=max_dt_info.max_version_nbr 
  )   
select * from (   
    select as_of_date, book_currency_code, book_code, notional_currency_code, nvl(sum(act_cash_bal_amt), 0) act_cash_bal_amt, nvl(sum(yest_cash_bal_amt), 0) yest_cash_bal_amt, nvl(sum(cum_cash_disc_amt), 0) cum_cash_disc_amt, nvl(sum(yest_cum_cash_disc_amt),0) yest_cum_cash_disc_amt,   
      (nvl(sum(YEST_CASH_BAL_AMT),0)+nvl(sum(YEST_CUM_CASH_DISC_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_total 
      ,(nvl(sum(YEST_CASH_BAL_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_cash 
      ,(nvl(sum(YEST_CUM_CASH_DISC_AMT),0))*((max(ntl_fx_rate)/max(bk_ccy_fx_rate))-(max(yest_ntl_fx_rate)/max(yest_bk_ccy_fx_rate))) fx_cashDisc 
      , sum(act_cash_bal_bk_ccy_amt) act_cash_bal_bk_ccy_amt, sum(cum_cash_disc_bk_ccy_amt) cum_cash_disc_bk_ccy_amt 
    from 
    (   
        SELECT book_currency_code, book_code, cb_info.as_of_date, notional_currency_code, -1 * daily_cash_bal act_cash_bal_amt, -1 * daily_cash_bal * (er.rate/booker.rate) act_cash_bal_bk_ccy_amt, 
               -1*lag(daily_cash_bal) over (partition by book_currency_code, book_code, notional_currency_code order by cb_info.as_of_date) yest_cash_bal_amt,  
               NULL cum_cash_disc_amt, NULL cum_cash_disc_bk_ccy_amt, null yest_cum_cash_disc_amt, er.rate ntl_fx_rate, booker.rate bk_ccy_fx_rate, yer.rate yest_ntl_fx_rate, ybooker.rate yest_bk_ccy_fx_rate         
        FROM  
            treasperf.exchange_rate er,  
            treasperf.exchange_rate booker, 
            treasperf.exchange_rate yer,  
            treasperf.exchange_rate ybooker,     
            cb_info 
        where 
            booker.as_of_date=cb_info.as_of_date 
            and booker.currency_code=cb_info.book_currency_code 
            and er.as_of_date=cb_info.as_of_date 
            and er.currency_code=cb_info.notional_currency_code 
            and ybooker.as_of_date=booker.as_of_date-1 
            and ybooker.currency_code=booker.currency_code 
            and yer.as_of_date=er.as_of_date-1 
            and yer.currency_code=er.currency_code 
        union            
        SELECT pccd.book_currency_code, pccd.book_code, pccd.as_of_date,PCCD.CASH_CCY_CODE notional_currency_code,NULL act_cash_bal_amt, NULL act_cash_bal_bk_ccy_amt, NULL yest_act_cash_bal_amt,  
            -1 * cash_disc_amt cum_cash_disc_amt, -1 * (er.rate/booker.rate) * cash_disc_amt cum_cash_disc_bk_ccy_amt,  
            -1*lag(cash_disc_amt) over (partition by pccd.book_currency_code, pccd.book_code, PCCD.CASH_CCY_CODE order by pccd.as_of_date) yest_cum_cash_disc_amt, 
            er.rate ntl_fx_rate, booker.rate bk_ccy_fx_rate, yer.rate yest_ntl_fx_rate, ybooker.rate yest_bk_ccy_fx_rate      
        FROM  
            port_cum_cash_disc_v pccd,  
            treasperf.exchange_rate er,  
            treasperf.exchange_rate booker, 
            treasperf.exchange_rate yer,  
            treasperf.exchange_rate ybooker              
        WHERE  
            er.currency_code = PCCD.CASH_CCY_CODE  
            AND er.as_of_date = PCCD.AS_OF_DATE  
            AND booker.currency_code = pccd.book_currency_code  
            AND booker.as_of_date = pccd.as_of_date  
            and ybooker.as_of_date=booker.as_of_date-1 
            and ybooker.currency_code=booker.currency_code 
            and yer.as_of_date=er.as_of_date-1 
            and yer.currency_code=er.currency_code 
            and pccd.portfolio_type_code = 'A' 
    )   group by as_of_date, book_currency_code, book_code, notional_currency_code      
) where as_of_date=:asofdate and book_code not in ('P0Cash','P2INDEX') )  
) order by book_code, security_id, currency_code

