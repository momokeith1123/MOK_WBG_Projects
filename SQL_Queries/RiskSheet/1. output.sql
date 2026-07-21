with 
port_defn_info 
as 
( 
(select distinct security_id, cusip, isin, oth, trade_id, asset_type_code, external_trade_id external_trade_id, notional_currency_code, nvl(trade_strategy_code, 'NO_STG') trade_strategy_code, book_code, book_currency_code, portfolio_type_code, nvl(account_code, book_code) account_code, coll_cntry_code, issuer_cntry_code, level_1_sector_code, level_2_sector_code, collateral_type_code, ext_ref, maturity_dt, trade_dt, settlement_dt, 
  (case when asset_type_code='BOND' then replace(replace(security_id, asset_sub_type_code||'~'||notional_currency_code,''),'~','') 
   when asset_type_code in ('REPO','SWAP','SWOPT','FXOPT') then substr(security_id, length(asset_type_code)+2, instr(security_id, '~',length(asset_type_code)+2)-length(asset_type_code)-2) 
   when asset_type_code like 'FX%' or asset_type_code='MM' then  replace(replace(replace(replace(security_id, asset_sub_type_code,''),'~',''),'Bought', ''),'Sold','') 
  Else '' end) secid 
from  
treasperf.portfolio_defn_mv 
where  
 (account_eff_dt is null or account_eff_dt<=:asofDate) and (account_end_dt is null or account_end_dt>=:asofDate) and portfolio_type_code='A' and desk_code in ('LAM','COLLMGT'))  
), 
holding_info 
as 
( 
select thd.as_of_date, thd.security_id, port_defn.secid, max(port_defn.external_trade_id) external_trade_id, max(port_defn.maturity_dt) maturity_dt, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code, max(port_defn.trade_strategy_code) trade_strategy_code, max(issuer_cntry_code) ISSUER_CNTRY, 
 max(coll_cntry_code) coll_cntry_code, max(ext_ref) ext_ref, max(level_1_sector_code) level_1_sector_code, max(level_2_sector_code) level_2_sector_code, max(collateral_type_code) collateral_type_code, max(cusip) cusip, max(isin) isin, max(oth) oth, 
 (case when sum(THD.NOTIONAL_BEG_AMT+THD.NOTIONAL_CHG_AMT)=0 and asset_type_code not in ('FUT','LOPT') then 1 else sum(THD.NOTIONAL_BEG_AMT+THD.NOTIONAL_CHG_AMT) end) curr_ntl_amt, sum(THD.NOTIONAL_BEG_AMT+THD.NOTIONAL_CHG_AMT) current_ntl_amt, sum(THD.NOTIONAL_BEG_BOOK_CCY_AMT+THD.NOTIONAL_CHG_BOOK_CCY_AMT) curr_ntl_book_ccy_amt, 
        sum(thd.market_value_amt) market_value_amt, sum(THD.MARKET_VALUE_BOOK_CCY_AMT) MARKET_VALUE_BOOK_CCY_AMT, sum(THD.PENDING_CF_ADJ_AMT) PENDING_CF_ADJ_AMT, sum(THD.PENDING_CF_ADJ_BK_CCY_AMT) PENDING_CF_ADJ_BK_CCY_AMT, sum(THD.PENDING_CF_AMT) PENDING_CF_AMT, sum(THD.PENDING_CF_BOOK_CCY_AMT) PENDING_CF_BOOK_CCY_AMT,  
        sum(tp.CAPITAL_GL_AMT) CAPITAL_GL_AMT, sum(tp.CAPITAL_GL_BOOK_CCY_AMT) CAPITAL_GL_BOOK_CCY_AMT,  
        sum(tp.CURRENCY_GL_AMT) CURRENCY_GL_AMT, sum(tp.ACCRUAL_AMT) ACCRUAL_AMT, sum(tp.ACCRUAL_BOOK_CCY_AMT) ACCRUAL_BOOK_CCY_AMT, sum(tp.INCOME_AMT+tp.fee_amt) INCOME_AMT, sum(tp.INCOME_BOOK_CCY_AMT+tp.fee_book_ccy_amt) INCOME_BOOK_CCY_AMT, 
  sum((case when port_defn.asset_type_code='BOND' and port_defn.settlement_dt<thd.as_of_date then (THD.NOTIONAL_BEG_AMT+THD.NOTIONAL_CHG_AMT) else 0 end)) curr_res_ntl_amt           
from 
 treasperf.trade_holding_detail  thd, 
 treasperf.trade_perf tp, 
(SELECT DISTINCT tp.security_id, tp.trade_id, tp.as_of_date, 
                  MAX (tp.run_dt) OVER ( PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_run_dt, 
                  MAX ( tp.version_nbr) KEEP (DENSE_RANK FIRST ORDER BY tp.run_dt DESC NULLS LAST) OVER ( PARTITION BY tp.security_id, tp.trade_id, tp.as_of_date) max_version_nbr 
             FROM treasperf.trade_holding_detail tp 
            WHERE trade_status_code IN ('P', 'S') and as_of_date=:asofDate
) max_dt_info, port_defn_info port_defn 
where    
 thd.security_id=max_dt_info.security_id 
 and thd.trade_id=max_dt_info.trade_id 
 and thd.as_of_date=max_dt_info.as_of_date 
 and thd.run_dt=max_dt_info.max_run_dt 
 and thd.version_nbr=max_dt_info.max_version_nbr 
 and TP.SECURITY_ID=thd.security_id 
 and tp.trade_id=thd.trade_id 
 and tp.as_of_date=thd.as_of_date 
 and tp.run_dt=thd.run_dt 
 and tp.version_nbr=thd.version_nbr 
 and max_dt_info.security_id=port_defn.security_id 
 and max_dt_info.trade_id=port_defn.trade_id 
 and port_defn.portfolio_type_code='A'  
group by thd.as_of_date, thd.security_id, port_defn.secid, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code   
), 
settle_risk 
as 
( 
  select trs.as_of_date, trs.security_id, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code, 
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='ALL' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TOTAL_PARALLEL_DV01, 
     sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='ALL' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TOTAL_PARALLEL_CONV, 
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code<>'ALL' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TOTAL_DV01, 
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='1D' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_D_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='1D' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_D_CONV, 
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='1W' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_W_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='1W' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_W_CONV, 
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='1M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_M_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='1M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_M_CONV,                      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='3M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THREE_M_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='3M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THREE_M_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='6M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SIX_M_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='6M' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SIX_M_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='1Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='1Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_ONE_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='2Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWO_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='2Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWO_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='3Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THREE_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='3Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THREE_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='4Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FOUR_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='4Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FOUR_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='5Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FIVE_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='5Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FIVE_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='6Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SIX_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='6Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SIX_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='7Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SEVEN_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='7Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_SEVEN_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='8Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_EIGHT_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='8Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_EIGHT_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='9Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_NINE_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='9Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_NINE_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='10Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TEN_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='10Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TEN_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='15Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FIFTN_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='15Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_FIFTN_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='20Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWNTY_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='20Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWNTY_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='25Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWNTYFV_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='25Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_TWNTYFV_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRDT' and rf.term_bucket_code='30Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THIRTY_YR_DV01, sum(CASE WHEN rf.risk_factor_type_code='KRCT' and rf.term_bucket_code='30Y' THEN trs.risk_amt * er.rate ELSE 0 END) SETTLE_THIRTY_YR_CONV,      
     sum(CASE WHEN rf.risk_factor_type_code='KRCT' THEN trs.risk_amt * er.rate ELSE 0 END)  SETTLE_convexity   
  from  
      treasperf.trade_risk_sensitivity trs, 
      treasperf.exchange_rate er, 
      treasperf.risk_factor rf, 
      port_defn_info port_defn, 
      (select distinct trs1.as_of_date, trs1.security_id, trs1.trade_id, max(trs1.run_dt) over (partition by trs1.security_id, trs1.trade_id, trs1.as_of_date) max_run_dt, 
             max(trs1.version_nbr) keep (dense_rank first order by trs1.run_dt desc nulls last) over (partition by trs1.security_id, trs1.trade_id, trs1.as_of_date) max_version_nbr  
      from TREASPERF.TRADE_RISK_SENSITIVITY trs1 
      where trs1.as_of_date=:asofDate) max_info 
  where  
         trs.security_id=max_info.security_id 
     and trs.trade_id=max_info.trade_id 
     and TRS.AS_OF_DATE=max_info.as_of_date 
     and TRS.RUN_DT=max_info.max_run_dt 
     and TRS.VERSION_NBR=max_info.max_version_nbr 
     and trs.security_id=port_defn.security_id 
     and trs.trade_id=port_defn.trade_id 
     and port_defn.asset_type_code='BOND' 
     and RF.RISK_FACTOR_ID=TRS.RISK_FACTOR_ID 
     and er.as_of_Date=trs.as_of_date 
     and ER.CURRENCY_CODE=RF.CURRENCY_CODE 
     and RF.CURVE_ID='Total' 
  group by trs.as_of_date, trs.security_id, port_defn.notional_currency_code, port_defn.asset_type_code, port_defn.portfolio_type_code, port_defn.book_currency_code, port_defn.book_code, port_defn.account_code 
), 
 risk_stats_info 
 as 
 ( 
     select as_of_date, security_id,  
      (case when sum(case when  risk_factor_type_code='RISKNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end )=0 then 1 else sum(case when  risk_factor_type_code='RISKNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end ) end) RISKNTL, 
      (case when sum(case when  risk_factor_type_code='INITNTL' then stats_val else 0 end ) = 0 then  
        (case when sum(case when  risk_factor_type_code='RISKNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end )=0 then 1 else sum(case when  risk_factor_type_code='RISKNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end ) end)  
       else 
        (case when sum(case when  risk_factor_type_code='INITNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end )=0 then 1 else sum(case when  risk_factor_type_code='INITNTL' then (case when stats_val is null or stats_val=0 then 1 else stats_val end ) else 0 end ) end) 
       end  
      ) INITNTL, 
      sum(case when  risk_factor_type_code='BERY' then stats_val else 0 end ) BERY, 
      sum(case when  risk_factor_type_code='RATE' then stats_val else 0 end ) RATE, 
      sum(case when  risk_factor_type_code='DM_DISC' then stats_val else 0 end ) DM_DISC,    ---FUT/OPT Total DV01 - to be fixed 
      sum(case when  risk_factor_type_code='DM_LIBOR' then stats_val else 0 end ) DM_LIBOR, 
      sum(case when  risk_factor_type_code='CONV' then stats_val else 0 end ) CONV, 
      sum(case when  risk_factor_type_code='VEGA' then stats_val else 0 end ) VEGA 
     from  
     ( 
      select srs.as_of_date, srs.security_id, srs.stats_val, srs.risk_factor_id, rf.risk_factor_type_code 
      from  
       treasperf.security_risk_stats srs, 
       treasperf.risk_factor rf, 
       (select distinct security_id, as_of_date, srs.risk_factor_id, 
               MAX (run_dt) OVER ( PARTITION BY security_id, as_of_date, rf1.risk_factor_type_code) max_run_dt, 
               MAX ( version_nbr) KEEP (DENSE_RANK FIRST ORDER BY run_dt DESC NULLS LAST) OVER ( PARTITION BY security_id, as_of_date, rf1.risk_factor_type_code) max_version_nbr 
        from  
         treasperf.security_risk_stats srs, 
         treasperf.risk_factor rf1 
         where srs.as_of_date=:asofDate
         and rf1.risk_factor_id=srs.risk_factor_id 
         and rf1.risk_factor_type_code in ('RISKNTL','RATE','DM_DISC','DM_LIBOR','CONV','BERY', 'INITNTL','VEGA') 
        ) max_stats_info   
      where  
        srs.security_id=max_stats_info.security_id 
        and srs.risk_factor_id=max_stats_info.risk_factor_id 
        and srs.as_of_date=max_stats_info.as_of_date 
        and srs.run_dt=max_stats_info.max_run_dt 
        and srs.version_nbr=max_stats_info.max_version_nbr 
        and rf.risk_factor_id=srs.risk_factor_id 
     ) 
     group by security_id, as_of_date 
),  
 ir_risk_info 
 AS  
  (SELECT rf.term_bucket_code, 
            rf.risk_factor_type_code, 
            rf.currency_code, 
            RF.CURVE_ID, 
            srs.security_id, srs.risk_factor_id, srs.as_of_date, (case when rf.risk_factor_type_code='KRS' and sm.asset_type_code<>'BOND' then 0 else srs.value end) value, (case when rf.risk_factor_type_code='KRS' and sm.asset_type_code<>'BOND' then 0 else srs.risk_amt end) risk_amt, srs.term_date, srs.run_dt, srs.version_nbr, srs.user_id, srs.datetime_stamp 
       FROM TREASPERF.SECURITY_TOTAL_IR_SENSITIVITY srs, treasperf.security_master sm, 
            (SELECT DISTINCT 
                    srs1.security_id, srs1.as_of_date, 
                    MAX ( srs1.run_dt)  OVER ( PARTITION BY srs1.security_id, srs1.as_of_date) max_run_dt, 
                    MAX (srs1.version_nbr) KEEP (DENSE_RANK FIRST ORDER BY srs1.run_dt DESC NULLS LAST) OVER ( PARTITION BY srs1.security_id, srs1.as_of_date) max_version_nbr 
               FROM treasperf.SECURITY_TOTAL_IR_SENSITIVITY srs1, 
                    treasperf.risk_factor rf1 
              WHERE rf1.risk_factor_id = srs1.risk_factor_id and srs1.as_of_date=:asofDate) max_risk_info, 
            TREASPERF.RISK_FACTOR rf 
      WHERE     srs.security_id = max_risk_info.security_id 
            AND sm.security_id=srs.security_id 
            AND SRS.AS_OF_DATE = max_risk_info.as_of_date 
            AND srs.run_dt = max_risk_info.max_run_dt 
            AND SRS.VERSION_NBR = max_risk_info.max_version_nbr 
            AND RF.RISK_FACTOR_ID = srs.risk_factor_id 
            AND ABS (ROUND (srs.risk_amt, 2)) > 0 
   )     
select holding_info.AS_OF_DATE, replace(replace(replace(replace(replace(holding_info.SECURITY_ID,'~','_'),'Bought','FXBUY'),'Sold','FXSELL'),'~REPO~CLASSIC',''),'~REV~CLASSIC','') security_id, 
 holding_info.secid SEC_TRADE_ID, holding_info.cusip, holding_info.isin, holding_info.oth,  
    holding_info.maturity_dt, holding_info.BOOK_CURRENCY_CODE, nvl(risk_data.CURRENCY_CODE,holding_info.notional_currency_code) currency_code, holding_info.ASSET_TYPE_CODE, -- holding_info.PORTFOLIO_TYPE_CODE,  
  holding_info.BOOK_CODE, holding_info.ACCOUNT_CODE, holding_info.TRADE_STRATEGY_CODE,  
    holding_info.ISSUER_CNTRY,
    (case when holding_info.COLL_CNTRY_CODE is null then  holding_info.ISSUER_CNTRY else holding_info.COLL_CNTRY_CODE end) CNTRY_OF_RISK,
    holding_info.EXT_REF , holding_info.LEVEL_1_SECTOR_CODE, holding_info.LEVEL_2_SECTOR_CODE, holding_info.COLLATERAL_TYPE_CODE, 
    round((case when holding_info.asset_type_code='BOND' then (current_ntl_amt/(RISKNTL))*INITNTL else null end),0) quantity, 
    (case when holding_info.asset_type_code='BOND' then nvl(risk_stats_info.RISKNTL, holding_info.curr_ntl_amt)/nvl(risk_stats_info.INITNTL, holding_info.curr_ntl_amt) else null end) factor, 
    holding_info.current_ntl_amt CURR_NTL_AMT, holding_info.CURR_NTL_BOOK_CCY_AMT, pricing.price_val price, pricing.accrued_val accrued, 
    (case when holding_info.asset_type_code='FXOPT' and risk_data.CURRENCY_CODE<>holding_info.notional_currency_code then 0 else holding_info.MARKET_VALUE_AMT end) market_value_amt, 
    (case when holding_info.asset_type_code='FXOPT' and risk_data.CURRENCY_CODE<>holding_info.notional_currency_code then 0 else holding_info.MARKET_VALUE_BOOK_CCY_AMT end)*fx.rate  market_value_book_ccy_amt, 
    holding_info.PENDING_CF_ADJ_AMT, holding_info.PENDING_CF_ADJ_BK_CCY_AMT,  
    holding_info.PENDING_CF_AMT, holding_info.PENDING_CF_BOOK_CCY_AMT, holding_info.CAPITAL_GL_AMT, holding_info.CAPITAL_GL_BOOK_CCY_AMT, 
    (case when holding_info.asset_type_code='FXOPT' and risk_data.CURRENCY_CODE<>holding_info.notional_currency_code then 0 else holding_info.CURRENCY_GL_AMT end) currency_gl_amt, holding_info.ACCRUAL_AMT, holding_info.ACCRUAL_BOOK_CCY_AMT, 
    (case when holding_info.asset_type_code='FXOPT' and risk_data.CURRENCY_CODE<>holding_info.notional_currency_code then 0 else holding_info.INCOME_AMT end) income_amt, 
    (case when holding_info.asset_type_code='FXOPT' and risk_data.CURRENCY_CODE<>holding_info.notional_currency_code then 0 else holding_info.INCOME_BOOK_CCY_AMT end) income_book_ccy_amt, 
     risk_stats_info.rate, risk_stats_info.bery, risk_stats_info.dm_disc, risk_stats_info.dm_libor,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * (case when holding_info.asset_type_code in ('FUT','LOPT') then TOTAL_DV01 else TOTAL_PARALLEL_DV01 end) +   
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TOTAL_PARALLEL_RESDV01 + nvl(settle_risk.settle_total_parallel_dv01, 0) TOTAL_PARALLEL_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * (case when holding_info.asset_type_code in ('FUT','LOPT') then CONV else TOTAL_PARALLEL_CONV end) +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * total_parallel_res_conv  + nvl(settle_risk.settle_total_parallel_conv, 0) TOTAL_PARALLEL_CONV,  
    risk_stats_info.vega*0.01*holding_info.CURR_NTL_AMT VEGA, 
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * TOTAL_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TOTAL_RES_DV01 +  nvl(settle_risk.settle_total_dv01, 0) TOTAL_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * ONE_D_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * ONE_D_RESDV01 +  nvl(settle_risk.settle_one_d_dv01, 0) ONE_D_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * ONE_W_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * ONE_W_RESDV01 +  nvl(settle_risk.settle_one_w_dv01, 0) ONE_W_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_M_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * ONE_M_RESDV01 +  nvl(settle_risk.settle_one_m_dv01, 0) ONE_M_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THREE_M_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * THREE_M_RESDV01 +  nvl(settle_risk.settle_three_m_dv01, 0) THREE_M_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SIX_M_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * SIX_M_RESDV01 +  nvl(settle_risk.settle_six_m_dv01, 0) SIX_M_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * ONE_YR_RESDV01 +  nvl(settle_risk.settle_one_yr_dv01, 0) ONE_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWO_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TWO_YR_RESDV01 +  nvl(settle_risk.settle_two_yr_dv01, 0) TWO_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THREE_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * THREE_YR_RESDV01 +  nvl(settle_risk.settle_three_yr_dv01, 0) THREE_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FOUR_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * FOUR_YR_RESDV01 +  nvl(settle_risk.settle_four_yr_dv01, 0) FOUR_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FIVE_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * FIVE_YR_RESDV01 +  nvl(settle_risk.settle_five_yr_dv01, 0) FIVE_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SIX_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * SIX_YR_RESDV01 +  nvl(settle_risk.settle_six_yr_dv01, 0) SIX_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SEVEN_YR_DV01 + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * SEVEN_YR_RESDV01 +  nvl(settle_risk.settle_seven_yr_dv01, 0) SEVEN_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * EIGHT_YR_DV01 + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * EIGHT_YR_RESDV01 +  nvl(settle_risk.settle_eight_yr_dv01, 0) EIGHT_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * NINE_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * NINE_YR_RESDV01 +  nvl(settle_risk.settle_nine_yr_dv01, 0) NINE_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TEN_YR_DV01 +  
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TEN_YR_RESDV01 +  nvl(settle_risk.settle_ten_yr_dv01, 0) TEN_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FIFTN_YR_DV01 + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * FIFTN_YR_RESDV01 +  nvl(settle_risk.settle_fiftn_yr_dv01, 0) FIFTN_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWNTY_YR_DV01 + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TWNTY_YR_RESDV01 +  nvl(settle_risk.settle_twnty_yr_dv01, 0) TWNTY_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWNTYFV_YR_DV01 + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TWNTYFV_YR_RESDV01 +  nvl(settle_risk.settle_twntyfv_yr_dv01, 0) TWNTYFV_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THIRTY_YR_DV01  + 
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * THIRTY_YR_RESDV01 +  nvl(settle_risk.settle_thirty_yr_dv01, 0) THIRTY_YR_DV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TOTAL_SPDDV01 TOTAL_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_D_SPDDV01 ONE_D_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_W_SPDDV01 ONE_W_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_M_SPDDV01 ONE_M_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THREE_M_SPDDV01 THREE_M_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SIX_M_SPDDV01 SIX_M_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * ONE_YR_SPDDV01 ONE_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWO_YR_SPDDV01 TWO_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THREE_YR_SPDDV01 THREE_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FOUR_YR_SPDDV01 FOUR_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FIVE_YR_SPDDV01 FIVE_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SIX_YR_SPDDV01 SIX_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * SEVEN_YR_SPDDV01 SEVEN_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * EIGHT_YR_SPDDV01 EIGHT_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * NINE_YR_SPDDV01 NINE_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TEN_YR_SPDDV01 TEN_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * FIFTN_YR_SPDDV01 FIFTN_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWNTY_YR_SPDDV01 TWNTY_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * TWNTYFV_YR_SPDDV01 TWNTYFV_YR_SPDDV01,  
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end )  * THIRTY_YR_SPDDV01 THIRTY_YR_SPDDV01,  
    (case when holding_info.asset_type_code='BOND' then    (case when abs(round((holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then holding_info.curr_ntl_amt else risk_stats_info.riskntl end))  * TOTAL_PARALLEL_DV01  +
    (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) * TOTAL_PARALLEL_RESDV01 + nvl(settle_risk.settle_total_parallel_dv01, 0),0)- round((holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then holding_info.curr_ntl_amt else risk_stats_info.riskntl end) )  * TOTAL_SPDDV01,0))<10 then 'FIXED' else 'FLOAT' end)
    when holding_info.asset_type_code in ('FUT','LOPT') then ''
    when holding_info.asset_type_code in ('FXSPOT','FXFWD','FXOPT','SWOPT') then 'N.A.' Else (case when risk_stats_info.rate=0 then 'FLOAT' else 'FIXED' end)      end)  FixFloat, 
    (case when holding_info.asset_type_code in ('BOND','FUT','LOPT') then (holding_info.curr_ntl_amt/(case when risk_stats_info.riskntl is null or risk_stats_info.riskntl=0 then (case when holding_info.curr_ntl_amt=0 then 1 else holding_info.curr_ntl_amt end) else risk_stats_info.riskntl end) ) else 1 end ) * (case when holding_info.asset_type_code in ('FUT','LOPT') then TOTAL_DV01 else TOTAL_INST_DV01 end) +   
    (case when holding_info.asset_type_code='BOND' then (holding_info.curr_res_ntl_amt/risk_stats_info.riskntl) else 0 end) * TOTAL_PARALLEL_RESDV01 + nvl(settle_risk.settle_total_parallel_dv01, 0) TOTAL_INST_DV01, replace(holding_info.external_trade_id,'NA','') ExtId 
