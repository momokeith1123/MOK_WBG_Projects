/*
Author      : Mamadou Oumar Keita
Purpose     : Retrieve holding values
Database    : FSMP
Schema      : TREASPERF
Created On  : 2026-07-23
*/
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYYMMDD';

ALTER SESSION SET CURRENT_SCHEMA = TREASPERF;


SELECT
    BOOK_CURRENCY_CODE,
    BOOK_CODE,
    PORTFOLIO_TYPE_CODE,
    TO_CHAR(AS_OF_DATE,'YYYYMMDD') AS AS_OF_DATE,
    TO_CHAR(RUN_DT,'YYYYMMDD') AS RUN_DT,
    VERSION_NBR,
    NOTIONAL_VALUE_AMT,
    NOTIONAL_VALUE_RPT_CCY_AMT,
    HOLDING_VALUE_AMT,
    HOLDING_VALUE_RPT_CCY_AMT,
    CASH_BALANCE_AMT,
    CASH_BAL_RPT_CCY_AMT,
    EXTERNAL_CF_AMT,
    NET_ASSET_VALUE_AMT,
    NET_ASSET_VALUE_RPT_CCY_AMT
FROM (
    SELECT
        PH.*,
        ROW_NUMBER() OVER (
            PARTITION BY 
                         BOOK_CURRENCY_CODE, 
                         BOOK_CODE,
                         PORTFOLIO_TYPE_CODE,
                         AS_OF_DATE
            ORDER BY VERSION_NBR DESC
        ) AS RN
    FROM PORTFOLIO_HOLDING PH
    WHERE AS_OF_DATE >= TO_DATE('30/06/2025','DD/MM/YYYY')
      AND PORTFOLIO_TYPE_CODE = 'A'
)
WHERE RN = 1
and BOOK_CODE = 'P1'
ORDER BY AS_OF_DATE;

select *
from PORTFOLIO_HOLDING
where as_of_date = to_date('30/06/2025', 'DD/MM/YYYY')
order by book_code, portfolio_type_code
