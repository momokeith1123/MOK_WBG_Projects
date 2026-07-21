 SELECT x.as_of_date,           
           'FUTURES~MARGIN' SECURITY_ID,   
          '' SEC_TRADE_ID, 
          '' CUSIP, 
          '' ISIN, 
          '' OTH, 
          '' MATURITY_DT, 
           x.book_currency_code, 
           x.margin_currency_code CURRENCY_CODE, 
          'CASH' ASSET_TYPE_CODE,  
           x.book_code, 
          '' ACCOUNT_CODE, 
          '' TRADE_STRATEGY_CODE,  
          '' ISSUER_CNTRY, 
          '' CNTRY_OF_RISK, 
          '' EXT_REF, 
          '' LEVEL_1_SECTOR_CODE, 
          '' LEVEL_2_SECTOR_CODE, 
          '' COLLATERAL_TYPE_CODE, 
          '' QUANTITY, 
          '' FACTOR, 
            SUM (x.margin_bal_amt) CURR_NTL_AMT, 
            SUM (x.balance_amt_USD) CURR_NTL_BOOK_CCY_AMT, 
          ''  PRICE, 
          ''   ACCRUED, 
            SUM (x.margin_bal_amt) MARKET_VALUE_AMT, 
            SUM (x.balance_amt_USD) MARKET_VALUE_BOOK_CCY_AMT, 
            '' pending_cf_adj_amt, '' pending_cf_adj_bk_ccy_amt, '' pending_cf_amt, '' pending_cf_book_ccy_amt, '' capital_gl_amt, '' capital_gl_book_ccy_amt, 
            SUM (x.currency_gl_amt) currency_gl_AMT, 
            SUM (x.accrual_amt) accrual_amt, 
            SUM (x.accrual_book_ccy_amt) accrual_book_ccy_amt, 
          ''   INCOME_AMT, 
            SUM (x.currency_gl_amt) INCOME_BOOK_CCY_AMT 
    FROM (SELECT f.as_of_date,  
                 f.book_code,  
                 f.margin_currency_code,  
                 f.margin_bal_amt,  
                 f.margin_bal_amt * e.rate balance_amt_USD,  
                 f.currency_gl_amt,  
                 f.daily_int_amt  accrual_amt,  
                 f.daily_int_amt * e.rate accrual_book_ccy_amt,  
                 f.book_currency_code 
            FROM TREASPERF.futures_margin_account f, treasperf.exchange_rate e  
           WHERE     e.currency_code = f.margin_currency_code  
                 AND e.as_of_date = f.as_of_date  
                  AND f.as_of_date = :asofdate
                 AND ABS (f.margin_bal_amt) > 1) x  
GROUP BY as_of_date, margin_currency_code, book_currency_code, book_code 
ORDER BY Book_code      