from  
  holding_info,  
  treasperf.pricing ,  
  risk_stats_info,   
  treasperf.exchange_rate fx,   
  settle_risk, 
  (  
     SELECT ir1.as_of_date, ir1.security_id, ir1.currency_code, ir1.curve_id, max(run_dt) run_dt, max(version_nbr) version_nbr, 
         sum(CASE WHEN ir1.risk_factor_type_code IN ('KRD', 'KRDT') and ir1.term_bucket_code='ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_PARALLEL_DV01, 
          sum(CASE WHEN ir1.risk_factor_type_code IN ('KRD', 'KRDT') and ir1.term_bucket_code='MPL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_INST_DV01, 
         sum(CASE WHEN ir1.risk_factor_type_code IN ('KRC', 'KRCT') and ir1.term_bucket_code='ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_PARALLEL_CONV, 
         sum(CASE WHEN ir1.risk_factor_type_code IN ('KRD', 'KRDT') and ir1.term_bucket_code not in ('ALL','MPL') THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_DV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='1D' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_D_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='1D' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_D_CONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='1W' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_W_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='1W' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_W_CONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='1M' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_M_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='1M' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_M_CONV,                      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='3M' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_M_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='3M' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_M_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='6M' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_M_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='6M' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_M_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='1Y' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='1Y' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='2Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWO_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='2Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWO_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='3Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='3Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='4Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FOUR_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='4Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FOUR_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='5Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIVE_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='5Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIVE_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='6Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='6Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='7Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SEVEN_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='7Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SEVEN_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='8Y' THEN ir1.risk_amt * er.rate ELSE 0 END) EIGHT_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='8Y' THEN ir1.risk_amt * er.rate ELSE 0 END) EIGHT_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='9Y' THEN ir1.risk_amt * er.rate ELSE 0 END) NINE_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='9Y' THEN ir1.risk_amt * er.rate ELSE 0 END) NINE_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='10Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TEN_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='10Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TEN_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='15Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIFTN_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='15Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIFTN_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='20Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTY_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='20Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTY_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='25Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTYFV_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='25Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTYFV_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code='KRDT' and ir1.term_bucket_code='30Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THIRTY_YR_DV01, sum(CASE WHEN ir1.risk_factor_type_code='KRCT' and ir1.term_bucket_code='30Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THIRTY_YR_CONV,      
         sum(CASE WHEN ir1.risk_factor_type_code in ('KRC','KRCT') and ir1.term_bucket_code<>'ALL' THEN ir1.risk_amt * er.rate ELSE 0 END)  convexity, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code<>'ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_SPDDV01,  
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='1D' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_D_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='1W' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_W_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='1M' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_M_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='3M' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_M_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='6M' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_M_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='1Y' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='2Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWO_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='3Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='4Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FOUR_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='5Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIVE_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='6Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='7Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SEVEN_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='8Y' THEN ir1.risk_amt * er.rate ELSE 0 END) EIGHT_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='9Y' THEN ir1.risk_amt * er.rate ELSE 0 END) NINE_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='10Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TEN_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='15Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIFTN_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='20Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTY_YR_SPDDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='25Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTYFV_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRS' and ir1.term_bucket_code='30Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THIRTY_YR_SPDDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_PARALLEL_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code<>'ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) TOTAL_RES_DV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' THEN ir1.risk_amt * er.rate ELSE 0 END)  total_res_convexity, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='ALL' THEN ir1.risk_amt * er.rate ELSE 0 END) total_parallel_res_conv,   
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='1D' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_D_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='1W' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_W_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='1M' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_M_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='3M' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_M_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='6M' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_M_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='1Y' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='2Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWO_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='3Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='4Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FOUR_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='5Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIVE_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='6Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='7Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SEVEN_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='8Y' THEN ir1.risk_amt * er.rate ELSE 0 END) EIGHT_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='9Y' THEN ir1.risk_amt * er.rate ELSE 0 END) NINE_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='10Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TEN_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='15Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIFTN_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='20Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTY_YR_RESDV01, sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='25Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTYFV_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRDTR' and ir1.term_bucket_code='30Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THIRTY_YR_RESDV01, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='1D' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_D_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='1W' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_W_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='1M' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_M_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='3M' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_M_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='6M' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_M_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='1Y' THEN ir1.risk_amt * er.rate ELSE 0 END) ONE_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='2Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWO_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='3Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THREE_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='4Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FOUR_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='5Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIVE_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='6Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SIX_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='7Y' THEN ir1.risk_amt * er.rate ELSE 0 END) SEVEN_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='8Y' THEN ir1.risk_amt * er.rate ELSE 0 END) EIGHT_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='9Y' THEN ir1.risk_amt * er.rate ELSE 0 END) NINE_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='10Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TEN_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='15Y' THEN ir1.risk_amt * er.rate ELSE 0 END) FIFTN_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='20Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTY_YR_RESCONV, sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='25Y' THEN ir1.risk_amt * er.rate ELSE 0 END) TWNTYFV_YR_RESCONV, 
         sum(CASE WHEN ir1.risk_factor_type_code='KRCTR' and ir1.term_bucket_code='30Y' THEN ir1.risk_amt * er.rate ELSE 0 END) THIRTY_YR_RESCONV  
    FROM ir_risk_info ir1, treasperf.exchange_rate er 
    where  
       er.currency_code=ir1.currency_code  
       and er.as_of_date=ir1.as_of_date                
    GROUP BY ir1.as_of_date, ir1.security_id, ir1.currency_code, ir1.curve_id      
  ) risk_data   
