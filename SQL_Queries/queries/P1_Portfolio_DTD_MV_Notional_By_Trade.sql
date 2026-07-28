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

SELECT
    TRADE_ID,
    ASSET_TYPE_CODE,

    /* Daily P&L */
    SUM(INCOME_BOOK_CCY_AMT)       AS DTD,

    /* Market Value */
    SUM(MARKET_VALUE_BOOK_CCY_AMT) AS MV,

    /* Current Notional (Book Currency) */
    SUM(CURR_NTL_BOOK_CCY_AMT)     AS NOTIONAL_USD,

    /* Beginning Notional */
    SUM(NOTIONAL_BEG_AMT)          AS NOTIONAL,

    /* Reporting Date in YYYYMMDD format */
    TO_CHAR(AS_OF_DATE, 'YYYYMMDD') AS AS_OF_DATE

FROM CURR_TRADE_PERF_V

WHERE AS_OF_DATE = TO_DATE('20251231', 'YYYYMMDD')
  AND BOOK_CODE = 'P1'
  AND PORTFOLIO_TYPE_CODE = 'A'

GROUP BY
    TRADE_ID,
    ASSET_TYPE_CODE,
    TO_CHAR(AS_OF_DATE, 'YYYYMMDD')

ORDER BY
    TRADE_ID;