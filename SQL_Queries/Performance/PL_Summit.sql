/*
Author      : Mamadou Oumar Keita
Purpose     : Retrieve holding values
Database    : FSMP
Schema      : TREASPERF
Created On  : 2026-07-24
*/

ALTER SESSION SET CURRENT_SCHEMA = TREASPERF;

select aa.TRADE_ID,
       aa.ASSET_TYPE_CODE, 
       sum(aa.INCOME_BOOK_CCY_AMT) DTD, 
       sum(aa.MARKET_VALUE_BOOK_CCY_AMT) MV, 
       sum(aa.CURR_NTL_BOOK_CCY_AMT) notional_USD, 
       sum(aa.NOTIONAL_BEG_AMT) notional
from CURR_TRADE_PERF_V aa
    where aa.as_of_date='31-dec-2025'
    and aa.BOOK_CODE='P1'
    and aa.PORTFOLIO_TYPE_CODE='A'
    --and trade_id like '%71195%'
group by aa.TRADE_ID, aa.ASSET_TYPE_CODE