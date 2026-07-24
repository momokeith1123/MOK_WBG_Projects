/*=============================================================
    TRADE HOLDINGS + PERFORMANCE REPORT

    Purpose:
    Retrieve active portfolio holdings along with:
      - Security information
      - Trade information
      - Market values
      - Notional amounts
      - Pending cash flows
      - Performance metrics
      - Account mapping

    Only the latest run/version is selected for each
    Security + Trade + As Of Date combination.
==============================================================*/

SELECT
    /*---------------------------------------------------------
        Trade Holding Identification
    ---------------------------------------------------------*/
    thd.as_of_date,
    thd.run_dt,
    thd.version_nbr,
    thd.security_id,
    thd.trade_id,

    /*---------------------------------------------------------
        Security Attributes
    ---------------------------------------------------------*/
    sm.asset_type_code,
    sm.notional_currency_code,
    sm.maturity_dt,

    /*---------------------------------------------------------
        Trade Attributes
    ---------------------------------------------------------*/
    t.book_currency_code,
    t.book_code,
    t_def.account_code,
    t.portfolio_type_code,

    /*
    SDR Outstanding Balance (currently not used)

    sdr_bal.currencycode         AS sdr_currencycode,
    sdr_bal.outstandingamt       AS sdr_outstandingamt,
    sdr_bal.outstandingusdamt    AS sdr_outstandingusdamt,
    */

    /*---------------------------------------------------------
        Notional Amounts
    ---------------------------------------------------------*/
    thd.notional_beg_book_ccy_amt,
    thd.notional_chg_book_ccy_amt,

    (
        thd.notional_beg_book_ccy_amt
        + thd.notional_chg_book_ccy_amt
    ) AS curr_ntl_book_ccy_amt,

    /*---------------------------------------------------------
        Market Values
    ---------------------------------------------------------*/
    thd.market_value_amt,
    thd.market_value_book_ccy_amt,

    thd.recv_mkt_val_amt,
    thd.recv_mkt_val_book_ccy_amt,

    /*---------------------------------------------------------
        Pending Cash Flow Adjustments
    ---------------------------------------------------------*/
    thd.pending_cf_book_ccy_amt,
    thd.pending_cf_adj_amt,
    thd.pending_cf_adj_bk_ccy_amt,

    /*---------------------------------------------------------
        Performance Measures
    ---------------------------------------------------------*/
    tp1.accrual_book_ccy_amt,
    tp1.capital_gl_book_cy_amt,
    tp1.cum_capital_gl_amt,

    tp1.currency_gl_amt,
    tp1.daily_cf_book_ccy_amt,
    tp1.fee_book_ccy_amt,

    tp1.income_amt,
    tp1.income_book_ccy_amt,
    tp1.income_discrepancy_amt,

    tp1.receivable_int_book_ccy_amt

FROM treasperf.trade_holding_detail thd


/*=============================================================
    Get Latest Run Date and Version Number
==============================================================*/
JOIN
(
    SELECT DISTINCT
        tp.security_id,
        tp.trade_id,
        tp.as_of_date,

        MAX(tp.run_dt)
            OVER (
                PARTITION BY
                    tp.security_id,
                    tp.trade_id,
                    tp.as_of_date
            ) AS max_run_dt,

        MAX(tp.version_nbr)
            KEEP (
                DENSE_RANK FIRST
                ORDER BY tp.run_dt DESC NULLS LAST
            )
            OVER (
                PARTITION BY
                    tp.security_id,
                    tp.trade_id,
                    tp.as_of_date
            ) AS max_version_nbr

    FROM treasperf.trade_holding_detail tp

    WHERE tp.trade_status_code IN ('P', 'S')

) max_run

    ON thd.security_id = max_run.security_id
   AND thd.trade_id    = max_run.trade_id
   AND thd.as_of_date  = max_run.as_of_date
   AND thd.run_dt      = max_run.max_run_dt
   AND thd.version_nbr = max_run.max_version_nbr


/*=============================================================
    Security Master Information
==============================================================*/
LEFT JOIN
(
    SELECT
        security_id,
        maturity_dt,
        asset_type_code,
        notional_currency_code
    FROM treasperf.security_master
) sm

    ON thd.security_id = sm.security_id


/*=============================================================
    Trade Information
==============================================================*/
LEFT JOIN
(
    SELECT
        security_id,
        trade_id,
        book_currency_code,
        book_code,
        portfolio_type_code,
        active_ind
    FROM treasperf.trade
) t

    ON thd.security_id = t.security_id
   AND thd.trade_id    = t.trade_id


/*=============================================================
    Trade Performance Metrics
==============================================================*/
INNER JOIN
(
    SELECT
        security_id,
        trade_id,
        as_of_date,
        run_dt,
        version_nbr,

        accrual_book_ccy_amt,
        capital_gl_book_cy_amt,
        cum_capital_gl_amt,

        currency_gl_amt,
        daily_cf_book_ccy_amt,
        fee_book_ccy_amt,

        income_amt,
        income_book_ccy_amt,
        income_discrepancy_amt,

        receivable_int_book_ccy_amt

    FROM treasperf.trade_perf

) tp1

    ON thd.security_id = tp1.security_id
   AND thd.trade_id    = tp1.trade_id
   AND thd.as_of_date  = tp1.as_of_date
   AND thd.run_dt      = tp1.run_dt
   AND thd.version_nbr = tp1.version_nbr


/*=============================================================
    SDR Outstanding Balance (Currently Disabled)
==============================================================*/
/*
LEFT JOIN
(
    SELECT
        tradeid,
        asofdate,
        currencycode,
        outstandingamt,
        outstandingusdamt

    FROM datarep.sdr_outstandingbalance

    WHERE tradetypecode = 'BOND'
      AND asofmonth     = ' '

) sdr_bal

    ON thd.trade_id   = sdr_bal.tradeid
   AND thd.as_of_date = sdr_bal.asofdate
*/


/*=============================================================
    Account Mapping
==============================================================*/
LEFT JOIN
(
    SELECT DISTINCT
        security_id,
        trade_id,
        account_code

    FROM treasperf.portfolio_defn_mv

    WHERE
        (
            account_end_dt IS NULL
            OR account_end_dt >= :edate
        )
        AND
        (
            account_eff_dt IS NULL
            OR account_eff_dt <= :edate
        )

) t_def

    ON thd.security_id = t_def.security_id
   AND thd.trade_id    = t_def.trade_id


/*=============================================================
    Filters
==============================================================*/
WHERE 1 = 1

    /* Active Trades Only */
    AND t.active_ind = 'Y'

    /* Reporting Date Range */
    AND thd.as_of_date BETWEEN :sdate AND :edate

    /* Portfolio Type */
    AND t.portfolio_type_code = 'A'


    /*---------------------------------------------------------
        Optional Filters
    ---------------------------------------------------------*/

    -- AND t.book_code = 'P1'
    -- AND t_def.account_code = 'GRE'

    -- AND thd.trade_id = '278502I'

    -- AND thd.recv_mkt_val_book_ccy_amt <> 0
    -- AND thd.market_value_book_ccy_amt  <> 0
    -- AND thd.as_of_date = DATE '2025-07-01'

    -- AND thd.as_of_date = DATE '2026-01-31'
    -- AND account_code = 'E_ALTAFL'
    -- AND book_code = 'P1'

    -- AND thd.pending_cf_adj_bk_ccy_amt <> 0


/*=============================================================
    Sorting
==============================================================*/
ORDER BY
    thd.as_of_date;