where  
      risk_stats_info.security_id(+)=holding_info.security_id 
  and risk_stats_info.as_of_date(+)=holding_info.as_of_date 
  and risk_data.security_id(+)=holding_info.security_id 
  and risk_data.as_of_date(+)=holding_info.as_of_date  
  and settle_risk.as_of_date(+)=holding_info.as_of_date 
  and fx.as_of_date(+)=holding_info.as_of_date 
  and settle_risk.security_id(+)=holding_info.security_id 
  and settle_risk.notional_currency_code(+)=holding_info.notional_currency_code 
  and fx.currency_code(+)=holding_info.book_currency_code 
  and settle_risk.asset_type_code(+)=holding_info.asset_type_code 
  and settle_risk.portfolio_type_code(+)=holding_info.portfolio_type_code 
  and settle_risk.book_currency_code(+)=holding_info.book_currency_code 
  and settle_risk.book_code(+)=holding_info.book_code 
  and settle_risk.account_code(+)=holding_info.account_code  
  and (abs(holding_info.CURR_NTL_AMT) > 1 or abs(holding_info.INCOME_BOOK_CCY_AMT)>1) 
  and pricing.security_id=holding_info.security_id 
  and pricing.as_of_date=holding_info.as_of_date 
  order by book_code, account_code, asset_type_code, maturity_dt, sec_trade_id, currency_code

