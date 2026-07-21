with 
 port_defn_info 
 as 
 ( 
 (select distinct security_id, cusip, isin, oth, trade_id, asset_type_code, external_trade_id external_trade_id, notional_currency_code, nvl(trade_strategy_code, 'NO_STG') trade_strategy_code, book_code, book_currency_code, portfolio_type_code, nvl(account_code, 'RESIDUAL') account_code, coll_cntry_code, issuer_cntry_code, level_1_sector_code, level_2_sector_code, collateral_type_code, ext_ref, maturity_dt, trade_dt, settlement_dt, 
   (case when asset_type_code='BOND' then replace(replace(security_id, asset_sub_type_code||'~'||notional_currency_code,''),'~','') 
    when asset_type_code in ('REPO','SWAP','SWOPT','FXOPT') then substr(security_id, length(asset_type_code)+2, instr(security_id, '~',length(asset_type_code)+2)-length(asset_type_code)-2) 
    when asset_type_code like 'FX%' or asset_type_code='MM' then  replace(replace(replace(replace(security_id, asset_sub_type_code,''),'~',''),'Bought', ''),'Sold','') 
   Else '' end) secid 
 from 
 treasperf.portfolio_defn_mv 
 WHERE 
  (account_eff_dt is null or account_eff_dt<= :asofdate  ) and (account_end_dt is null or account_end_dt>= :asofdate  ) and portfolio_type_code='A' and desk_code in ('LAM','COLLMGT')) 
 ), 
 holding_info 
 as 
 ( 
 select thd.as_of_date, thd.security_id, port_defn.secid, max(port_defn.external_trade_id) external_trade_id, max(port_defn.maturity_dt) maturity_dt, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code, max(port_defn.trade_strategy_code) trade_strategy_code, max(issuer_cntry_code) ISSUER_CNTRY, 
  max(coll_cntry_code) coll_cntry_code, max(ext_ref) ext_ref, max(level_1_sector_code) level_1_sector_code, max(level_2_sector_code) level_2_sector_code, max(collateral_type_code) collateral_type_code, max(cusip) cusip, max(isin) isin, max(oth) oth, 
  sum(PENDING_CF_ADJ_AMT+PENDING_CF_AMT) curr_ntl_amt, sum(PENDING_CF_ADJ_AMT+PENDING_CF_AMT) market_value_amt, 
  sum(PENDING_CF_ADJ_BK_CCY_AMT+PENDING_CF_BOOK_CCY_AMT) market_value_book_ccy_amt, sum(PENDING_CF_ADJ_BK_CCY_AMT+PENDING_CF_BOOK_CCY_AMT) curr_ntl_book_ccy_amt, 0 curr_res_ntl_amt, 
  0 pending_cf_adj_amt, 0 pending_cf_adj_bk_ccy_amt,  0 pending_cf_amt, 0 pending_cf_book_ccy_amt, 0 capital_gl_amt, 0 capital_gl_book_ccy_amt, 0 currency_gl_amt, 0 accrual_amt, 0 accrual_book_ccy_amt, 0 income_amt, 0 income_book_ccy_amt 
from 
  treasperf.trade_holding_detail  thd, 
  treasperf.exchange_rate x, 
(SELECT DISTINCT tp.security_id, tp.trade_id, tp.as_of_date, 
                   MAX (tp.run_dt) OVER ( PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_run_dt, 
                   MAX ( tp.version_nbr) KEEP (DENSE_RANK FIRST ORDER BY tp.run_dt DESC NULLS LAST) OVER ( PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_version_nbr 
              FROM treasperf.trade_holding_detail tp 
             WHERE trade_status_code IN ('P', 'S') and as_of_date= :asofdate
 ) max_dt_info, port_defn_info port_defn 
 WHERE 
  thd.security_id = max_dt_info.security_id 
  and thd.trade_id=max_dt_info.trade_id 
  and thd.as_of_date=max_dt_info.as_of_date 
  and thd.run_dt=max_dt_info.max_run_dt 
  and thd.version_nbr=max_dt_info.max_version_nbr 
  and max_dt_info.security_id=port_defn.security_id 
  and max_dt_info.trade_id=port_defn.trade_id 
  and port_defn.portfolio_type_code='A' 
  and x.currency_code=port_defn.book_currency_code 
  and x.as_of_date=thd.as_of_date 
  and port_defn.asset_type_code NOT IN ('SWOPT', 'SWAP', 'FXFWD', 'FXOPT') 
group by thd.as_of_date, thd.security_id, port_defn.secid, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code 
having Abs(Sum(PENDING_CF_ADJ_AMT + PENDING_CF_AMT)) > 1 
) , 
pending_cash 
as 
( 
SELECT :asofdate as_of_date, t.security_id, T.secid SEC_TRADE_ID, t.account_code, 
       max(C.CF_END_DATE) maturity_dt, c.cf_ccy_code currency_code, t.ASSET_TYPE_CODE, T.BOOK_CURRENCY_CODE, T.BOOK_CODE, 
       'PendingCASH' MODIFIED_ASSET_TYPE_CODE, 
        sum(c.cf_adj_amt) market_value_amt, sum(c.cf_adj_amt * x.rate) market_value_book_ccy_amt,  sum(c.cf_adj_amt) curr_ntl_amt, sum(c.cf_adj_amt * x.rate) curr_ntl_book_ccy_amt, max(t.trade_strategy_code) trade_strategy_code, max(issuer_cntry_code) ISSUER_CNTRY, 
  max(coll_cntry_code) coll_cntry_code, max(ext_ref) ext_ref, max(level_1_sector_code) level_1_sector_code, max(level_2_sector_code) level_2_sector_code, max(collateral_type_code) collateral_type_code, max(cusip) cusip, max(isin) isin, max(oth) oth 
from 
   port_defn_info t, 
    treasperf.cash_flow_adj c, 
    treasperf.security_master s, 
    treasperf.exchange_rate x 
WHERE t.security_id = c.security_id 
        AND t.security_id = s.security_id 
        AND t.trade_id = c.trade_id 
        AND c.cf_start_date <= :asofdate 
        AND c.cf_end_date > :asofdate
        AND x.as_of_date = :asofdate
        AND c.cf_ccy_code = x.currency_code 
        AND c.cf_adj_amt <> 0 
        AND c.active_ind = 'Y' 
        AND t.portfolio_type_code = 'A' 
        AND s.asset_type_code IN ('SWOPT', 'SWAP', 'FXFWD', 'FXOPT', 'BOND') 
        AND (   t.book_code IN ('P0', 'P1', 'P2', 'P7IDA', 'P8', 'P9', 'BJMA') OR t.book_code LIKE 'P6%') 
        group by t.security_id, t.secid, c.cf_ccy_code, t.portfolio_type_code, t.book_currency_code, t.book_code, t.account_code, t.asset_type_code 
        having Abs(Sum(c.cf_adj_amt)) > 1 
) 
select as_of_date, ' ' security_id, sec_trade_id, ' ' cusip, ' ' ISIN, ' ' OTH, maturity_dt, book_currency_code, currency_code, asset_type_code, book_code, account_code, trade_strategy_code, 
        ' ' issuer_cntry, ' ' cntry_of_risk, ' ' ext_ref, ' ' level_1_sector_code, ' ' level_2_sector_code, collateral_type_code, quantity, factor, curr_ntl_amt, curr_ntl_book_ccy_amt, price, accrued, 
        market_value_amt, market_value_book_ccy_amt 
 from ( 
select holding_info.as_of_date, holding_info.security_id security_id, holding_info.secid sec_trade_id, holding_info.cusip, holding_info.ISIN, holding_info.OTH, pending_cash.maturity_dt, holding_info.book_currency_code, holding_info.notional_currency_code currency_code, 'PendingCASH' asset_type_code, holding_info.book_code, holding_info.account_code, holding_info.trade_strategy_code, 
        holding_info.issuer_cntry, holding_info.issuer_cntry cntry_of_risk, holding_info.ext_ref, holding_info.level_1_sector_code, holding_info.level_2_sector_code, holding_info.collateral_type_code, '' quantity, '' factor, holding_info.curr_ntl_amt, holding_info.curr_ntl_book_ccy_amt, 100 price, '' accrued, 
        holding_info.curr_ntl_amt market_value_amt, holding_info.curr_ntl_book_ccy_amt market_value_book_ccy_amt 
from 
 holding_info, pending_cash 
where 
  pending_cash.as_of_date = holding_info.as_of_date 
  and pending_cash.security_id=holding_info.security_id 
  and pending_cash.sec_trade_id=holding_info.secid 
  and pending_cash.book_code=holding_info.book_code 
  and pending_cash.account_code=holding_info.account_code 
  and pending_cash.trade_strategy_code=holding_info.trade_strategy_code 
Union all 
select as_of_date, security_id, sec_trade_id, cusip, ISIN, OTH, maturity_dt, book_currency_code, currency_code, modified_asset_type_code asset_type_code, book_code, account_code, trade_strategy_code, 
        issuer_cntry, issuer_cntry cntry_of_risk, ext_ref, level_1_sector_code, level_2_sector_code, collateral_type_code, '' quantity, '' factor, curr_ntl_amt, curr_ntl_book_ccy_amt, 100 price, '' accrued, 
        curr_ntl_amt market_value_amt, curr_ntl_book_ccy_amt market_value_book_ccy_amt 
from 
 pending_cash 
where asset_type_code in ('SWOPT', 'SWAP', 'FXFWD', 'FXOPT')  
 ) 
