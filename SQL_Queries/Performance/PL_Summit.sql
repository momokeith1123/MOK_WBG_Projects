/******************************************************************************
 * Query Name : CURR_TRADE_PERF_DTD_MV_NOTIONAL_BY_TRADE.sql
 *
 * Purpose    : Retrieve DTD P&L, Market Value, and Notional amounts
 *              by Trade ID and Asset Type for a given valuation date.
 *
 * Source     : CURR_TRADE_PERF_V
 *
 * Filters    :
 *   - As Of Date        : 2025-12-31
 *   - Book Code         : P1
 *   - Portfolio Type    : A
 *
 * Author     : Mamadou Oumar Keita
 * Date       : 2026-07-13
 ******************************************************************************/
 
 ALTER SESSION SET CURRENT_SCHEMA = TREASPERF;

SELECT
    t.TRADE_ID ,
    p.isin,
    t.ASSET_TYPE_CODE,
    t.book_code,
    SUM(t.INCOME_BOOK_CCY_AMT)       AS DTD,
    SUM(t.MARKET_VALUE_BOOK_CCY_AMT) AS MV,
    SUM (t.accrual_AMT) as AI,
    SUM(t.CURR_NTL_BOOK_CCY_AMT)     AS NOTIONAL_USD,
    SUM(t.NOTIONAL_BEG_AMT)          AS NOTIONAL,
    TO_CHAR(t.AS_OF_DATE, 'YYYYMMDD') AS AS_OF_DATE
    
FROM CURR_TRADE_PERF_V t, 
     (
        select * 
        from TREASPERF.PORTFOLIO_DEFN_MV 
        where maturity_dt >=  TO_DATE('20260724', 'YYYYMMDD')
            and trim(isin) not in ('000000000010', '000000000000' )) p
WHERE t.trade_id = p.trade_id(+)
   and t.security_id = p.security_id (+)
   and t.asset_type_code = p.asset_type_code(+)
   and t.book_code = p.book_code (+)
   and t.PORTFOLIO_TYPE_CODE = p.PORTFOLIO_TYPE_CODE (+)   
   and t.AS_OF_DATE = TO_DATE('20260724', 'YYYYMMDD')
  --AND t.BOOK_CODE = 'P1'
  AND t.PORTFOLIO_TYPE_CODE = 'A'
  --and t.trade_id like '%63928%'

GROUP BY
    t.TRADE_ID,
    p.isin,
    t.ASSET_TYPE_CODE,
    t.book_code,
    TO_CHAR(t.AS_OF_DATE, 'YYYYMMDD')

ORDER BY
     p.isin, t.trade_id;
    
    DESC TREASPERF.PORTFOLIO_DEFN_MV;
    
    
select * from TREASPERF.PORTFOLIO_DEFN_MV where maturity_dt >=  TO_DATE('20260724', 'YYYYMMDD') and trade_id like '%63928%';


 select * 
        from TREASPERF.PORTFOLIO_DEFN_MV 
        where maturity_dt >=  TO_DATE('20260724', 'YYYYMMDD')
            and trim(isin) not in ('000000000010', '000000000000' )
            and trade_id like '%63928%';
            


select * from CURR_TRADE_PERF_V where trade_id like '%63928%' and AS_OF_DATE = TO_DATE('20260724', 'YYYYMMDD');